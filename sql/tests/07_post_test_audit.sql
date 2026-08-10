USE [SmartBankDB];
GO

SELECT TOP (200) EventTime, ActorLogin, ActionType, SchemaName, TableName,
       AffectedRowCount, CorrelationID, OldValues, NewValues
FROM audit.DmlAudit
ORDER BY EventTime DESC, AuditID DESC;

SELECT TOP (200) EventTime, ActorLogin, EventType, OperationName, Succeeded,
       TargetType, TargetID, CorrelationID, ErrorNumber, SafeDetails
FROM audit.ApplicationEvent
ORDER BY EventTime DESC, EventID DESC;

EXEC audit.usp_ReadNativeAudit
    @StartTime = NULL,
    @EndTime = NULL,
    @OnlyFailures = 0;
GO

