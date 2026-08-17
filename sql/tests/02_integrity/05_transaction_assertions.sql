-- Run in fresh connections as: sb_customer_amelia and sb_customer_hafiz.
USE [SmartBankDB];
GO

-- Amelia can create valid transactions only for Amelia's account.
IF ORIGINAL_LOGIN() = N'sb_customer_amelia'
BEGIN
    EXEC api.usp_PerformTransaction
        @TransactionType = 'DEPOSIT', @SourceAccountID = 'A000000001',
        @DestinationAccountID = NULL, @Amount = 25.00, @TransactionPin = '482731', @Channel = 'MOBILE';
    EXEC api.usp_PerformTransaction
        @TransactionType = 'WITHDRAWAL', @SourceAccountID = 'A000000001',
        @DestinationAccountID = NULL, @Amount = 5.00, @TransactionPin = '482731', @Channel = 'ATM';
    EXEC api.usp_PerformTransaction
        @TransactionType = 'TRANSFER', @SourceAccountID = 'A000000001',
        @DestinationAccountID = 'A000000003', @Amount = 10.00, @TransactionPin = '482731', @Channel = 'ONLINE';

    -- EXPECTED VALIDATION FAILURE: insufficient funds.
    EXEC api.usp_PerformTransaction
        @TransactionType = 'WITHDRAWAL', @SourceAccountID = 'A000000001',
        @DestinationAccountID = NULL, @Amount = 999999.00, @TransactionPin = '482731', @Channel = 'ONLINE';
END;
ELSE IF ORIGINAL_LOGIN() = N'sb_customer_hafiz'
BEGIN
    -- EXPECTED VALIDATION FAILURE: Amelia's account is not Hafiz's account.
    EXEC api.usp_PerformTransaction
        @TransactionType = 'WITHDRAWAL', @SourceAccountID = 'A000000001',
        @DestinationAccountID = NULL, @Amount = 10.00, @TransactionPin = '482731', @Channel = 'ONLINE';
END;
ELSE
    THROW 51220, 'Run this test only as a configured customer login.', 1;
GO
