-- Run in fresh connections as: sb_officer_farid and sb_officer_priya.
USE [SmartBankDB];
GO

-- Officers can use approved views and see only their own employment profile.
EXEC api.usp_GetMyStaffProfile;
SELECT * FROM api.vw_StaffDirectory;
SELECT * FROM api.vw_CustomerAccountSummary;
SELECT * FROM api.vw_MyTransactions ORDER BY TransDate DESC;
GO

-- EXPECTED DENIAL: an officer cannot access manager-only employment records.
DECLARE @ManagerProcedureDenied bit = 0;
BEGIN TRY
    EXEC api.usp_ManagerGetStaffProfiles;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() <> 229
        THROW;

    SET @ManagerProcedureDenied = 1;
    SELECT N'PASS - manager procedure denied to officer' AS Result,
           ERROR_NUMBER() AS ActualErrorNumber,
           ERROR_MESSAGE() AS ActualErrorMessage;
END CATCH;

IF @ManagerProcedureDenied = 0
    THROW 51114, 'FAIL: an officer unexpectedly executed the manager profile procedure.', 1;

-- EXPECTED DENIAL: only customers can submit transactions.
DECLARE @TransactionExecuteDenied bit = 0;
BEGIN TRY
    EXEC api.usp_PerformTransaction 'DEPOSIT', 'A000000001', NULL, 10.00, '482731', 'ONLINE';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() <> 229
        THROW;

    SET @TransactionExecuteDenied = 1;
    SELECT N'PASS - customer transaction procedure denied to officer' AS Result,
           ERROR_NUMBER() AS ActualErrorNumber,
           ERROR_MESSAGE() AS ActualErrorMessage;
END CATCH;

IF @TransactionExecuteDenied = 0
    THROW 51115, 'FAIL: an officer unexpectedly executed the customer transaction procedure.', 1;
GO
