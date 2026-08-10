USE [SmartBankDB];
GO

SELECT * FROM audit.vw_AuditMatrix;
SELECT TOP (200) * FROM audit.vw_DmlAudit ORDER BY EventTime DESC, AuditID DESC;
SELECT TOP (200) * FROM audit.ApplicationEvent ORDER BY EventTime DESC, EventID DESC;
EXEC audit.usp_ReadNativeAudit @StartTime = NULL, @EndTime = NULL, @OnlyFailures = 0;
GO

