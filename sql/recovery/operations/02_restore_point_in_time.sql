/*
RECOVERY MODULE:
Operation - Point-in-time restore

PURPOSE:
Select and verify the eligible encrypted full, optional differential and ordered
transaction-log chain, then restore a separate SmartBankDB_PITR copy with STOPAT.

RUN AS:
sa or another sysadmin on the primary SQL Server instance.

PRECONDITIONS:
Run scenarios/01_pitr_capture_marker.sql, perform the controlled accidental change,
and run scenarios/02_pitr_capture_post_change_log.sql.

DATABASE CHANGES:
Creates SmartBankDB_PITR only. It never overwrites SmartBankDB and never uses
WITH REPLACE. If an interrupted target exists, use the confirmation-gated cleanup.

PASS CONDITION:
All selected media pass VERIFYONLY, the LSN chain has no detected gap, STOPAT
completes, and SmartBankDB_PITR is ONLINE.
*/
USE [master];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF IS_SRVROLEMEMBER(N'sysadmin') <> 1
    THROW 52100, 'Run point-in-time restore as sa or another sysadmin.', 1;
IF DB_ID(N'SmartBankDB') IS NULL
    THROW 52101, 'SmartBankDB does not exist on this instance.', 1;
IF (SELECT recovery_model_desc FROM sys.databases WHERE name = N'SmartBankDB') <> N'FULL'
    THROW 52102, 'SmartBankDB must use FULL recovery for point-in-time restore.', 1;
IF DB_ID(N'SmartBankDB_PITR') IS NOT NULL
    THROW 52103, 'SmartBankDB_PITR already exists. Use the explicit cleanup utility before rerunning.', 1;

DECLARE @SourceDatabase sysname = N'SmartBankDB';
DECLARE @TargetDatabase sysname = N'SmartBankDB_PITR';
DECLARE @MarkerID uniqueidentifier, @MarkerTimeUtc datetime2(3),
        @MarkerTimeServer datetime2(3);
SELECT TOP (1)
       @MarkerID = MarkerID,
       @MarkerTimeUtc = MarkerTimeUtc,
       @MarkerTimeServer = MarkerTimeServer
FROM SmartBankDB.ops.RecoveryMarker
WHERE MarkerLabel LIKE N'PITR:%'
ORDER BY CreatedAt DESC;

IF @MarkerID IS NULL OR @MarkerTimeServer IS NULL
    THROW 52104, 'No complete PITR marker exists. Run scenarios/01_pitr_capture_marker.sql.', 1;

-- RESTORE STOPAT uses legacy datetime at the dynamic RESTORE interface. Move the
-- target one representable tick before the marker so it is unambiguously before
-- the lecturer's later accidental change.
DECLARE @StopAt datetime = DATEADD(MILLISECOND, -3, CONVERT(datetime, @MarkerTimeServer));

DECLARE @FullSetID int, @FullFile nvarchar(4000),
        @FullLastLsn numeric(25, 0), @FullCheckpointLsn numeric(25, 0),
        @FullRecoveryForkGuid uniqueidentifier;
SELECT TOP (1)
       @FullSetID = backupset.backup_set_id,
       @FullFile = media.physical_device_name,
       @FullLastLsn = backupset.last_lsn,
       @FullCheckpointLsn = backupset.checkpoint_lsn,
       @FullRecoveryForkGuid = backupset.last_recovery_fork_guid
FROM msdb.dbo.backupset AS backupset
INNER JOIN msdb.dbo.backupmediafamily AS media
    ON media.media_set_id = backupset.media_set_id
WHERE backupset.database_name = @SourceDatabase
  AND backupset.type = 'D' AND backupset.is_copy_only = 0
  AND backupset.backup_finish_date <= @StopAt
  AND backupset.has_backup_checksums = 1
  AND backupset.key_algorithm = N'AES_256'
