-- Run in fresh connections as: sb_manager_daniel and sb_manager_siti.
USE [SmartBankDB];
GO

-- Managers can update officer and DBA records only through the approved procedure.
EXEC api.usp_ManagerUpdateOfficer
    @StaffID = 'S00003', @StaffName = N'Farid Iskandar', @Phone = '012-3101003',
    @BranchID = 'B0001', @Salary = 5300.00;

EXEC api.usp_ManagerUpdateOfficer
    @StaffID = 'S00001', @StaffName = N'Aisha Rahman', @Phone = '012-3101001',
    @BranchID = 'B0004', @Salary = 9200.00;
GO

-- EXPECTED VALIDATION FAILURE: a manager cannot update or deactivate the other manager.
DECLARE @PeerManagerStaffID char(6), @PeerManagerName nvarchar(100),
        @PeerManagerPhone varchar(20), @PeerManagerBranchID char(5),
        @PeerManagerSalary decimal(19, 2);
IF ORIGINAL_LOGIN() = N'sb_manager_daniel'
BEGIN
    SELECT @PeerManagerStaffID = 'S00007', @PeerManagerName = N'Siti Aminah',
           @PeerManagerPhone = '012-3101007', @PeerManagerBranchID = 'B0002',
           @PeerManagerSalary = 10900.00;
END;
ELSE IF ORIGINAL_LOGIN() = N'sb_manager_siti'
BEGIN
    SELECT @PeerManagerStaffID = 'S00002', @PeerManagerName = N'Daniel Wong',
           @PeerManagerPhone = '012-3101002', @PeerManagerBranchID = 'B0001',
           @PeerManagerSalary = 11500.00;
END;

IF @PeerManagerStaffID IS NULL
    THROW 51202, 'Run this test only as a configured manager login.', 1;

DECLARE @PeerUpdateRejected bit = 0;
BEGIN TRY
    BEGIN TRANSACTION;
    EXEC api.usp_ManagerUpdateOfficer
         @StaffID = @PeerManagerStaffID, @StaffName = @PeerManagerName,
         @Phone = @PeerManagerPhone, @BranchID = @PeerManagerBranchID,
         @Salary = @PeerManagerSalary;
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    IF ERROR_NUMBER() <> 50212
        THROW;

    SET @PeerUpdateRejected = 1;
    SELECT N'PASS - manager update rejected for peer manager' AS Result,
           ERROR_NUMBER() AS ActualErrorNumber,
           ERROR_MESSAGE() AS ActualErrorMessage;
END CATCH;

IF @PeerUpdateRejected = 0
    THROW 51203, 'FAIL: a manager unexpectedly updated another manager through the officer procedure.', 1;

DECLARE @PeerDeactivationRejected bit = 0;
BEGIN TRY
    BEGIN TRANSACTION;
    EXEC api.usp_ManagerDeactivateOfficer @StaffID = @PeerManagerStaffID;
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    IF ERROR_NUMBER() <> 50216
        THROW;

    SET @PeerDeactivationRejected = 1;
    SELECT N'PASS - manager deactivation rejected for peer manager' AS Result,
           ERROR_NUMBER() AS ActualErrorNumber,
           ERROR_MESSAGE() AS ActualErrorMessage;
END CATCH;

IF @PeerDeactivationRejected = 0
    THROW 51204, 'FAIL: a manager unexpectedly deactivated another manager.', 1;
GO

-- EXPECTED DENIAL: base-table salary changes are blocked.
DECLARE @SalaryUpdateDenied bit = 0;
BEGIN TRY
    BEGIN TRANSACTION;
    UPDATE core.StaffEmployment SET SalaryCipher = 0x00 WHERE StaffID = 'S00003';
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    IF ERROR_NUMBER() <> 229
        THROW;

    SET @SalaryUpdateDenied = 1;
    SELECT N'PASS - direct salary update denied to manager' AS Result,
           ERROR_NUMBER() AS ActualErrorNumber,
           ERROR_MESSAGE() AS ActualErrorMessage;
END CATCH;

IF @SalaryUpdateDenied = 0
    THROW 51205, 'FAIL: a manager unexpectedly updated salary ciphertext directly.', 1;
GO
