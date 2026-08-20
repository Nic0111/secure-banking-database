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
DECLARE @BaseAccountReadDenied bit = 0;
BEGIN TRY
    SELECT * FROM core.Account;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() <> 229
        THROW;

    SET @BaseAccountReadDenied = 1;
    SELECT N'PASS - direct core.Account read denied' AS Result,
           ERROR_NUMBER() AS ActualErrorNumber,
           ERROR_MESSAGE() AS ActualErrorMessage;
END CATCH;

IF @BaseAccountReadDenied = 0
    THROW 51122, 'FAIL: a customer unexpectedly read core.Account directly.', 1;
GO

-- EXPECTED DENIAL: customers cannot read the internal staff directory (StaffID withheld).
DECLARE @StaffDirectoryReadDenied bit = 0;
BEGIN TRY
    SELECT TOP (1) * FROM api.vw_StaffDirectory;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() <> 229
        THROW;

    SET @StaffDirectoryReadDenied = 1;
    SELECT N'PASS - internal staff directory read denied' AS Result,
           ERROR_NUMBER() AS ActualErrorNumber,
           ERROR_MESSAGE() AS ActualErrorMessage;
END CATCH;

IF @StaffDirectoryReadDenied = 0
    THROW 51123, 'FAIL: a customer unexpectedly read the internal staff directory.', 1;

-- Customers read the ID-free public directory instead.
SELECT StaffName, Phone
FROM api.vw_StaffDirectoryPublic
ORDER BY StaffName;
GO
