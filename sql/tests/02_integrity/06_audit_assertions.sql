-- Connect as: sb_auditor_noor.
USE [SmartBankDB];
GO

-- Review audit records and verify the transaction ledger remains consistent.
SELECT TOP (100) * FROM audit.vw_DmlAudit ORDER BY EventTime DESC, AuditID DESC;
SELECT TOP (100) * FROM audit.ApplicationEvent ORDER BY EventTime DESC, EventID DESC;
SELECT * FROM audit.vw_AuditMatrix;
SELECT * FROM api.vw_UserRoleMembership ORDER BY DatabaseRole, DatabaseUser;
SELECT * FROM api.vw_RolePermissionMatrix ORDER BY PrincipalName, SecurableName, PermissionName;
EXEC audit.usp_ReadNativeAudit @StartTime = NULL, @EndTime = NULL, @OnlyFailures = 0;
EXEC api.usp_VerifyLedgerChain;
EXEC api.usp_VerifyAccountBalances;
GO

-- EXPECTED DENIAL: the auditor cannot read business data.
SELECT * FROM core.Customer;
GO

-- The auditor can inspect the anonymized analytics copy only.
USE [SmartBankAnalyticsDB];
GO
SELECT TOP (20) * FROM dbo.CustomerAnon;
SELECT TOP (20) * FROM dbo.AccountAnon;
SELECT TOP (20) * FROM dbo.TransactionAnon;
EXEC dbo.usp_StaticMaskingQualityCheck;
GO