ORDER BY backupset.backup_finish_date DESC, backupset.backup_set_id DESC;
IF @FullFile IS NULL
    THROW 52107, 'No eligible encrypted/checksummed full backup exists before STOPAT.', 1;
IF (SELECT COUNT(*) FROM msdb.dbo.backupmediafamily AS media
    INNER JOIN msdb.dbo.backupset AS backupset ON backupset.media_set_id = media.media_set_id
    WHERE backupset.backup_set_id = @FullSetID) <> 1
    THROW 52108, 'The recovery operation expects one media family per SmartBank backup set.', 1;

DECLARE @DiffSetID int = NULL, @DiffFile nvarchar(4000) = NULL,
        @BaseLastLsn numeric(25, 0) = @FullLastLsn;
SELECT TOP (1)
       @DiffSetID = backupset.backup_set_id,
       @DiffFile = media.physical_device_name,
       @BaseLastLsn = backupset.last_lsn
FROM msdb.dbo.backupset AS backupset
INNER JOIN msdb.dbo.backupmediafamily AS media
    ON media.media_set_id = backupset.media_set_id
WHERE backupset.database_name = @SourceDatabase
  AND backupset.type = 'I'
  AND backupset.database_backup_lsn = @FullCheckpointLsn
  AND backupset.backup_finish_date <= @StopAt
  AND backupset.has_backup_checksums = 1
  AND backupset.key_algorithm = N'AES_256'
ORDER BY backupset.backup_finish_date DESC, backupset.backup_set_id DESC;
IF @DiffSetID IS NOT NULL
   AND (SELECT COUNT(*) FROM msdb.dbo.backupmediafamily AS media
        INNER JOIN msdb.dbo.backupset AS backupset ON backupset.media_set_id = media.media_set_id
        WHERE backupset.backup_set_id = @DiffSetID) <> 1
    THROW 52109, 'The selected differential uses more than one media family.', 1;

DECLARE @FinalLogSetID int;
SELECT TOP (1) @FinalLogSetID = backup_set_id
FROM msdb.dbo.backupset
WHERE database_name = @SourceDatabase AND type = 'L'
  AND backup_finish_date >= @StopAt AND last_lsn > @BaseLastLsn
  AND database_backup_lsn = @FullCheckpointLsn
  AND first_recovery_fork_guid = @FullRecoveryForkGuid
  AND last_recovery_fork_guid = @FullRecoveryForkGuid
ORDER BY backup_finish_date, backup_set_id;
IF @FinalLogSetID IS NULL
    THROW 52110, 'No transaction-log backup covers STOPAT. Run the post-change log scenario.', 1;

CREATE TABLE #LogChain
(
    SequenceNo int IDENTITY(1, 1) PRIMARY KEY,
    BackupSetID int NOT NULL,
    BackupFile nvarchar(4000) NOT NULL,
    FirstLsn numeric(25, 0) NOT NULL,
    LastLsn numeric(25, 0) NOT NULL,
    HasChecksum bit NOT NULL,
    KeyAlgorithm nvarchar(32) NULL,
    IsFinal bit NOT NULL
);
INSERT #LogChain (BackupSetID, BackupFile, FirstLsn, LastLsn, HasChecksum, KeyAlgorithm, IsFinal)
SELECT backupset.backup_set_id, media.physical_device_name,
       backupset.first_lsn, backupset.last_lsn,
       backupset.has_backup_checksums, backupset.key_algorithm,
       CONVERT(bit, IIF(backupset.backup_set_id = @FinalLogSetID, 1, 0))
FROM msdb.dbo.backupset AS backupset
INNER JOIN msdb.dbo.backupmediafamily AS media
    ON media.media_set_id = backupset.media_set_id
WHERE backupset.database_name = @SourceDatabase AND backupset.type = 'L'
  AND backupset.last_lsn > @BaseLastLsn
  AND backupset.backup_set_id <= @FinalLogSetID
  AND backupset.database_backup_lsn = @FullCheckpointLsn
  AND backupset.first_recovery_fork_guid = @FullRecoveryForkGuid
  AND backupset.last_recovery_fork_guid = @FullRecoveryForkGuid
