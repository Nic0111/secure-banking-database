USE [SmartBankDB];
GO
SET NOCOUNT ON;
GO

SELECT TOP (1) MarkerID, MarkerTimeUtc AS MarkerUtc, MarkerTimeServer AS StopAtServerTime,
       MarkerLabel, ExpectedRecoveryRows
FROM ops.RecoveryMarker ORDER BY CreatedAt DESC;

SELECT N'Current source rows after lecturer change' AS Evidence, *
FROM demo.RecoveryTarget ORDER BY RecoveryID;

SELECT TOP (20) EventTime, ActorLogin, ActionType, SchemaName, TableName,
       AffectedRowCount, OldValues, NewValues
FROM audit.DmlAudit
WHERE SchemaName = N'demo' AND TableName = N'RecoveryTarget'
ORDER BY EventTime DESC, AuditID DESC;

-- Captures the log containing both the recovery marker and the later deletion.
EXEC ops.usp_RunBackup @BackupType = 'L';
GO
