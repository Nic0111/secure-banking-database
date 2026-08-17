/*
ASSIGNMENT SECTION:
Section 1 - Confidentiality

REQUIREMENT:
6. Customers may view only their own accounts and only their own transactions.

RUN AS:
Run once as sb_customer_amelia and once as sb_customer_hafiz using fresh connections.

EXPECTED RESULT:
Amelia sees customer C00001, accounts A000000001-A000000002 and five baseline
ledger rows. Hafiz sees C00002, accounts A000000003-A000000004 and six baseline
ledger rows. Cross-customer rows are filtered and direct core access is denied.

PASS CONDITION:
Each login receives only its mapped profile/accounts/transactions and zero rows for
the other demonstration customer.

DATABASE CHANGES:
None. This script is read-only.
*/
USE [SmartBankDB];
GO
SET NOCOUNT ON;
GO

IF IS_ROLEMEMBER(N'rl_customer') <> 1
    THROW 51150, 'Run this script as one of the two demonstration customer logins.', 1;

DECLARE @ExpectedCustomerID char(6) =
    CASE ORIGINAL_LOGIN()
        WHEN N'sb_customer_amelia' THEN 'C00001'
        WHEN N'sb_customer_hafiz' THEN 'C00002'
    END;
DECLARE @OtherCustomerID char(6) = IIF(@ExpectedCustomerID = 'C00001', 'C00002', 'C00001');
DECLARE @ExpectedAccountCount int = 2;
DECLARE @ExpectedTransactionCount int = IIF(@ExpectedCustomerID = 'C00001', 5, 6);
IF @ExpectedCustomerID IS NULL
    THROW 51151, 'The connected login is not a mapped demonstration customer.', 1;

CREATE TABLE #OwnProfile
(
    CustomerID char(6), CustomerName nvarchar(100), Email varchar(254),
    ICNumber varchar(20), Phone varchar(20), Address nvarchar(200),
    Status varchar(12), CreatedAt datetime2(3)
);
INSERT #OwnProfile EXEC api.usp_GetMyCustomerProfile;
SELECT N'Own customer profile' AS Evidence, * FROM #OwnProfile;

SELECT N'Own accounts only' AS Evidence, *
FROM api.vw_MyAccounts ORDER BY AccountID;
SELECT N'Own transactions only' AS Evidence, *
FROM api.vw_MyTransactions ORDER BY TransID;

IF (SELECT COUNT(*) FROM #OwnProfile) <> 1
   OR NOT EXISTS (SELECT 1 FROM #OwnProfile WHERE CustomerID = @ExpectedCustomerID)
   OR (SELECT COUNT(*) FROM api.vw_MyAccounts) <> @ExpectedAccountCount
   OR EXISTS (SELECT 1 FROM api.vw_MyAccounts WHERE CustomerID <> @ExpectedCustomerID)
   OR (SELECT COUNT(*) FROM api.vw_MyTransactions) <> @ExpectedTransactionCount
   OR EXISTS (SELECT 1 FROM api.vw_MyTransactions WHERE CustomerID <> @ExpectedCustomerID)
    THROW 51152, 'FAIL - customer row-level isolation does not match the golden baseline.', 1;

SELECT @OtherCustomerID AS OtherCustomerTested,
       (SELECT COUNT(*) FROM api.vw_MyAccounts WHERE CustomerID = @OtherCustomerID) AS OtherCustomerAccountsVisible,
       (SELECT COUNT(*) FROM api.vw_MyTransactions WHERE CustomerID = @OtherCustomerID) AS OtherCustomerTransactionsVisible,
       N'PASS - both values must be zero' AS Result;

BEGIN TRY
    EXEC sys.sp_executesql N'SELECT TOP (1) * FROM core.Account;';
    THROW 51153, 'FAIL - customer direct core.Account access unexpectedly succeeded.', 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51153 THROW;
    SELECT N'PASS' AS Result,
           N'Customer access is confined to row-filtered API views.' AS Evidence,
           ERROR_MESSAGE() AS ExpectedDenial;
END CATCH;
GO