ORDER BY backupset.first_lsn, backupset.backup_start_date, backupset.backup_set_id;

IF NOT EXISTS (SELECT 1 FROM #LogChain WHERE IsFinal = 1)
    THROW 52111, 'The final log backup is absent from the selected restore chain.', 1;
IF EXISTS (SELECT 1 FROM #LogChain WHERE HasChecksum <> 1 OR ISNULL(KeyAlgorithm, N'') <> N'AES_256')
    THROW 52112, 'Every selected log backup must have checksums and AES-256 encryption.', 1;
IF EXISTS
(
    SELECT BackupSetID FROM #LogChain GROUP BY BackupSetID HAVING COUNT(*) <> 1
)
    THROW 52113, 'The recovery operation expects one media family per transaction-log backup.', 1;

DECLARE @PreviousLastLsn numeric(25, 0) = @BaseLastLsn;
DECLARE @SequenceNo int, @LogSetID int, @LogFile nvarchar(4000),
        @FirstLsn numeric(25, 0), @LastLsn numeric(25, 0), @IsFinal bit;
DECLARE continuity_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT SequenceNo, BackupSetID, BackupFile, FirstLsn, LastLsn, IsFinal
    FROM #LogChain ORDER BY SequenceNo;
OPEN continuity_cursor;
FETCH NEXT FROM continuity_cursor
INTO @SequenceNo, @LogSetID, @LogFile, @FirstLsn, @LastLsn, @IsFinal;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF @FirstLsn > @PreviousLastLsn
    BEGIN
        CLOSE continuity_cursor;
        DEALLOCATE continuity_cursor;
        THROW 52114, 'A gap was detected in the selected transaction-log LSN chain.', 1;
    END;
    IF @LastLsn > @PreviousLastLsn SET @PreviousLastLsn = @LastLsn;
    FETCH NEXT FROM continuity_cursor
    INTO @SequenceNo, @LogSetID, @LogFile, @FirstLsn, @LastLsn, @IsFinal;
END;
CLOSE continuity_cursor;
DEALLOCATE continuity_cursor;

DECLARE @DataLogicalName sysname, @LogLogicalName sysname;
SELECT @DataLogicalName = logical_name
FROM msdb.dbo.backupfile
WHERE backup_set_id = @FullSetID AND file_type = 'D';
SELECT @LogLogicalName = logical_name
FROM msdb.dbo.backupfile
WHERE backup_set_id = @FullSetID AND file_type = 'L';
IF @DataLogicalName IS NULL OR @LogLogicalName IS NULL
    THROW 52115, 'Logical data/log file metadata is missing from the selected full backup.', 1;

DECLARE @DefaultDataPath nvarchar(4000) = CONVERT(nvarchar(4000), SERVERPROPERTY('InstanceDefaultDataPath'));
IF NULLIF(@DefaultDataPath, N'') IS NULL
    THROW 52116, 'InstanceDefaultDataPath is unavailable; configure a default data path before recovery.', 1;
DECLARE @TargetDataFile nvarchar(4000) = @DefaultDataPath + @TargetDatabase + N'.mdf';
DECLARE @TargetLogFile nvarchar(4000) = @DefaultDataPath + @TargetDatabase + N'_log.ldf';
DECLARE @Sql nvarchar(max);
DECLARE @StartedAtUtc datetime2(3) = SYSUTCDATETIME();

RESTORE VERIFYONLY FROM DISK = @FullFile WITH CHECKSUM;
IF @DiffFile IS NOT NULL RESTORE VERIFYONLY FROM DISK = @DiffFile WITH CHECKSUM;
DECLARE verify_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT BackupFile FROM #LogChain ORDER BY SequenceNo;
OPEN verify_cursor;
FETCH NEXT FROM verify_cursor INTO @LogFile;
WHILE @@FETCH_STATUS = 0
BEGIN
    RESTORE VERIFYONLY FROM DISK = @LogFile WITH CHECKSUM;
    FETCH NEXT FROM verify_cursor INTO @LogFile;
END;
CLOSE verify_cursor;
DEALLOCATE verify_cursor;

SET @Sql = N'RESTORE DATABASE ' + QUOTENAME(@TargetDatabase) + N'
             FROM DISK = @BackupFile
             WITH MOVE N''' + REPLACE(@DataLogicalName, N'''', N'''''') + N''' TO @DataFile,
                  MOVE N''' + REPLACE(@LogLogicalName, N'''', N'''''') + N''' TO @LogFile,
                  CHECKSUM, NORECOVERY, STATS = 10;';
EXEC sys.sp_executesql @Sql,
     N'@BackupFile nvarchar(4000), @DataFile nvarchar(4000), @LogFile nvarchar(4000)',
     @FullFile, @TargetDataFile, @TargetLogFile;

IF @DiffFile IS NOT NULL
BEGIN
    SET @Sql = N'RESTORE DATABASE ' + QUOTENAME(@TargetDatabase) + N'
                 FROM DISK = @BackupFile WITH CHECKSUM, NORECOVERY, STATS = 10;';
    EXEC sys.sp_executesql @Sql, N'@BackupFile nvarchar(4000)', @DiffFile;
END;

DECLARE restore_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT BackupSetID, BackupFile, IsFinal FROM #LogChain ORDER BY SequenceNo;
OPEN restore_cursor;
FETCH NEXT FROM restore_cursor INTO @LogSetID, @LogFile, @IsFinal;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF @IsFinal = 1
    BEGIN
        SET @Sql = N'RESTORE LOG ' + QUOTENAME(@TargetDatabase) + N'
                     FROM DISK = @BackupFile
                     WITH CHECKSUM, STOPAT = @StopAt, RECOVERY, STATS = 5;';
        EXEC sys.sp_executesql @Sql,
             N'@BackupFile nvarchar(4000), @StopAt datetime', @LogFile, @StopAt;
    END
    ELSE
    BEGIN
        SET @Sql = N'RESTORE LOG ' + QUOTENAME(@TargetDatabase) + N'
                     FROM DISK = @BackupFile WITH CHECKSUM, NORECOVERY, STATS = 5;';
        EXEC sys.sp_executesql @Sql, N'@BackupFile nvarchar(4000)', @LogFile;
    END;
    FETCH NEXT FROM restore_cursor INTO @LogSetID, @LogFile, @IsFinal;
END;
CLOSE restore_cursor;
DEALLOCATE restore_cursor;

IF (SELECT state_desc FROM sys.databases WHERE name = @TargetDatabase) <> N'ONLINE'
    THROW 52117, 'Point-in-time target did not finish ONLINE.', 1;

SELECT N'PASS' AS OperationResult,
       @MarkerID AS MarkerID,
       @MarkerTimeUtc AS MarkerTimeUtc,
       @MarkerTimeServer AS MarkerServerTime,
       @StopAt AS RestoredStopAtServerTime,
       @FullSetID AS FullBackupSetID,
       @FullFile AS FullBackupFile,
       @DiffSetID AS DifferentialBackupSetID,
       @DiffFile AS DifferentialBackupFile,
       @FinalLogSetID AS FinalLogBackupSetID,
       (SELECT COUNT(*) FROM #LogChain) AS LogBackupsApplied,
       @StartedAtUtc AS StartedAtUtc,
       SYSUTCDATETIME() AS FinishedAtUtc,
       DATEDIFF(SECOND, @StartedAtUtc, SYSUTCDATETIME()) AS RestoreDurationSeconds;

SELECT SequenceNo, BackupSetID, BackupFile, FirstLsn, LastLsn,
       HasChecksum, KeyAlgorithm, IsFinal
FROM #LogChain ORDER BY SequenceNo;
GO
