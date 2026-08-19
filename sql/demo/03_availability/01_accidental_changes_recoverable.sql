-- Run as: sa after the point-in-time recovery workflow in sql/recovery.
USE [SmartBankDB];
GO

-- Show the marker captured before the lecturer's accidental deletion.
SELECT TOP (1) MarkerID, MarkerTimeServer, MarkerLabel, CreatedAt
FROM ops.RecoveryMarker
WHERE MarkerLabel LIKE N'PITR:%'
ORDER BY CreatedAt DESC;

-- Show the live source after the deletion.
SELECT N'Live database' AS DatabaseCopy, *
FROM demo.RecoveryTarget
ORDER BY RecoveryID;

-- Show the separate copy restored to the marker time.
SELECT N'Point-in-time restored database' AS DatabaseCopy, *
FROM SmartBankDB_PITR.demo.RecoveryTarget
ORDER BY RecoveryID;

-- Show the audit row for the accidental change.
SELECT TOP (20) EventTime, ActorLogin, ActionType, AffectedRowCount, OldValues, NewValues
FROM audit.DmlAudit
WHERE SchemaName = N'demo' AND TableName = N'RecoveryTarget'
ORDER BY EventTime DESC, AuditID DESC;
GO
