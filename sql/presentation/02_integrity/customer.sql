-- Run as: sb_customer_amelia in SSMS SQLCMD mode.
-- Set this variable privately before presenting and exclude the PIN from screenshots.
:setvar DemoTransactionPin "482731"

USE [SmartBankDB];
GO

DECLARE @DemoPin varchar(12) = '$(DemoTransactionPin)';

-- Show Amelia's account balances before the transactions.
SELECT AccountID, AccountType, Balance, Status
FROM api.vw_MyAccounts
ORDER BY AccountID;

-- 1. Successful: deposit money into Amelia's own savings account.
EXEC api.usp_PerformTransaction
    @TransactionType = 'DEPOSIT',
    @SourceAccountID = 'A000000001',
    @DestinationAccountID = NULL,
    @Amount = 100.00,
    @TransactionPin = @DemoPin,
    @Channel = 'MOBILE';

-- 2. Successful: withdraw money from Amelia's own savings account.
EXEC api.usp_PerformTransaction
    @TransactionType = 'WITHDRAWAL',
    @SourceAccountID = 'A000000001',
    @DestinationAccountID = NULL,
    @Amount = 50.00,
    @TransactionPin = @DemoPin,
    @Channel = 'ATM';

-- 3. Successful: transfer money from Amelia's account to another customer.
-- A000000003 belongs to customer C00002. Amelia must own the source account,
-- but she does not need to own the destination account.
EXEC api.usp_PerformTransaction
    @TransactionType = 'TRANSFER',
    @SourceAccountID = 'A000000001',
    @DestinationAccountID = 'A000000003',
    @Amount = 25.00,
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

-- 4. Expected rejection: attempt to deposit directly into another customer's
-- account. A000000003 belongs to customer C00002, so it cannot be used as
-- Amelia's deposit/source account. Sending money to it requires TRANSFER.
-- Execute this block separately from the successful examples.
DECLARE @DemoPin varchar(12) = '$(DemoTransactionPin)';
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
DECLARE @DemoPin varchar(12) = '$(DemoTransactionPin)';
EXEC api.usp_PerformTransaction
    @TransactionType = 'WITHDRAWAL',
    @SourceAccountID = 'A000000001',
    @DestinationAccountID = NULL,
    @Amount = -1.00,
    @TransactionPin = @DemoPin,
    @Channel = 'ONLINE';
GO
