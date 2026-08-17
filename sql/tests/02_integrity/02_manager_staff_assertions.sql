-- Run in fresh connections as: sb_manager_daniel and sb_manager_siti.
USE [SmartBankDB];
GO

-- Managers can update officer details only through the approved procedure.
EXEC api.usp_ManagerUpdateOfficer
    @StaffID = 'S00003', @StaffName = N'Farid Iskandar', @Phone = '012-3101003',
    @BranchID = 'B0001', @Salary = 5300.00;
GO

-- EXPECTED VALIDATION FAILURE: a manager cannot update or deactivate the other manager.
IF ORIGINAL_LOGIN() = N'sb_manager_daniel'
BEGIN
    EXEC api.usp_ManagerUpdateOfficer @StaffID = 'S00007', @StaffName = N'Siti Aminah',
         @Phone = '012-3101007', @BranchID = 'B0002', @Salary = 10900.00;
    EXEC api.usp_ManagerDeactivateOfficer @StaffID = 'S00007';
END;
ELSE IF ORIGINAL_LOGIN() = N'sb_manager_siti'
BEGIN
    EXEC api.usp_ManagerUpdateOfficer @StaffID = 'S00002', @StaffName = N'Daniel Wong',
         @Phone = '012-3101002', @BranchID = 'B0001', @Salary = 11500.00;
    EXEC api.usp_ManagerDeactivateOfficer @StaffID = 'S00002';
END;
GO

-- EXPECTED DENIAL: base-table salary changes are blocked.
UPDATE core.StaffEmployment SET SalaryCipher = 0x00 WHERE StaffID = 'S00003';
GO
