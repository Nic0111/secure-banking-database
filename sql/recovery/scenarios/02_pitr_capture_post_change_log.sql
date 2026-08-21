/*
RECOVERY MODULE:
Scenario - Validate the accident and close the PITR log chain

PURPOSE:
Confirm an audited data change happened after the marker, then create the verified
encrypted log backup needed by restore.

RUN AS:
sa or another sysadmin after the lecturer's controlled UPDATE or DELETE statement(s).

PRECONDITIONS:
scenarios/01_pitr_capture_marker.sql has run and an audited table was changed.

DATABASE CHANGES:
Creates one verified encrypted transaction-log backup. It does not repair data.

PASS CONDITION:
The corresponding DML audit row is visible, and the post-change log backup succeeds
and verifies.
*/
USE [SmartBankDB];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF IS_SRVROLEMEMBER(N'sysadmin') <> 1
    THROW 52210, 'Run the post-change log scenario as sa or another sysadmin.', 1;

DECLARE @MarkerID uniqueidentifier, @MarkerTimeUtc datetime2(3),
        @MarkerTimeServer datetime2(3);
SELECT TOP (1)
       @MarkerID = MarkerID,
       @MarkerTimeUtc = MarkerTimeUtc,
       @MarkerTimeServer = MarkerTimeServer
FROM ops.RecoveryMarker
WHERE MarkerLabel LIKE N'PITR:%'
ORDER BY CreatedAt DESC;
IF @MarkerID IS NULL
    THROW 52211, 'No PITR marker exists. Run scenarios/01_pitr_capture_marker.sql.', 1;

-- Confirm the change was recorded by the application's DML audit trail.
IF NOT EXISTS
   (
       SELECT 1 FROM audit.DmlAudit
       WHERE ActionType IN ('DELETE', 'UPDATE')
         AND EventTime > @MarkerTimeUtc
   )
    THROW 52212, 'No audited DELETE or UPDATE exists after the marker. Perform the lecturer-selected change first.', 1;

-- Show the changes that the point-in-time restore will undo.
SELECT TOP (20) AuditID, EventTime, SchemaName, TableName, ActionType, ActorLogin, AffectedRowCount,
       CorrelationID, OldValues, NewValues
FROM audit.DmlAudit
WHERE ActionType IN ('DELETE', 'UPDATE')
  AND EventTime > @MarkerTimeUtc
ORDER BY EventTime DESC, AuditID DESC;

-- Take the closing log backup after the change.
DECLARE @PreviousBackupRunID bigint = ISNULL((SELECT MAX(BackupRunID) FROM ops.BackupRun), 0);
EXEC ops.usp_RunBackup @BackupType = 'L';

DECLARE @PostChangeBackupRunID bigint, @PostChangeBackupFile nvarchar(4000),
        @PostChangeFinishedAt datetime2(3);
SELECT TOP (1)
       @PostChangeBackupRunID = BackupRunID,
       @PostChangeBackupFile = BackupFile,
       @PostChangeFinishedAt = FinishedAt
FROM ops.BackupRun
WHERE BackupRunID > @PreviousBackupRunID AND BackupType = 'L'
  AND Succeeded = 1 AND Verified = 1
ORDER BY BackupRunID DESC;
IF @PostChangeBackupRunID IS NULL
    THROW 52214, 'The post-change encrypted log backup did not produce verified evidence.', 1;

-- Report the audit and backup evidence for the restore step.
SELECT N'PASS' AS ScenarioResult,
       @MarkerID AS MarkerID,
       @MarkerTimeUtc AS MarkerTimeUtc,
       @MarkerTimeServer AS MarkerTimeServer,
       (SELECT COUNT(*) FROM audit.DmlAudit
        WHERE ActionType IN ('DELETE', 'UPDATE') AND EventTime > @MarkerTimeUtc) AS AuditedChangeCount,
       @PostChangeBackupRunID AS PostChangeBackupRunID,
       @PostChangeBackupFile AS PostChangeBackupFile,
       @PostChangeFinishedAt AS PostChangeFinishedAtUtc;
GO
