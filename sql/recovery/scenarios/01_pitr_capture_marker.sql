/*
RECOVERY MODULE:
Scenario - Capture point-in-time recovery marker

PURPOSE:
Close the log chain before the accident and persist the exact expected recovery
rows together with UTC and SQL Server-local recovery times.

RUN AS:
sa or another sysadmin on the primary instance.

PRECONDITIONS:
SmartBankDB is ONLINE in FULL recovery, the backup procedure is deployed, and the
golden demo.RecoveryTarget contains rows 1 through 10.

DATABASE CHANGES:
Creates one verified encrypted log backup and one ops.RecoveryMarker row.

PASS CONDITION:
The log backup is successful/verified and a marker with ten expected rows is saved.
*/
USE [SmartBankDB];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF IS_SRVROLEMEMBER(N'sysadmin') <> 1
    THROW 52200, 'Run the PITR marker scenario as sa or another sysadmin.', 1;
IF (SELECT recovery_model_desc FROM sys.databases WHERE name = DB_NAME()) <> N'FULL'
    THROW 52201, 'SmartBankDB must use FULL recovery.', 1;
IF OBJECT_ID(N'ops.RecoveryMarker', N'U') IS NULL
   OR OBJECT_ID(N'ops.BackupRun', N'U') IS NULL
   OR OBJECT_ID(N'ops.usp_RunBackup', N'P') IS NULL
   OR OBJECT_ID(N'demo.RecoveryTarget', N'U') IS NULL
    THROW 52202, 'Required backup/recovery implementation objects are missing.', 1;
IF DB_ID(N'SmartBankDB_PITR') IS NOT NULL
    THROW 52203, 'SmartBankDB_PITR already exists. Run cleanup before starting a new PITR drill.', 1;
IF (SELECT COUNT(*) FROM demo.RecoveryTarget) <> 10
   OR EXISTS
      (
          SELECT expected.RecoveryID
          FROM (VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10)) AS expected(RecoveryID)
          EXCEPT
          SELECT RecoveryID FROM demo.RecoveryTarget
      )
    THROW 52204, 'Restore the golden baseline: RecoveryTarget must contain IDs 1 through 10.', 1;

DECLARE @PreviousBackupRunID bigint = ISNULL((SELECT MAX(BackupRunID) FROM ops.BackupRun), 0);
EXEC ops.usp_RunBackup @BackupType = 'L';

DECLARE @PreMarkerBackupRunID bigint, @PreMarkerBackupFile nvarchar(4000);
SELECT TOP (1)
       @PreMarkerBackupRunID = BackupRunID,
       @PreMarkerBackupFile = BackupFile
FROM ops.BackupRun
WHERE BackupRunID > @PreviousBackupRunID AND BackupType = 'L'
  AND Succeeded = 1 AND Verified = 1
ORDER BY BackupRunID DESC;
IF @PreMarkerBackupRunID IS NULL
    THROW 52205, 'The pre-marker encrypted log backup did not produce verified evidence.', 1;

DECLARE @MarkerID uniqueidentifier = NEWID();
DECLARE @MarkerTimeUtc datetime2(3) = SYSUTCDATETIME();
DECLARE @MarkerTimeServer datetime2(3) = SYSDATETIME();
DECLARE @ExpectedRows nvarchar(max) =
(
    SELECT RecoveryID, EvidenceText, CreatedAt
    FROM demo.RecoveryTarget
    ORDER BY RecoveryID
    FOR JSON PATH, INCLUDE_NULL_VALUES
);

INSERT ops.RecoveryMarker
    (MarkerID, MarkerTimeUtc, MarkerTimeServer, MarkerLabel, ExpectedRecoveryRows, CreatedBy)
VALUES
    (@MarkerID, @MarkerTimeUtc, @MarkerTimeServer,
     N'PITR:' + CONVERT(nvarchar(36), @MarkerID) + N' - before controlled lecturer change',
     @ExpectedRows, ORIGINAL_LOGIN());

-- Make the later manual accident unambiguously newer than the marker even after
-- conversion to RESTORE STOPAT's legacy datetime precision.
WAITFOR DELAY '00:00:01';

SELECT N'PASS' AS ScenarioResult,
       @MarkerID AS MarkerID,
       @MarkerTimeUtc AS MarkerTimeUtc,
       @MarkerTimeServer AS MarkerTimeServer,
       @PreMarkerBackupRunID AS PreMarkerBackupRunID,
       @PreMarkerBackupFile AS PreMarkerBackupFile,
       (SELECT COUNT(*) FROM demo.RecoveryTarget) AS ExpectedRowCount,
       @ExpectedRows AS ExpectedRowsJson;

SELECT RecoveryID, EvidenceText, CreatedAt
FROM demo.RecoveryTarget
ORDER BY RecoveryID;
GO
