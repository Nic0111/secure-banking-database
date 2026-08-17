/*
ASSIGNMENT SECTION:
Section 2 - Integrity

REQUIREMENT:
5. Customers may perform valid deposits, withdrawals and transfers on their own
accounts; invalid manipulations must be rejected.

RUN AS:
Run as sb_customer_amelia or sb_customer_hafiz in SQLCMD mode. Supply the existing
DemoTransactionPin variable externally; do not hard-code or display it.

EXPECTED RESULT:
A deposit/withdrawal pair and two opposite own-account transfers succeed, leaving
the balances unchanged overall. Negative amount, excessive withdrawal and another
customer's source-account attempts are rejected.

PASS CONDITION:
All valid operations commit atomically, all three invalid operations fail, the
ledger chain remains valid, and the customer sees only their own appended entries.

DATABASE CHANGES:
Appends six immutable ledger entries and application/audit events. Net account
balances are unchanged. Restore the golden baseline before a full rerun.
*/
USE [SmartBankDB];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF IS_ROLEMEMBER(N'rl_customer') <> 1
    THROW 51240, 'Run this script as a demonstration customer login.', 1;

DECLARE @DemoPin varchar(12) = '$(DemoTransactionPin)';
DECLARE @SourceAccount varchar(10), @OwnDestination varchar(10), @OtherCustomerAccount varchar(10);
SELECT @SourceAccount = CASE ORIGINAL_LOGIN()
                            WHEN N'sb_customer_amelia' THEN 'A000000001'
                            WHEN N'sb_customer_hafiz' THEN 'A000000003'
                        END,
       @OwnDestination = CASE ORIGINAL_LOGIN()
                            WHEN N'sb_customer_amelia' THEN 'A000000002'
                            WHEN N'sb_customer_hafiz' THEN 'A000000004'
                         END,
       @OtherCustomerAccount = CASE ORIGINAL_LOGIN()
                                  WHEN N'sb_customer_amelia' THEN 'A000000003'
                                  WHEN N'sb_customer_hafiz' THEN 'A000000001'
                               END;
IF @SourceAccount IS NULL
    THROW 51241, 'The connected login is not a mapped demonstration customer.', 1;

DECLARE @StartingSourceBalance decimal(19, 2), @StartingDestinationBalance decimal(19, 2);
SELECT @StartingSourceBalance = Balance FROM api.vw_MyAccounts WHERE AccountID = @SourceAccount;
SELECT @StartingDestinationBalance = Balance FROM api.vw_MyAccounts WHERE AccountID = @OwnDestination;
IF @StartingSourceBalance IS NULL OR @StartingDestinationBalance IS NULL
    THROW 51247, 'FAIL - the customer cannot see both expected source accounts.', 1;

EXEC api.usp_PerformTransaction 'DEPOSIT', @SourceAccount, NULL, 10.00, @DemoPin, 'MOBILE';
EXEC api.usp_PerformTransaction 'WITHDRAWAL', @SourceAccount, NULL, 10.00, @DemoPin, 'MOBILE';
EXEC api.usp_PerformTransaction 'TRANSFER', @SourceAccount, @OwnDestination, 5.00, @DemoPin, 'ONLINE';
EXEC api.usp_PerformTransaction 'TRANSFER', @OwnDestination, @SourceAccount, 5.00, @DemoPin, 'ONLINE';

IF ISNULL((SELECT Balance FROM api.vw_MyAccounts WHERE AccountID = @SourceAccount), -1) <> @StartingSourceBalance
   OR ISNULL((SELECT Balance FROM api.vw_MyAccounts WHERE AccountID = @OwnDestination), -1) <> @StartingDestinationBalance
    THROW 51242, 'FAIL - compensating demo transactions did not return balances to their starting values.', 1;

DECLARE @Rejected table (Attempt nvarchar(140), ErrorNumber int, ErrorMessage nvarchar(4000));
BEGIN TRY
    EXEC api.usp_PerformTransaction 'WITHDRAWAL', @SourceAccount, NULL, -1.00, @DemoPin, 'ONLINE';
    THROW 51243, 'FAIL - negative transaction amount unexpectedly succeeded.', 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51243 THROW;
    INSERT @Rejected VALUES (N'Negative withdrawal amount', ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    EXEC api.usp_PerformTransaction 'WITHDRAWAL', @SourceAccount, NULL, 900000.00, @DemoPin, 'ONLINE';
    THROW 51244, 'FAIL - excessive withdrawal unexpectedly succeeded.', 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51244 THROW;
    INSERT @Rejected VALUES (N'Withdrawal exceeding available balance', ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    EXEC api.usp_PerformTransaction 'DEPOSIT', @OtherCustomerAccount, NULL, 1.00, @DemoPin, 'ONLINE';
    THROW 51245, 'FAIL - transaction on another customer source account unexpectedly succeeded.', 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51245 THROW;
    INSERT @Rejected VALUES (N'Use another customer account as source', ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;

SELECT TOP (10) N'Own recent immutable ledger entries' AS Evidence, *
FROM api.vw_MyTransactions
WHERE AccountID IN (@SourceAccount, @OwnDestination)
ORDER BY TransID DESC;
SELECT N'PASS' AS Result, Attempt, ErrorNumber, ErrorMessage AS ExpectedRejection
FROM @Rejected ORDER BY Attempt;

IF (SELECT COUNT(*) FROM @Rejected) <> 3
    THROW 51246, 'FAIL - one or more invalid customer transactions were not rejected.', 1;
GO
