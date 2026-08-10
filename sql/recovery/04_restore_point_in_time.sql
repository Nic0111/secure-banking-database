USE [master];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DECLARE @SourceDatabase sysname = N'SmartBankDB';
DECLARE @TargetDatabase sysname = N'SmartBankDB_PITR';
-- RESTORE ... STOPAT expects the legacy datetime type when supplied through a
-- variable. The marker remains datetime2(3); cast only at the restore boundary.
DECLARE @StopAt datetime =
    (SELECT TOP (1) CONVERT(datetime, MarkerTimeServer)
     FROM SmartBankDB.ops.RecoveryMarker ORDER BY CreatedAt DESC);

IF @StopAt IS NULL THROW 52020, 'No recovery marker exists. Run 02_capture_pitr_marker.sql first.', 1;
IF DB_ID(@TargetDatabase) IS NOT NULL THROW 52021, 'SmartBankDB_PITR already exists. Use 06_cleanup_validation_databases.sql before rerunning.', 1;

DECLARE @FullSetID int, @FullFile nvarchar(4000), @FullLastLsn numeric(25, 0), @FullCheckpointLsn numeric(25, 0);
SELECT TOP (1) @FullSetID = backupset.backup_set_id,
       @FullFile = media.physical_device_name,
       @FullLastLsn = backupset.last_lsn,
       @FullCheckpointLsn = backupset.checkpoint_lsn
FROM msdb.dbo.backupset AS backupset
INNER JOIN msdb.dbo.backupmediafamily AS media ON media.media_set_id = backupset.media_set_id
WHERE backupset.database_name = @SourceDatabase AND backupset.type = 'D'
  AND backupset.is_copy_only = 0 AND backupset.backup_finish_date <= @StopAt
ORDER BY backupset.backup_finish_date DESC;
IF @FullFile IS NULL THROW 52022, 'No full backup exists before the requested recovery time.', 1;

DECLARE @DiffSetID int, @DiffFile nvarchar(4000), @BaseLastLsn numeric(25, 0) = @FullLastLsn;
SELECT TOP (1) @DiffSetID = backupset.backup_set_id,
       @DiffFile = media.physical_device_name,
       @BaseLastLsn = backupset.last_lsn
FROM msdb.dbo.backupset AS backupset
INNER JOIN msdb.dbo.backupmediafamily AS media ON media.media_set_id = backupset.media_set_id
WHERE backupset.database_name = @SourceDatabase AND backupset.type = 'I'
  AND backupset.database_backup_lsn = @FullCheckpointLsn
  AND backupset.backup_finish_date <= @StopAt
ORDER BY backupset.backup_finish_date DESC;

DECLARE @FinalLogSetID int;
SELECT TOP (1) @FinalLogSetID = backup_set_id
FROM msdb.dbo.backupset
WHERE database_name = @SourceDatabase AND type = 'L'
  AND backup_finish_date >= @StopAt AND last_lsn > @BaseLastLsn
ORDER BY backup_finish_date;
IF @FinalLogSetID IS NULL THROW 52023, 'No transaction-log backup covers the recovery marker. Run 03_capture_post_change_log.sql.', 1;

DECLARE @DataPath nvarchar(4000) = CONVERT(nvarchar(4000), SERVERPROPERTY('InstanceDefaultDataPath'));
DECLARE @DataFile nvarchar(4000) = @DataPath + @TargetDatabase + N'.mdf';
DECLARE @LogFile nvarchar(4000) = @DataPath + @TargetDatabase + N'_log.ldf';
DECLARE @Sql nvarchar(max);

SET @Sql = N'RESTORE DATABASE ' + QUOTENAME(@TargetDatabase) + N' FROM DISK = @File
    WITH MOVE N''SmartBankDB'' TO @DataFile, MOVE N''SmartBankDB_log'' TO @LogFile, NORECOVERY, STATS = 10;';
EXEC sys.sp_executesql @Sql,
    N'@File nvarchar(4000), @DataFile nvarchar(4000), @LogFile nvarchar(4000)',
    @FullFile, @DataFile, @LogFile;

IF @DiffFile IS NOT NULL
BEGIN
    SET @Sql = N'RESTORE DATABASE ' + QUOTENAME(@TargetDatabase) + N' FROM DISK = @File WITH NORECOVERY, STATS = 10;';
    EXEC sys.sp_executesql @Sql, N'@File nvarchar(4000)', @DiffFile;
END;

DECLARE @LogSetID int, @LogFilePath nvarchar(4000), @IsFinal bit;
DECLARE log_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT backupset.backup_set_id, media.physical_device_name,
           CONVERT(bit, CASE WHEN backupset.backup_set_id = @FinalLogSetID THEN 1 ELSE 0 END)
    FROM msdb.dbo.backupset AS backupset
    INNER JOIN msdb.dbo.backupmediafamily AS media ON media.media_set_id = backupset.media_set_id
    WHERE backupset.database_name = @SourceDatabase AND backupset.type = 'L'
      AND backupset.last_lsn > @BaseLastLsn AND backupset.backup_set_id <= @FinalLogSetID
    ORDER BY backupset.first_lsn, backupset.backup_start_date;

OPEN log_cursor;
FETCH NEXT FROM log_cursor INTO @LogSetID, @LogFilePath, @IsFinal;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @Sql = N'RESTORE LOG ' + QUOTENAME(@TargetDatabase) + N' FROM DISK = @File
        WITH STOPAT = @StopAt, ' + CASE WHEN @IsFinal = 1 THEN N'RECOVERY' ELSE N'NORECOVERY' END + N', STATS = 5;';
    EXEC sys.sp_executesql @Sql, N'@File nvarchar(4000), @StopAt datetime', @LogFilePath, @StopAt;
    FETCH NEXT FROM log_cursor INTO @LogSetID, @LogFilePath, @IsFinal;
END;
CLOSE log_cursor;
DEALLOCATE log_cursor;

SELECT @StopAt AS RestoredToServerTime, @FullFile AS FullBackupUsed, @DiffFile AS DifferentialBackupUsed,
       @FinalLogSetID AS FinalLogBackupSetID;
SELECT N'Recovered rows at marker' AS Evidence, *
FROM SmartBankDB_PITR.demo.RecoveryTarget ORDER BY RecoveryID;
GO
