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
    DECLARE @InsufficientFundsRejected bit = 0;
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC api.usp_PerformTransaction
            @TransactionType = 'WITHDRAWAL', @SourceAccountID = 'A000000001',
            @DestinationAccountID = NULL, @Amount = 999999.00, @TransactionPin = '482731', @Channel = 'ONLINE';
        ROLLBACK TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        IF ERROR_NUMBER() <> 50242
            THROW;

        SET @InsufficientFundsRejected = 1;
        SELECT N'PASS - insufficient-funds withdrawal rejected' AS Result,
               ERROR_NUMBER() AS ActualErrorNumber,
               ERROR_MESSAGE() AS ActualErrorMessage;
    END CATCH;

    IF @InsufficientFundsRejected = 0
        THROW 51221, 'FAIL: an insufficient-funds withdrawal unexpectedly succeeded.', 1;
END;
ELSE IF ORIGINAL_LOGIN() = N'sb_customer_hafiz'
BEGIN
    -- EXPECTED VALIDATION FAILURE: Amelia's account is not Hafiz's account.
    DECLARE @ForeignAccountRejected bit = 0;
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC api.usp_PerformTransaction
            @TransactionType = 'WITHDRAWAL', @SourceAccountID = 'A000000001',
            @DestinationAccountID = NULL, @Amount = 10.00, @TransactionPin = '482731', @Channel = 'ONLINE';
        ROLLBACK TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        IF ERROR_NUMBER() <> 50241
            THROW;

        SET @ForeignAccountRejected = 1;
        SELECT N'PASS - foreign source account rejected' AS Result,
               ERROR_NUMBER() AS ActualErrorNumber,
               ERROR_MESSAGE() AS ActualErrorMessage;
    END CATCH;

    IF @ForeignAccountRejected = 0
        THROW 51222, 'FAIL: a customer unexpectedly transacted from another customer''s account.', 1;
END;
ELSE
    THROW 51220, 'Run this test only as a configured customer login.', 1;
GO
