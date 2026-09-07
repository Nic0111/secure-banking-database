-- Run as: sb_officer_farid or sb_officer_priya.
USE [SmartBankDB];
GO

-- Open a new savings account for an existing active customer through the
-- approved officer procedure. The new account starts with a zero balance.
EXEC api.usp_OfficerOpenAccount
    @AccountID = 'APRES00001',
    @CustomerID = 'C00012',
    @AccountType = 'SAVINGS';
GO

-- Freeze the customer account through the approved management procedure.
EXEC api.usp_OfficerSetAccountStatus
    @AccountID = 'APRES00001',
    @Status = 'FROZEN';
GO

-- Show the managed account and its current status.
SELECT AccountID, CustomerID, AccountType, Balance, Status
FROM api.vw_CustomerAccountSummary
WHERE AccountID = 'APRES00001';
GO

-- Return the account to ACTIVE after the demonstration.
EXEC api.usp_OfficerSetAccountStatus
    @AccountID = 'APRES00001',
    @Status = 'ACTIVE';
GO

-- Optional negative test: execute separately.
-- Expected result: permission denied because officers cannot alter balances
-- directly; balance changes must use approved customer transaction procedures.
UPDATE core.Account
SET Balance = 999999.99
WHERE AccountID = 'APRES00001';
GO
