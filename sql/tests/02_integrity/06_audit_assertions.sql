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
EXEC ops.usp_BackupHealth @Days = 3;
GO

-- EXPECTED DENIAL: the auditor cannot read business data.
DECLARE @BusinessDataReadDenied bit = 0;
BEGIN TRY
    SELECT * FROM core.Customer;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() <> 229
        THROW;

    SET @BusinessDataReadDenied = 1;
    SELECT N'PASS - direct business-data read denied to auditor' AS Result,
           ERROR_NUMBER() AS ActualErrorNumber,
           ERROR_MESSAGE() AS ActualErrorMessage;
END CATCH;

IF @BusinessDataReadDenied = 0
    THROW 51230, 'FAIL: the auditor unexpectedly read core.Customer directly.', 1;
GO

-- EXPECTED DENIAL: the auditor cannot read raw backup metadata.
USE [msdb];
GO
DECLARE @BackupHistoryReadDenied bit = 0;
BEGIN TRY
    SELECT TOP (1) * FROM dbo.backupset;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() <> 229
        THROW;

    SET @BackupHistoryReadDenied = 1;
    SELECT N'PASS - direct backup history read denied to auditor' AS Result,
           ERROR_NUMBER() AS ActualErrorNumber,
           ERROR_MESSAGE() AS ActualErrorMessage;
END CATCH;

IF @BackupHistoryReadDenied = 0
    THROW 51231, 'FAIL: the auditor unexpectedly read dbo.backupset directly.', 1;
GO

-- The auditor can inspect the anonymized analytics copy only.
USE [SmartBankAnalyticsDB];
GO
SELECT TOP (20) * FROM dbo.CustomerAnon;
SELECT TOP (20) * FROM dbo.AccountAnon;
SELECT TOP (20) * FROM dbo.TransactionAnon;
EXEC dbo.usp_StaticMaskingQualityCheck;
GO
