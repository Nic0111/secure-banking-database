/*
RECOVERY MODULE:
Operation - Tail-log backup and complete in-place restore

PURPOSE:
After any manually performed accidental audited data change, discover its whole
database transaction from the DML audit, capture the tail of the log, select the
newest usable encrypted full, compatible differential and every required
transaction-log backup, then restore SmartBankDB to a healthy point approximately
two minutes before capture.

RUN AS:
sa or another sysadmin on the primary SQL Server instance. Run this entire file
once, immediately after the accidental change is demonstrated.

IMPORTANT:
This operation overwrites SmartBankDB and disconnects it by taking the tail with
NORECOVERY. The accidental change is deliberately not scripted here. If an error
occurs after the tail backup succeeds, SmartBankDB can remain in RESTORING; retain
the reported media and resolve the restore error rather than redeploying.

PASS CONDITION:
The exact tail backup is the final log applied with STOPAT and RECOVERY,
SmartBankDB is ONLINE, the complete discovered DML transaction and its optional
application event are absent, restore history matches the selected chain, and
DBCC CHECKDB succeeds.
*/
USE [master];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF IS_SRVROLEMEMBER(N'sysadmin') <> 1
    THROW 52300, 'Run tail-log recovery as sa or another sysadmin.', 1;
IF DB_ID(N'SmartBankDB') IS NULL
    THROW 52301, 'SmartBankDB does not exist on this instance.', 1;
IF (SELECT recovery_model_desc FROM sys.databases WHERE name = N'SmartBankDB') <> N'FULL'
    THROW 52302, 'SmartBankDB must use FULL recovery for tail-log recovery.', 1;
IF (SELECT state_desc FROM sys.databases WHERE name = N'SmartBankDB') <> N'ONLINE'
    THROW 52303, 'SmartBankDB must be ONLINE before this one-pass recovery begins.', 1;
IF NOT EXISTS
(
    SELECT 1 FROM master.sys.certificates
    WHERE name = N'SmartBank_Backup_Certificate'
      AND pvt_key_encryption_type_desc <> N'NO_PRIVATE_KEY'
)
    THROW 52304, 'The backup-encryption certificate and private key must exist in master.', 1;

DECLARE @SourceDatabase sysname = N'SmartBankDB';
DECLARE @CaptureReferenceServerTime datetime = GETDATE();
DECLARE @InitialStopAt datetime = DATEADD(MINUTE, -2, @CaptureReferenceServerTime);
DECLARE @StopAt datetime = @InitialStopAt;
DECLARE @AnchorAuditID bigint;
DECLARE @AccidentEventID bigint;
DECLARE @AccidentOperation sysname;
DECLARE @AccidentTargetType varchar(30);
DECLARE @AccidentTargetID nvarchar(128);
DECLARE @AccidentCorrelationID uniqueidentifier;
DECLARE @AccidentTimeUtc datetime2(3);
DECLARE @AccidentTimeServer datetime;
DECLARE @AccidentActor sysname;
DECLARE @BackupDirectory nvarchar(4000);
DECLARE @Separator nvarchar(2);
DECLARE @CurrentDatabaseGuid uniqueidentifier;
DECLARE @CurrentRecoveryForkGuid uniqueidentifier;

SELECT @BackupDirectory = ConfigValue
FROM SmartBankDB.ops.Configuration
WHERE ConfigKey = N'BackupDirectory';
SELECT @Separator = ConfigValue
FROM SmartBankDB.ops.Configuration
WHERE ConfigKey = N'PathSeparator';
SELECT @CurrentDatabaseGuid = database_guid,
       @CurrentRecoveryForkGuid = recovery_fork_guid
FROM sys.database_recovery_status
WHERE database_id = DB_ID(@SourceDatabase);

IF NULLIF(@BackupDirectory, N'') IS NULL OR NULLIF(@Separator, N'') IS NULL
    THROW 52305, 'SmartBankDB backup directory or path separator is not configured.', 1;
IF @CurrentDatabaseGuid IS NULL OR @CurrentRecoveryForkGuid IS NULL
    THROW 52306, 'Current database recovery metadata is unavailable.', 1;

