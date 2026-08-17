-- Run in fresh connections as: sb_customer_amelia and sb_customer_hafiz.
USE [SmartBankDB];
GO

-- Each customer sees only that customer's account and transaction rows.
DECLARE @ExpectedCustomerID char(6) =
    CASE ORIGINAL_LOGIN()
        WHEN N'sb_customer_amelia' THEN 'C00001'
        WHEN N'sb_customer_hafiz' THEN 'C00002'
    END;
IF @ExpectedCustomerID IS NULL
    THROW 51120, 'Run this test only as a configured customer login.', 1;

IF EXISTS (SELECT 1 FROM api.vw_MyAccounts WHERE CustomerID <> @ExpectedCustomerID)
    THROW 51121, 'FAIL: a customer can view another customer''s account.', 1;

EXEC api.usp_GetMyCustomerProfile;
SELECT * FROM api.vw_MyAccounts;
SELECT * FROM api.vw_MyTransactions ORDER BY TransDate DESC;
GO

-- EXPECTED DENIAL: customers cannot read the base account table.
SELECT * FROM core.Account;
GO
