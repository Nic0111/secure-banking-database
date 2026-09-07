-- Run in fresh connections as: sb_manager_daniel and sb_manager_siti.
USE [SmartBankDB];
GO

-- Managers can update officer and DBA records in their own branch only through the approved procedure.
DECLARE @OwnOfficerStaffID char(6), @OwnOfficerName nvarchar(100),
        @OwnOfficerPhone varchar(20), @OwnOfficerBranchID char(5),
        @OwnOfficerSalary decimal(19, 2);
IF ORIGINAL_LOGIN() = N'sb_manager_daniel'
BEGIN
    SELECT @OwnOfficerStaffID = 'S00004', @OwnOfficerName = N'Farid Iskandar',
           @OwnOfficerPhone = '012-3101004', @OwnOfficerBranchID = 'B0001',
           @OwnOfficerSalary = 5300.00;
END;
ELSE IF ORIGINAL_LOGIN() = N'sb_manager_siti'
BEGIN
    SELECT @OwnOfficerStaffID = 'S00005', @OwnOfficerName = N'Priya Nair',
           @OwnOfficerPhone = '012-3101005', @OwnOfficerBranchID = 'B0002',
           @OwnOfficerSalary = 5400.00;
END;

IF @OwnOfficerStaffID IS NULL
    THROW 51200, 'Run this test only as a configured manager login.', 1;

EXEC api.usp_ManagerUpdateOfficer
    @StaffID = @OwnOfficerStaffID, @StaffName = @OwnOfficerName, @Phone = @OwnOfficerPhone,
    @BranchID = @OwnOfficerBranchID, @Salary = @OwnOfficerSalary;

DECLARE @OwnDbaStaffID char(6), @OwnDbaName nvarchar(100),
        @OwnDbaPhone varchar(20), @OwnDbaBranchID char(5),
        @OwnDbaSalary decimal(19, 2), @OtherDbaStaffID char(6),
        @OtherDbaName nvarchar(100), @OtherDbaPhone varchar(20),
        @OtherDbaBranchID char(5), @OtherDbaSalary decimal(19, 2);
IF ORIGINAL_LOGIN() = N'sb_manager_daniel'
BEGIN
    SELECT @OwnDbaStaffID = 'S00003', @OwnDbaName = N'Aisha Rahman',
           @OwnDbaPhone = '012-3101003', @OwnDbaBranchID = 'B0001', @OwnDbaSalary = 9200.00,
           @OtherDbaStaffID = 'S00009', @OtherDbaName = N'Kavitha Rao',
           @OtherDbaPhone = '012-3101009', @OtherDbaBranchID = 'B0002', @OtherDbaSalary = 9400.00;
END;
ELSE
BEGIN
    SELECT @OwnDbaStaffID = 'S00009', @OwnDbaName = N'Kavitha Rao',
           @OwnDbaPhone = '012-3101009', @OwnDbaBranchID = 'B0002', @OwnDbaSalary = 9400.00,
           @OtherDbaStaffID = 'S00003', @OtherDbaName = N'Aisha Rahman',
           @OtherDbaPhone = '012-3101003', @OtherDbaBranchID = 'B0001', @OtherDbaSalary = 9200.00;
END;

EXEC api.usp_ManagerUpdateOfficer
    @StaffID = @OwnDbaStaffID, @StaffName = @OwnDbaName, @Phone = @OwnDbaPhone,
    @BranchID = @OwnDbaBranchID, @Salary = @OwnDbaSalary;

-- EXPECTED VALIDATION FAILURE: the other DBA belongs to another branch.
DECLARE @DbaUpdateRejected bit = 0;
BEGIN TRY
    BEGIN TRANSACTION;
    EXEC api.usp_ManagerUpdateOfficer
        @StaffID = @OtherDbaStaffID, @StaffName = @OtherDbaName, @Phone = @OtherDbaPhone,
        @BranchID = @OtherDbaBranchID, @Salary = @OtherDbaSalary;
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    IF ERROR_NUMBER() <> 50245
        THROW;

    SET @DbaUpdateRejected = 1;
    SELECT N'PASS - DBA update rejected: the DBA is not in the manager own branch' AS Result,
           ERROR_NUMBER() AS ActualErrorNumber,
           ERROR_MESSAGE() AS ActualErrorMessage;
END CATCH;

IF @DbaUpdateRejected = 0
    THROW 51208, 'FAIL: a manager unexpectedly updated the DBA across branches.', 1;

-- EXPECTED VALIDATION FAILURE: managers may maintain an own-branch DBA's
-- employment record, but only an officer identity can be deactivated here.
DECLARE @DbaDeactivationRejected bit = 0;
BEGIN TRY
    BEGIN TRANSACTION;
    EXEC api.usp_ManagerDeactivateOfficer @StaffID = @OwnDbaStaffID;
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    IF ERROR_NUMBER() <> 50216
        THROW;

    SET @DbaDeactivationRejected = 1;
    SELECT N'PASS - manager cannot deactivate an own-branch DBA through the officer procedure' AS Result,
           ERROR_NUMBER() AS ActualErrorNumber,
           ERROR_MESSAGE() AS ActualErrorMessage;
END CATCH;

IF @DbaDeactivationRejected = 0
    THROW 51211, 'FAIL: a manager unexpectedly deactivated an own-branch DBA.', 1;

-- EXPECTED VALIDATION FAILURE: a manager cannot update an officer from another branch.
DECLARE @OtherOfficerStaffID char(6) =
    CASE ORIGINAL_LOGIN()
        WHEN N'sb_manager_daniel' THEN 'S00005'
        WHEN N'sb_manager_siti' THEN 'S00004'
    END;
DECLARE @CrossBranchUpdateRejected bit = 0;
BEGIN TRY
    BEGIN TRANSACTION;
    EXEC api.usp_ManagerUpdateOfficer
        @StaffID = @OtherOfficerStaffID, @StaffName = N'Cross Branch Target',
        @Phone = '012-0000000', @BranchID = 'B0001', @Salary = 9000.00;
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    IF ERROR_NUMBER() <> 50245
        THROW;

    SET @CrossBranchUpdateRejected = 1;
    SELECT N'PASS - cross-branch officer update rejected' AS Result,
           ERROR_NUMBER() AS ActualErrorNumber,
           ERROR_MESSAGE() AS ActualErrorMessage;
END CATCH;

IF @CrossBranchUpdateRejected = 0
    THROW 51209, 'FAIL: a manager unexpectedly updated an officer from another branch.', 1;
GO

-- EXPECTED VALIDATION FAILURE: a manager cannot update or deactivate the other manager.
DECLARE @PeerManagerStaffID char(6), @PeerManagerName nvarchar(100),
        @PeerManagerPhone varchar(20), @PeerManagerBranchID char(5),
        @PeerManagerSalary decimal(19, 2);
IF ORIGINAL_LOGIN() = N'sb_manager_daniel'
BEGIN
    SELECT @PeerManagerStaffID = 'S00002', @PeerManagerName = N'Siti Aminah',
           @PeerManagerPhone = '012-3101002', @PeerManagerBranchID = 'B0002',
           @PeerManagerSalary = 10900.00;
END;
ELSE IF ORIGINAL_LOGIN() = N'sb_manager_siti'
BEGIN
    SELECT @PeerManagerStaffID = 'S00001', @PeerManagerName = N'Daniel Wong',
           @PeerManagerPhone = '012-3101001', @PeerManagerBranchID = 'B0001',
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
    UPDATE core.StaffEmployment SET SalaryCipher = 0x00 WHERE StaffID = 'S00004';
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
