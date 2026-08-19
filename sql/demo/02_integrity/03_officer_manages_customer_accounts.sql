-- Run as: sb_officer_farid or sb_officer_priya.
USE [SmartBankDB];
GO

-- Officers open and control an account through approved procedures.
EXEC api.usp_OfficerOpenAccount
    @AccountID = 'ADEMO00001', @CustomerID = 'C00012', @AccountType = 'SAVINGS';
EXEC api.usp_OfficerSetAccountStatus @AccountID = 'ADEMO00001', @Status = 'FROZEN';
SELECT * FROM api.vw_CustomerAccountSummary WHERE AccountID = 'ADEMO00001';
EXEC api.usp_OfficerSetAccountStatus @AccountID = 'ADEMO00001', @Status = 'ACTIVE';

-- Expected result: permission denied. Officers cannot change balances directly.
UPDATE core.Account SET Balance = 999999.99 WHERE AccountID = 'ADEMO00001';
GO
