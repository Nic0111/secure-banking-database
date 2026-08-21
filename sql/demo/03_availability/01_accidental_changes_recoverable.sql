-- Run as: sa after the point-in-time recovery workflow in sql/recovery.
USE [SmartBankDB];
GO

-- Show the marker captured before the lecturer's change.
SELECT TOP (1) MarkerID, MarkerTimeServer, MarkerLabel, CreatedAt
FROM ops.RecoveryMarker
WHERE MarkerLabel LIKE N'PITR:%'
ORDER BY CreatedAt DESC;

-- Replace both queries below with the table, key and filter chosen by the lecturer.
-- This RecoveryTarget example is a safe fallback: it compares only rows 1 and 2.
SELECT N'Live database' AS DatabaseCopy, *
FROM demo.RecoveryTarget
WHERE RecoveryID IN (1, 2)
ORDER BY RecoveryID;

-- Use the same table, key and filter as the live query above.
SELECT N'Point-in-time restored database' AS DatabaseCopy, *
FROM SmartBankDB_PITR.demo.RecoveryTarget
WHERE RecoveryID IN (1, 2)
ORDER BY RecoveryID;

-- Find the actual table and row values changed after the marker.
SELECT TOP (20) EventTime, SchemaName, TableName, ActorLogin, ActionType,
       AffectedRowCount, OldValues, NewValues
FROM audit.DmlAudit
WHERE ActionType IN ('DELETE', 'UPDATE')
  AND EventTime >
      (
          SELECT TOP (1) MarkerTimeUtc
          FROM ops.RecoveryMarker
          WHERE MarkerLabel LIKE N'PITR:%'
          ORDER BY CreatedAt DESC
      )
ORDER BY EventTime DESC, AuditID DESC;
GO