CREATE TABLE #AccidentDml
(
    AuditID bigint NOT NULL PRIMARY KEY,
    EventTime datetime2(3) NOT NULL,
    ActionType varchar(6) NOT NULL,
    SchemaName sysname NOT NULL,
    TableName sysname NOT NULL,
    AffectedRowCount int NOT NULL,
    ActorLogin sysname NOT NULL,
    TransactionID bigint NULL,
    CorrelationID uniqueidentifier NULL,
    OldValues nvarchar(max) NULL,
    NewValues nvarchar(max) NULL
);

-- The newest DML audit row is the anchor. Actor, table, key, role, action type,
-- procedure and correlation ID are all discovered rather than supplied.
SELECT TOP (1)
       @AnchorAuditID = AuditID,
       @AccidentActor = ActorLogin
FROM SmartBankDB.audit.DmlAudit
ORDER BY EventTime DESC, AuditID DESC;

IF @AnchorAuditID IS NULL
    THROW 52307, 'No audited data change was found.', 1;

INSERT #AccidentDml
    (AuditID, EventTime, ActionType, SchemaName, TableName, AffectedRowCount,
     ActorLogin, TransactionID, CorrelationID, OldValues, NewValues)
SELECT AuditID, EventTime, ActionType, SchemaName, TableName, AffectedRowCount,
       ActorLogin, TransactionID, CorrelationID, OldValues, NewValues
FROM SmartBankDB.audit.DmlAudit
WHERE AuditID = @AnchorAuditID;

-- Some audit triggers intentionally omit CorrelationID. Include every row from
-- the same database transaction so any multi-table action stays atomic.
INSERT #AccidentDml
    (AuditID, EventTime, ActionType, SchemaName, TableName, AffectedRowCount,
     ActorLogin, TransactionID, CorrelationID, OldValues, NewValues)
SELECT auditRow.AuditID, auditRow.EventTime, auditRow.ActionType,
       auditRow.SchemaName, auditRow.TableName, auditRow.AffectedRowCount,
       auditRow.ActorLogin, auditRow.TransactionID, auditRow.CorrelationID,
       auditRow.OldValues, auditRow.NewValues
