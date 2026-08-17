/*
ASSIGNMENT SECTION:
Section 3 - Availability

REQUIREMENT:
1. Accidental changes must be recoverable.

RUN AS:
sa, after completing the point-in-time workflow in sql/recovery:
02_capture_pitr_marker.sql, the lecturer's accidental deletion,
03_capture_post_change_log.sql and 04_restore_point_in_time.sql.

EXPECTED RESULT:
The live database differs from the saved marker, while SmartBankDB_PITR exactly
matches every row and value stored in the marker JSON. The deletion is auditable.

PASS CONDITION:
A marker exists, a live accidental change is visible, the PITR database exists,
and the recovered dataset has no missing, extra or altered marker rows.

DATABASE CHANGES:
None. Restore operations remain in sql/recovery and are not duplicated here.
*/
USE [SmartBankDB];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF IS_SRVROLEMEMBER(N'sysadmin') <> 1
    THROW 51300, 'Run recovery evidence as sa or another sysadmin.', 1;

DECLARE @MarkerID uniqueidentifier, @MarkerTimeUtc datetime2(3), @MarkerTimeServer datetime2(3),
        @ExpectedRowsJson nvarchar(max);
SELECT TOP (1)
       @MarkerID = MarkerID,
       @MarkerTimeUtc = MarkerTimeUtc,
       @MarkerTimeServer = MarkerTimeServer,
       @ExpectedRowsJson = ExpectedRecoveryRows
FROM ops.RecoveryMarker
ORDER BY CreatedAt DESC;

IF @MarkerID IS NULL
BEGIN
    SELECT N'NOT READY' AS Result,
           N'Run sql/recovery/02_capture_pitr_marker.sql before the accidental-change scenario.' AS NextAction;
    THROW 51301, 'No point-in-time recovery marker exists.', 1;
END;

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

SELECT @MarkerID AS MarkerID, @MarkerTimeUtc AS MarkerTimeUtc,
       @MarkerTimeServer AS StopAtServerTime,
       (SELECT COUNT(*) FROM #ExpectedRows) AS ExpectedRowsAtMarker,
       (SELECT COUNT(*) FROM demo.RecoveryTarget) AS CurrentLiveRows;

SELECT N'Rows missing or changed in the live database after the accident' AS Evidence, *
FROM
(
    SELECT RecoveryID, EvidenceText, CreatedAt FROM #ExpectedRows
    EXCEPT
    SELECT RecoveryID, EvidenceText, CreatedAt FROM demo.RecoveryTarget
) AS liveDifference
ORDER BY RecoveryID;

SELECT TOP (20) EventTime, ActorLogin, ActionType, SchemaName, TableName,
       AffectedRowCount, OldValues, NewValues
FROM audit.DmlAudit
WHERE SchemaName = N'demo' AND TableName = N'RecoveryTarget'
  AND EventTime >= @MarkerTimeUtc
ORDER BY EventTime DESC, AuditID DESC;

IF NOT EXISTS
   (
       SELECT RecoveryID, EvidenceText, CreatedAt FROM #ExpectedRows
       EXCEPT
       SELECT RecoveryID, EvidenceText, CreatedAt FROM demo.RecoveryTarget
   )
   AND NOT EXISTS
   (
       SELECT RecoveryID, EvidenceText, CreatedAt FROM demo.RecoveryTarget
       EXCEPT
       SELECT RecoveryID, EvidenceText, CreatedAt FROM #ExpectedRows
   )
BEGIN
    SELECT N'NOT READY' AS Result,
           N'The live recovery target still matches the marker; perform the lecturer accidental change first.' AS NextAction;
    THROW 51302, 'No accidental change is visible in the live recovery target.', 1;
END;

IF DB_ID(N'SmartBankDB_PITR') IS NULL
BEGIN
    SELECT N'NOT READY' AS Result,
           N'Run sql/recovery/03_capture_post_change_log.sql and 04_restore_point_in_time.sql.' AS NextAction;
    THROW 51303, 'SmartBankDB_PITR does not exist.', 1;
END;

CREATE TABLE #RecoveredRows
(
    RecoveryID int NOT NULL PRIMARY KEY,
    EvidenceText nvarchar(200) NOT NULL,
    CreatedAt datetime2(3) NOT NULL
);
INSERT #RecoveredRows (RecoveryID, EvidenceText, CreatedAt)
EXEC sys.sp_executesql
    N'SELECT RecoveryID, EvidenceText, CreatedAt
      FROM SmartBankDB_PITR.demo.RecoveryTarget ORDER BY RecoveryID;';

SELECT N'Rows recovered at the point-in-time marker' AS Evidence, *
FROM #RecoveredRows ORDER BY RecoveryID;

IF EXISTS
   (
       SELECT RecoveryID, EvidenceText, CreatedAt FROM #ExpectedRows
       EXCEPT
       SELECT RecoveryID, EvidenceText, CreatedAt FROM #RecoveredRows
   )
   OR EXISTS
   (
       SELECT RecoveryID, EvidenceText, CreatedAt FROM #RecoveredRows
       EXCEPT
       SELECT RecoveryID, EvidenceText, CreatedAt FROM #ExpectedRows
   )
    THROW 51304, 'FAIL - the PITR database does not exactly match the saved recovery marker.', 1;

SELECT N'PASS' AS Result,
       N'The point-in-time restored database exactly matches the pre-accident marker.' AS Evidence,
       (SELECT COUNT(*) FROM #RecoveredRows) AS RecoveredRowCount;
GO
