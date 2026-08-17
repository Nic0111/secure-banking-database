/*
RECOVERY MODULE:
Scenario - Validate the accident and close the PITR log chain

PURPOSE:
Refuse to continue until the live recovery target differs from its marker and the
change is audited, then create the verified encrypted log backup needed by restore.

RUN AS:
sa or another sysadmin after the lecturer's controlled DELETE statement(s).

PRECONDITIONS:
scenarios/01_pitr_capture_marker.sql has run and demo.RecoveryTarget was changed.

DATABASE CHANGES:
Creates one verified encrypted transaction-log backup. It does not repair data.

PASS CONDITION:
The source-marker difference and corresponding DML audit row are visible, and the
post-change log backup succeeds and verifies.
*/
USE [SmartBankDB];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF IS_SRVROLEMEMBER(N'sysadmin') <> 1
    THROW 52210, 'Run the post-change log scenario as sa or another sysadmin.', 1;

DECLARE @MarkerID uniqueidentifier, @MarkerTimeUtc datetime2(3),
        @MarkerTimeServer datetime2(3), @ExpectedRowsJson nvarchar(max);
SELECT TOP (1)
       @MarkerID = MarkerID,
       @MarkerTimeUtc = MarkerTimeUtc,
       @MarkerTimeServer = MarkerTimeServer,
       @ExpectedRowsJson = ExpectedRecoveryRows
FROM ops.RecoveryMarker
WHERE MarkerLabel LIKE N'PITR:%'
ORDER BY CreatedAt DESC;
IF @MarkerID IS NULL
    THROW 52211, 'No PITR marker exists. Run scenarios/01_pitr_capture_marker.sql.', 1;

CREATE TABLE #ExpectedRows
(
    RecoveryID int NOT NULL PRIMARY KEY,
    EvidenceText nvarchar(200) NOT NULL,
    CreatedAt datetime2(3) NOT NULL
);
INSERT #ExpectedRows (RecoveryID, EvidenceText, CreatedAt)
SELECT RecoveryID, EvidenceText, CreatedAt
FROM OPENJSON(@ExpectedRowsJson)
WITH
(
    RecoveryID int '$.RecoveryID',
    EvidenceText nvarchar(200) '$.EvidenceText',
    CreatedAt datetime2(3) '$.CreatedAt'
);

CREATE TABLE #SourceDifference
(
    DifferenceType varchar(20) NOT NULL,
    RecoveryID int NOT NULL,
    EvidenceText nvarchar(200) NOT NULL,
    CreatedAt datetime2(3) NOT NULL
);
INSERT #SourceDifference (DifferenceType, RecoveryID, EvidenceText, CreatedAt)
SELECT N'MISSING_OR_CHANGED', RecoveryID, EvidenceText, CreatedAt
FROM
(
    SELECT RecoveryID, EvidenceText, CreatedAt FROM #ExpectedRows
    EXCEPT
    SELECT RecoveryID, EvidenceText, CreatedAt FROM demo.RecoveryTarget
) AS missingRows;
INSERT #SourceDifference (DifferenceType, RecoveryID, EvidenceText, CreatedAt)
SELECT N'EXTRA_OR_CHANGED', RecoveryID, EvidenceText, CreatedAt
FROM
(
    SELECT RecoveryID, EvidenceText, CreatedAt FROM demo.RecoveryTarget
    EXCEPT
    SELECT RecoveryID, EvidenceText, CreatedAt FROM #ExpectedRows
) AS extraRows;

IF NOT EXISTS (SELECT 1 FROM #SourceDifference)
    THROW 52212, 'The live rows still match the marker. Perform the controlled accidental change first.', 1;
IF NOT EXISTS
   (
       SELECT 1 FROM audit.DmlAudit
       WHERE SchemaName = N'demo' AND TableName = N'RecoveryTarget'
         AND ActionType IN ('DELETE', 'UPDATE') AND EventTime >= @MarkerTimeUtc
   )
    THROW 52213, 'The source changed, but no corresponding RecoveryTarget DML audit evidence was found.', 1;

SELECT N'Live source difference from marker' AS Evidence, *
FROM #SourceDifference ORDER BY RecoveryID, DifferenceType;
SELECT TOP (20) N'Audited accidental change' AS Evidence,
       AuditID, EventTime, ActionType, ActorLogin, AffectedRowCount,
       CorrelationID, OldValues, NewValues
FROM audit.DmlAudit
WHERE SchemaName = N'demo' AND TableName = N'RecoveryTarget'
  AND ActionType IN ('DELETE', 'UPDATE') AND EventTime >= @MarkerTimeUtc
ORDER BY EventTime DESC, AuditID DESC;

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

SELECT N'PASS' AS ScenarioResult,
       @MarkerID AS MarkerID,
       @MarkerTimeUtc AS MarkerTimeUtc,
       @MarkerTimeServer AS MarkerTimeServer,
       (SELECT COUNT(*) FROM #SourceDifference) AS DifferenceRows,
       @PostChangeBackupRunID AS PostChangeBackupRunID,
       @PostChangeBackupFile AS PostChangeBackupFile,
       @PostChangeFinishedAt AS PostChangeFinishedAtUtc;
GO