FROM SmartBankDB.audit.DmlAudit AS auditRow
WHERE auditRow.ActorLogin = @AccidentActor
  AND auditRow.EventTime BETWEEN
      DATEADD(MINUTE, -2, (SELECT MIN(EventTime) FROM #AccidentDml))
      AND DATEADD(MINUTE, 2, (SELECT MAX(EventTime) FROM #AccidentDml))
  AND EXISTS
  (
      SELECT 1 FROM #AccidentDml AS correlated
      WHERE correlated.TransactionID = auditRow.TransactionID
  )
  AND NOT EXISTS
  (
      SELECT 1 FROM #AccidentDml AS captured
      WHERE captured.AuditID = auditRow.AuditID
  );

SELECT @AccidentTimeUtc = MIN(EventTime)
FROM #AccidentDml;

SELECT TOP (1) @AccidentCorrelationID = CorrelationID
FROM #AccidentDml
WHERE CorrelationID IS NOT NULL
ORDER BY EventTime DESC, AuditID DESC;

-- Procedure-level metadata enriches the evidence when the change came through
-- an API. Direct audited DML remains valid and simply leaves these values NULL.
IF @AccidentCorrelationID IS NOT NULL
BEGIN
    SELECT TOP (1)
           @AccidentEventID = applicationEvent.EventID,
           @AccidentOperation = applicationEvent.OperationName,
           @AccidentTargetType = applicationEvent.TargetType,
           @AccidentTargetID = applicationEvent.TargetID
    FROM SmartBankDB.audit.ApplicationEvent AS applicationEvent
    WHERE applicationEvent.Succeeded = 1
      AND applicationEvent.ActorLogin = @AccidentActor
      AND applicationEvent.CorrelationID = @AccidentCorrelationID
    ORDER BY applicationEvent.EventTime DESC, applicationEvent.EventID DESC;
END;

SET @AccidentTimeServer = CONVERT
(
    datetime,
    SWITCHOFFSET
    (
        TODATETIMEOFFSET(@AccidentTimeUtc, '+00:00'),
        DATENAME(TZOFFSET, SYSDATETIMEOFFSET())
    )
);

IF @AccidentTimeServer <= @InitialStopAt
    THROW 52308, 'The latest audited change is not newer than the initial two-minute recovery point. Reset safely, then repeat the manual demonstration.', 1;

DECLARE @LatestRegularLogSetID int = NULL;
DECLARE @LatestRegularLogFinish datetime = NULL;
DECLARE @LatestRegularLogLastLsn numeric(25, 0) = NULL;
SELECT TOP (1)
       @LatestRegularLogSetID = backup_set_id,
       @LatestRegularLogFinish = backup_finish_date,
       @LatestRegularLogLastLsn = last_lsn
FROM msdb.dbo.backupset
WHERE database_name = @SourceDatabase
  AND database_guid = @CurrentDatabaseGuid
  AND type = 'L'
  AND is_copy_only = 0
  AND last_recovery_fork_guid = @CurrentRecoveryForkGuid
  AND backup_finish_date <= @CaptureReferenceServerTime
ORDER BY backup_finish_date DESC, backup_set_id DESC;

-- The final restore must reach STOPAT from the tail, not from an earlier regular
-- log. If a scheduled log ended during the two-minute window, move STOPAT just
-- after it, but never across the audited accident.
IF @LatestRegularLogFinish > @StopAt
BEGIN
    IF @LatestRegularLogFinish >= @AccidentTimeServer
        THROW 52312, 'A regular log backup finished at or after the accident. The tail cannot be the final pre-accident log; reset and repeat between scheduled log runs.', 1;
    SET @StopAt = DATEADD(MILLISECOND, 10, @LatestRegularLogFinish);
END;
IF @StopAt >= @AccidentTimeServer
    THROW 52313, 'The calculated recovery point is not before the audited accident.', 1;

DECLARE @FullSetID int;
DECLARE @FullFile nvarchar(4000);
DECLARE @FullLastLsn numeric(25, 0);
DECLARE @FullCheckpointLsn numeric(25, 0);
DECLARE @FullRecoveryForkGuid uniqueidentifier;
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
  AND backupset.database_guid = @CurrentDatabaseGuid
  AND backupset.type = 'D'
  AND backupset.is_copy_only = 0
  AND backupset.backup_finish_date <= @StopAt
  AND backupset.last_recovery_fork_guid = @CurrentRecoveryForkGuid
  AND backupset.has_backup_checksums = 1
  AND backupset.key_algorithm = N'AES_256'
ORDER BY backupset.backup_finish_date DESC, backupset.backup_set_id DESC;

IF @FullSetID IS NULL
    THROW 52314, 'No eligible encrypted/checksummed full backup exists before STOPAT.', 1;
IF (SELECT COUNT(*) FROM msdb.dbo.backupmediafamily AS media
    INNER JOIN msdb.dbo.backupset AS backupset ON backupset.media_set_id = media.media_set_id
    WHERE backupset.backup_set_id = @FullSetID) <> 1
    THROW 52315, 'The selected full backup must use exactly one media family.', 1;

DECLARE @DiffSetID int = NULL;
DECLARE @DiffFile nvarchar(4000) = NULL;
DECLARE @BaseLastLsn numeric(25, 0) = @FullLastLsn;
SELECT TOP (1)
       @DiffSetID = backupset.backup_set_id,
       @DiffFile = media.physical_device_name,
       @BaseLastLsn = backupset.last_lsn
FROM msdb.dbo.backupset AS backupset
INNER JOIN msdb.dbo.backupmediafamily AS media
    ON media.media_set_id = backupset.media_set_id
WHERE backupset.database_name = @SourceDatabase
  AND backupset.database_guid = @CurrentDatabaseGuid
  AND backupset.type = 'I'
  AND backupset.database_backup_lsn = @FullCheckpointLsn
  AND backupset.backup_finish_date <= @StopAt
  AND backupset.last_recovery_fork_guid = @FullRecoveryForkGuid
  AND backupset.has_backup_checksums = 1
  AND backupset.key_algorithm = N'AES_256'
ORDER BY backupset.backup_finish_date DESC, backupset.backup_set_id DESC;

IF @DiffSetID IS NULL
    THROW 52332, 'No compatible encrypted/checksummed differential backup exists before STOPAT.', 1;
IF (SELECT COUNT(*) FROM msdb.dbo.backupmediafamily AS media
        INNER JOIN msdb.dbo.backupset AS backupset ON backupset.media_set_id = media.media_set_id
        WHERE backupset.backup_set_id = @DiffSetID) <> 1
    THROW 52316, 'The selected differential backup must use exactly one media family.', 1;

CREATE TABLE #LogChain
(
    SequenceNo int IDENTITY(1, 1) PRIMARY KEY,
    BackupSetID int NOT NULL UNIQUE,
    BackupFile nvarchar(4000) NOT NULL,
    BackupStartDate datetime NOT NULL,
    BackupFinishDate datetime NOT NULL,
    FirstLsn numeric(25, 0) NOT NULL,
    LastLsn numeric(25, 0) NOT NULL,
    HasChecksum bit NOT NULL,
    KeyAlgorithm nvarchar(32) NULL,
    IsTail bit NOT NULL
);

IF EXISTS
(
    SELECT backupset.backup_set_id
    FROM msdb.dbo.backupset AS backupset
    INNER JOIN msdb.dbo.backupmediafamily AS media
        ON media.media_set_id = backupset.media_set_id
    WHERE backupset.database_name = @SourceDatabase
      AND backupset.database_guid = @CurrentDatabaseGuid
      AND backupset.type = 'L'
      AND backupset.is_copy_only = 0
      AND backupset.last_lsn > @BaseLastLsn
      AND backupset.backup_finish_date <= @CaptureReferenceServerTime
      AND backupset.database_backup_lsn = @FullCheckpointLsn
      AND backupset.first_recovery_fork_guid = @FullRecoveryForkGuid
      AND backupset.last_recovery_fork_guid = @FullRecoveryForkGuid
    GROUP BY backupset.backup_set_id
    HAVING COUNT(*) <> 1
)
    THROW 52317, 'A required regular log backup uses more than one media family.', 1;

INSERT #LogChain
    (BackupSetID, BackupFile, BackupStartDate, BackupFinishDate,
     FirstLsn, LastLsn, HasChecksum, KeyAlgorithm, IsTail)
SELECT backupset.backup_set_id, media.physical_device_name,
       backupset.backup_start_date, backupset.backup_finish_date,
       backupset.first_lsn, backupset.last_lsn,
       backupset.has_backup_checksums, backupset.key_algorithm, 0
FROM msdb.dbo.backupset AS backupset
INNER JOIN msdb.dbo.backupmediafamily AS media
    ON media.media_set_id = backupset.media_set_id
WHERE backupset.database_name = @SourceDatabase
  AND backupset.database_guid = @CurrentDatabaseGuid
  AND backupset.type = 'L'
  AND backupset.is_copy_only = 0
  AND backupset.last_lsn > @BaseLastLsn
  AND backupset.backup_finish_date <= @CaptureReferenceServerTime
  AND backupset.database_backup_lsn = @FullCheckpointLsn
  AND backupset.first_recovery_fork_guid = @FullRecoveryForkGuid
  AND backupset.last_recovery_fork_guid = @FullRecoveryForkGuid
ORDER BY backupset.first_lsn, backupset.backup_start_date, backupset.backup_set_id;

IF EXISTS (SELECT 1 FROM #LogChain WHERE HasChecksum <> 1 OR ISNULL(KeyAlgorithm, N'') <> N'AES_256')
    THROW 52318, 'Every required regular log backup must have checksums and AES-256 encryption.', 1;
IF @LatestRegularLogLastLsn > @BaseLastLsn
   AND NOT EXISTS (SELECT 1 FROM #LogChain WHERE BackupSetID = @LatestRegularLogSetID)
    THROW 52333, 'The latest regular log is not compatible with the selected full/differential base.', 1;

DECLARE @PreviousLastLsn numeric(25, 0) = @BaseLastLsn;
DECLARE @LogSetID int;
DECLARE @LogFile nvarchar(4000);
DECLARE @FirstLsn numeric(25, 0);
DECLARE @LastLsn numeric(25, 0);
DECLARE continuity_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT BackupSetID, BackupFile, FirstLsn, LastLsn
    FROM #LogChain ORDER BY SequenceNo;
OPEN continuity_cursor;
FETCH NEXT FROM continuity_cursor INTO @LogSetID, @LogFile, @FirstLsn, @LastLsn;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF @FirstLsn > @PreviousLastLsn
    BEGIN
        CLOSE continuity_cursor;
        DEALLOCATE continuity_cursor;
        THROW 52319, 'A gap exists in the regular transaction-log chain.', 1;
    END;
    IF @LastLsn > @PreviousLastLsn SET @PreviousLastLsn = @LastLsn;
    FETCH NEXT FROM continuity_cursor INTO @LogSetID, @LogFile, @FirstLsn, @LastLsn;
END;
CLOSE continuity_cursor;
DEALLOCATE continuity_cursor;

-- Verify all existing media before the tail backup makes the database unavailable.
RESTORE VERIFYONLY FROM DISK = @FullFile WITH CHECKSUM;
IF @DiffFile IS NOT NULL
    RESTORE VERIFYONLY FROM DISK = @DiffFile WITH CHECKSUM;
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

DECLARE @TailTimestamp varchar(20) =
    CONVERT(char(8), @CaptureReferenceServerTime, 112) + '_' +
    REPLACE(CONVERT(char(12), @CaptureReferenceServerTime, 114), ':', '');
DECLARE @TailFile nvarchar(4000) = @BackupDirectory + @Separator +
    N'SmartBankDB_TAIL_' + @TailTimestamp + N'_' +
    CONVERT(nvarchar(36), NEWID()) + N'.trn';
DECLARE @RestoreStartedAt datetime = GETDATE();

PRINT N'Preflight passed. Capturing tail to: ' + @TailFile;
BACKUP LOG [SmartBankDB]
TO DISK = @TailFile
WITH COPY_ONLY, NORECOVERY, INIT, COMPRESSION, CHECKSUM,
     ENCRYPTION (ALGORITHM = AES_256, SERVER CERTIFICATE = SmartBank_Backup_Certificate),
     STATS = 10;

DECLARE @TailSetID int;
DECLARE @TailStartDate datetime;
DECLARE @TailFinishDate datetime;
DECLARE @TailFirstLsn numeric(25, 0);
DECLARE @TailLastLsn numeric(25, 0);
DECLARE @TailDatabaseBackupLsn numeric(25, 0);
DECLARE @TailFirstFork uniqueidentifier;
DECLARE @TailLastFork uniqueidentifier;
SELECT TOP (1)
       @TailSetID = backupset.backup_set_id,
       @TailStartDate = backupset.backup_start_date,
       @TailFinishDate = backupset.backup_finish_date,
       @TailFirstLsn = backupset.first_lsn,
       @TailLastLsn = backupset.last_lsn,
       @TailDatabaseBackupLsn = backupset.database_backup_lsn,
       @TailFirstFork = backupset.first_recovery_fork_guid,
       @TailLastFork = backupset.last_recovery_fork_guid
FROM msdb.dbo.backupset AS backupset
INNER JOIN msdb.dbo.backupmediafamily AS media
    ON media.media_set_id = backupset.media_set_id
WHERE backupset.database_name = @SourceDatabase
  AND backupset.type = 'L'
  AND media.physical_device_name = @TailFile
ORDER BY backupset.backup_set_id DESC;

IF @TailSetID IS NULL
    THROW 52320, 'The tail backup completed but its msdb history row was not found.', 1;
IF @TailDatabaseBackupLsn <> @FullCheckpointLsn
   OR @TailFirstFork <> @FullRecoveryForkGuid
   OR @TailLastFork <> @FullRecoveryForkGuid
    THROW 52321, 'The captured tail does not match the selected full-backup recovery path.', 1;
IF @TailFirstLsn > @PreviousLastLsn
    THROW 52322, 'A gap exists between the verified regular logs and the captured tail.', 1;
IF @TailLastLsn <= @PreviousLastLsn
    THROW 52323, 'The captured tail does not advance the selected log chain.', 1;

INSERT #LogChain
    (BackupSetID, BackupFile, BackupStartDate, BackupFinishDate,
     FirstLsn, LastLsn, HasChecksum, KeyAlgorithm, IsTail)
VALUES
    (@TailSetID, @TailFile, @TailStartDate, @TailFinishDate,
     @TailFirstLsn, @TailLastLsn, 1, N'AES_256', 1);

RESTORE VERIFYONLY FROM DISK = @TailFile WITH CHECKSUM;

-- In-place full + compatible differential + every regular log + exact tail.
RESTORE DATABASE [SmartBankDB]
FROM DISK = @FullFile
WITH REPLACE, CHECKSUM, NORECOVERY, STATS = 10;

IF @DiffFile IS NOT NULL
    RESTORE DATABASE [SmartBankDB]
    FROM DISK = @DiffFile
    WITH CHECKSUM, NORECOVERY, STATS = 10;

DECLARE @IsTail bit;
DECLARE restore_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT BackupSetID, BackupFile, IsTail
    FROM #LogChain ORDER BY SequenceNo;
OPEN restore_cursor;
FETCH NEXT FROM restore_cursor INTO @LogSetID, @LogFile, @IsTail;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF @IsTail = 1
        RESTORE LOG [SmartBankDB]
        FROM DISK = @LogFile
        WITH CHECKSUM, STOPAT = @StopAt, RECOVERY, STATS = 5;
    ELSE
        RESTORE LOG [SmartBankDB]
        FROM DISK = @LogFile
        WITH CHECKSUM, STOPAT = @StopAt, NORECOVERY, STATS = 5;

    FETCH NEXT FROM restore_cursor INTO @LogSetID, @LogFile, @IsTail;
END;
CLOSE restore_cursor;
DEALLOCATE restore_cursor;

IF (SELECT state_desc FROM sys.databases WHERE name = @SourceDatabase) <> N'ONLINE'
    THROW 52324, 'SmartBankDB did not finish ONLINE.', 1;
IF EXISTS
(
    SELECT 1
    FROM SmartBankDB.audit.DmlAudit AS restoredAudit
    INNER JOIN #AccidentDml AS accident
        ON accident.AuditID = restoredAudit.AuditID
       AND accident.EventTime = restoredAudit.EventTime
       AND accident.ActorLogin = restoredAudit.ActorLogin
)
    THROW 52327, 'One or more rows from the discovered accidental transaction remain after recovery.', 1;
IF @AccidentEventID IS NOT NULL
   AND EXISTS
   (
       SELECT 1 FROM SmartBankDB.audit.ApplicationEvent
       WHERE EventID = @AccidentEventID
         AND ActorLogin = @AccidentActor
         AND CorrelationID = @AccidentCorrelationID
   )
    THROW 52325, 'The application event associated with the accidental transaction remains after recovery.', 1;
IF (SELECT COUNT(*) FROM msdb.dbo.restorehistory
    WHERE destination_database_name = @SourceDatabase
      AND restore_date >= @RestoreStartedAt
      AND restore_type = 'D'
      AND backup_set_id = @FullSetID) <> 1
    THROW 52328, 'Restore history does not contain the selected full backup.', 1;
IF @DiffSetID IS NOT NULL
   AND (SELECT COUNT(*) FROM msdb.dbo.restorehistory
        WHERE destination_database_name = @SourceDatabase
          AND restore_date >= @RestoreStartedAt
          AND restore_type = 'I'
          AND backup_set_id = @DiffSetID) <> 1
    THROW 52329, 'Restore history does not contain the selected differential backup.', 1;
IF (SELECT COUNT(*) FROM msdb.dbo.restorehistory AS restorehistory
    INNER JOIN #LogChain AS chain ON chain.BackupSetID = restorehistory.backup_set_id
    WHERE restorehistory.destination_database_name = @SourceDatabase
      AND restorehistory.restore_date >= @RestoreStartedAt
      AND restorehistory.restore_type = 'L') <> (SELECT COUNT(*) FROM #LogChain)
    THROW 52330, 'Restore history does not contain every selected log backup.', 1;
IF NOT EXISTS
(
    SELECT 1 FROM msdb.dbo.restorehistory
    WHERE destination_database_name = @SourceDatabase
      AND restore_date >= @RestoreStartedAt
      AND restore_type = 'L'
      AND backup_set_id = @TailSetID
      AND stop_at = @StopAt
      AND recovery = 1
)
    THROW 52331, 'The exact tail backup was not recorded as the final STOPAT recovery.', 1;

DBCC CHECKDB (N'SmartBankDB') WITH NO_INFOMSGS;

SELECT N'PASS' AS OperationResult,
       @CaptureReferenceServerTime AS CaptureReferenceServerTime,
       @InitialStopAt AS InitialTwoMinuteStopAt,
       @StopAt AS AppliedStopAt,
       @AnchorAuditID AS LatestExcludedAuditID,
       (SELECT COUNT(*) FROM #AccidentDml) AS ExcludedAuditRows,
       @AccidentTimeUtc AS AccidentTimeUtc,
       @AccidentTimeServer AS AccidentTimeServer,
       @AccidentActor AS AccidentActor,
       @AccidentOperation AS AccidentOperation,
       @AccidentTargetType AS AccidentTargetType,
       @AccidentTargetID AS AccidentTargetID,
       @AccidentCorrelationID AS AccidentCorrelationID,
       @FullSetID AS FullBackupSetID,
       @FullFile AS FullBackupFile,
       @DiffSetID AS DifferentialBackupSetID,
       @DiffFile AS DifferentialBackupFile,
       @TailSetID AS TailBackupSetID,
       @TailFile AS TailBackupFile,
       (SELECT COUNT(*) FROM #LogChain) AS LogBackupsApplied,
       @RestoreStartedAt AS RestoreStartedAt,
       GETDATE() AS FinishedAt;

SELECT AuditID, EventTime, ActorLogin, ActionType, SchemaName, TableName,
       AffectedRowCount, TransactionID, CorrelationID, OldValues, NewValues
FROM #AccidentDml
ORDER BY EventTime, AuditID;

;WITH SelectedRestoreChain AS
(
    SELECT 1 AS RestoreSequence, N'FULL' AS BackupType,
           backupset.backup_set_id AS BackupSetID, @FullFile AS BackupFile,
           backupset.backup_start_date AS BackupStartDate,
           backupset.backup_finish_date AS BackupFinishDate,
           backupset.first_lsn AS FirstLsn, backupset.last_lsn AS LastLsn,
           backupset.has_backup_checksums AS HasChecksum,
           backupset.key_algorithm AS KeyAlgorithm,
           N'REPLACE + NORECOVERY' AS RestoreAction
    FROM msdb.dbo.backupset AS backupset
    WHERE backupset.backup_set_id = @FullSetID

    UNION ALL

    SELECT 2, N'DIFFERENTIAL', backupset.backup_set_id, @DiffFile,
           backupset.backup_start_date, backupset.backup_finish_date,
           backupset.first_lsn, backupset.last_lsn,
           backupset.has_backup_checksums, backupset.key_algorithm,
           N'NORECOVERY'
    FROM msdb.dbo.backupset AS backupset
    WHERE backupset.backup_set_id = @DiffSetID

    UNION ALL

    SELECT chain.SequenceNo + 2,
           CASE WHEN chain.IsTail = 1 THEN N'TAIL LOG' ELSE N'REGULAR LOG' END,
           chain.BackupSetID, chain.BackupFile,
           chain.BackupStartDate, chain.BackupFinishDate,
           chain.FirstLsn, chain.LastLsn,
           chain.HasChecksum, chain.KeyAlgorithm,
           CASE WHEN chain.IsTail = 1 THEN N'STOPAT + RECOVERY' ELSE N'STOPAT + NORECOVERY' END
    FROM #LogChain AS chain
)
SELECT RestoreSequence, BackupType, BackupSetID, BackupFile,
       BackupStartDate, BackupFinishDate, FirstLsn, LastLsn,
       HasChecksum, KeyAlgorithm, RestoreAction
FROM SelectedRestoreChain
ORDER BY RestoreSequence;

SELECT TOP (20)
       restore_history_id, restore_date, destination_database_name,
       restore_type, backup_set_id, stop_at, recovery
FROM msdb.dbo.restorehistory
WHERE destination_database_name = @SourceDatabase
  AND restore_date >= @RestoreStartedAt
ORDER BY restore_history_id;
GO
