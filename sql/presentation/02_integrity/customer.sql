-- show
SELECT AccountID, AccountType, Balance, Status
FROM api.vw_MyAccounts
ORDER BY AccountID;

-- 1. Successful: deposit money into Amelia's own savings account.
DECLARE @DemoPin varchar(12) = '482731';
EXEC api.usp_PerformTransaction
    @TransactionType = 'DEPOSIT',
    @SourceAccountID = 'A000000001',
    @DestinationAccountID = NULL,
    @Amount = 100.00,
    @TransactionPin = @DemoPin,
    @Channel = 'MOBILE';

-- 2. Successful: withdraw money from Amelia's own savings account.
DECLARE @DemoPin varchar(12) = '482731';
EXEC api.usp_PerformTransaction
    @TransactionType = 'WITHDRAWAL',
    @SourceAccountID = 'A000000001',
    @DestinationAccountID = NULL,
    @Amount = 100.00,
    @TransactionPin = @DemoPin,
    @Channel = 'ATM';

-- 3. Successful: transfer money from Amelia's account to another customer.
DECLARE @DemoPin varchar(12) = '482731';
EXEC api.usp_PerformTransaction
    @TransactionType = 'TRANSFER',
    @SourceAccountID = 'A000000001',
    @DestinationAccountID = 'A000000003',
    @Amount = 100.00,
    @TransactionPin = @DemoPin,
    @Channel = 'ONLINE';

-- Show the updated balances and the latest transaction records.
SELECT AccountID, AccountType, Balance, Status
FROM api.vw_MyAccounts
ORDER BY AccountID;

SELECT TOP (10)
       TransID, AccountID, CounterpartyAccountID, TransDate, Amount,
       Direction, TransactionType, BalanceAfter, Channel
FROM api.vw_MyTransactions
ORDER BY TransID DESC;
GO

-- 4. Customer deposits cash into another customer's account - the counter
-- deposit case. Amelia credits money into A000000003 (customer C00002's
-- account) without touching her own balance; the destination balance is never
-- disclosed to Amelia, just a receipt.
DECLARE @DemoPin varchar(12) = '482731';
EXEC api.usp_CustomerDepositToAccount
    @DestinationAccountID = 'A000000003',
    @Amount = 200.00,
    @TransactionPin = @DemoPin,
    @Channel = 'ONLINE';
GO

-- Amelia's own balances are unchanged; the credit appears in C00002's statement.
SELECT AccountID, AccountType, Balance, Status
FROM api.vw_MyAccounts
ORDER BY AccountID;
GO

-- 5. Expected rejection: the self-service path (usp_PerformTransaction) still
-- refuses a deposit into another customer's account - only the dedicated
-- deposit procedure opens that path. Execute this block separately.
DECLARE @DemoPin varchar(12) = '482731';
EXEC api.usp_PerformTransaction
    @TransactionType = 'DEPOSIT',
    @SourceAccountID = 'A000000003',
    @DestinationAccountID = NULL,
    @Amount = 10.00,
    @TransactionPin = @DemoPin,
    @Channel = 'ONLINE';
GO
DECLARE @DemoPin varchar(12) = '482731';
EXEC api.usp_PerformTransaction
    @TransactionType = 'DEPOSIT',
    @SourceAccountID = 'A000000003',
    @DestinationAccountID = NULL,
    @Amount = 10.00,
    @TransactionPin = @DemoPin,
    @Channel = 'ONLINE';
GO

-- Optional negative test: execute this block separately.
-- Expected result: validation error because the amount must be positive.
DECLARE @DemoPin varchar(12) = '482731';
EXEC api.usp_PerformTransaction
    @TransactionType = 'WITHDRAWAL',
    @SourceAccountID = 'A000000001',
    @DestinationAccountID = NULL,
    @Amount = -1.00,
    @TransactionPin = @DemoPin,
    @Channel = 'ONLINE';
GO
