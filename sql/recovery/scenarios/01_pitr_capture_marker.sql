/*
RECOVERY MODULE:
Scenario - Capture point-in-time recovery marker

PURPOSE:
Close the log chain before the accident and record the UTC and SQL Server-local
time to which the whole database will be restored.

RUN AS:
sa or another sysadmin on the primary instance.

PRECONDITIONS:
SmartBankDB is ONLINE in FULL recovery and the backup procedure is deployed.

DATABASE CHANGES:
Creates one verified encrypted log backup and one ops.RecoveryMarker row.

PASS CONDITION:
The log backup is successful/verified and a database-wide recovery marker is saved.
*/
USE [SmartBankDB];
GO
SET NOCOUNT ON;
GO

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

-- Save the database-wide recovery time.
DECLARE @MarkerID uniqueidentifier = NEWID();
DECLARE @MarkerTimeUtc datetime2(3) = SYSUTCDATETIME();
DECLARE @MarkerTimeServer datetime2(3) = SYSDATETIME();

INSERT ops.RecoveryMarker
    (MarkerID, MarkerTimeUtc, MarkerTimeServer, MarkerLabel, ExpectedRecoveryRows, CreatedBy)
VALUES
    (@MarkerID, @MarkerTimeUtc, @MarkerTimeServer,
     N'PITR:' + CONVERT(nvarchar(36), @MarkerID) + N' - before lecturer-selected data change',
     N'[]', ORIGINAL_LOGIN());

SELECT N'PASS' AS ScenarioResult,
       @MarkerID AS MarkerID,
       @MarkerTimeUtc AS MarkerTimeUtc,
       @MarkerTimeServer AS MarkerTimeServer,
       @PreMarkerBackupRunID AS PreMarkerBackupRunID,
       @PreMarkerBackupFile AS PreMarkerBackupFile;
GO
