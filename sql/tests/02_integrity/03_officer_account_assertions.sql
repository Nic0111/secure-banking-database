-- Run in fresh connections as: sb_officer_farid and sb_officer_priya.
USE [SmartBankDB];
GO

-- Officers can open and update accounts through stored procedures.
IF NOT EXISTS (SELECT 1 FROM api.vw_CustomerAccountSummary WHERE AccountID = 'ATEST00001')
    EXEC api.usp_OfficerOpenAccount @AccountID = 'ATEST00001', @CustomerID = 'C00012', @AccountType = 'CURRENT';
EXEC api.usp_OfficerSetAccountStatus @AccountID = 'ATEST00001', @Status = 'FROZEN';
EXEC api.usp_OfficerSetAccountStatus @AccountID = 'ATEST00001', @Status = 'ACTIVE';
GO

-- EXPECTED DENIAL: officers cannot bypass the account or salary controls.
DECLARE @BalanceUpdateDenied bit = 0;
BEGIN TRY
    BEGIN TRANSACTION;
    UPDATE core.Account SET Balance = 999999.99 WHERE AccountID = 'A000000001';
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    IF ERROR_NUMBER() <> 229
        THROW;

    SET @BalanceUpdateDenied = 1;
    SELECT N'PASS - direct account-balance update denied to officer' AS Result,
           ERROR_NUMBER() AS ActualErrorNumber,
           ERROR_MESSAGE() AS ActualErrorMessage;
END CATCH;

IF @BalanceUpdateDenied = 0
    THROW 51206, 'FAIL: an officer unexpectedly updated an account balance directly.', 1;

DECLARE @SalaryUpdateDenied bit = 0;
BEGIN TRY
    BEGIN TRANSACTION;
    UPDATE core.StaffEmployment SET SalaryCipher = 0x00 WHERE StaffID IN ('S00003', 'S00004');
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    IF ERROR_NUMBER() <> 229
        THROW;

    SET @SalaryUpdateDenied = 1;
    SELECT N'PASS - direct salary update denied to officer' AS Result,
           ERROR_NUMBER() AS ActualErrorNumber,
           ERROR_MESSAGE() AS ActualErrorMessage;
END CATCH;

IF @SalaryUpdateDenied = 0
    THROW 51207, 'FAIL: an officer unexpectedly updated salary ciphertext directly.', 1;
GO
