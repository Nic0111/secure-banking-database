-- Run as: sb_auditor_noor after the integrity demonstrations.
USE [SmartBankDB];
GO

DECLARE @StartTime datetime2(3) = DATEADD(HOUR, -2, SYSUTCDATETIME());

-- Show successful data changes.
SELECT TOP (50) AuditID, EventTime, ActionType, SchemaName, TableName,
       AffectedRowCount, ActorLogin, OldValues, NewValues
FROM audit.vw_DmlAudit
WHERE EventTime >= @StartTime
ORDER BY EventTime DESC, AuditID DESC;

-- Show successful and rejected procedure calls.
SELECT TOP (50) EventTime, EventType, OperationName, Succeeded,
       ActorLogin, TargetID, ErrorNumber, SafeDetails
FROM audit.ApplicationEvent
WHERE EventTime >= @StartTime
ORDER BY EventTime DESC, EventID DESC;

-- Show login, permission, and denied-operation audit metadata.
EXEC audit.usp_ReadNativeAudit @StartTime = @StartTime, @EndTime = NULL, @OnlyFailures = 0;
GO
