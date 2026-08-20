-- Run as: sb_manager_daniel.
USE [SmartBankDB];
GO

-- Managers update officer and DBA records in their own branch only through the approved procedure.
EXEC api.usp_ManagerUpdateOfficer
    @StaffID = 'S00004', @StaffName = N'Farid Iskandar', @Phone = '012-3101004',
    @BranchID = 'B0001', @Salary = 5200.00;
EXEC api.usp_ManagerUpdateOfficer
    @StaffID = 'S00003', @StaffName = N'Aisha Rahman', @Phone = '012-3101003',
    @BranchID = 'B0001', @Salary = 9200.00;
EXEC api.usp_ManagerGetStaffProfiles;

-- Expected result: validation error. A manager cannot change another manager.
EXEC api.usp_ManagerUpdateOfficer
    @StaffID = 'S00002', @StaffName = N'Siti Aminah', @Phone = '012-3101002',
    @BranchID = 'B0002', @Salary = 10900.00;

-- Expected result: validation error. Officers from another branch are out of scope.
EXEC api.usp_ManagerUpdateOfficer
    @StaffID = 'S00005', @StaffName = N'Priya Nair', @Phone = '012-3101005',
    @BranchID = 'B0002', @Salary = 5400.00;

-- Expected result: permission denied. Base-table updates are blocked.
UPDATE core.Staff SET Phone = '012-0000000' WHERE StaffID = 'S00004';
GO
