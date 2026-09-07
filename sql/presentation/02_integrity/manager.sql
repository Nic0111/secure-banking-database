-- Run as: sb_manager_daniel.
-- Daniel manages branch B0001; Farid (S00004) is an officer in B0001.
USE [SmartBankDB];
GO

-- Show the officer details visible to the manager before the update.
EXEC api.usp_ManagerGetStaffProfiles;
GO

-- Update an officer in the manager's own branch through the approved API.
-- @Salary = NULL preserves the officer's existing encrypted salary.
EXEC api.usp_ManagerUpdateOfficer
    @StaffID = 'S00004',
    @StaffName = N'Farid Iskandar',
    @Phone = '012-3101099',
    @BranchID = 'B0001',
    @Salary = NULL;
GO

-- Show the updated officer details.
EXEC api.usp_ManagerGetStaffProfiles;
GO

-- Optional negative test: execute separately.
-- Expected result: error 50245 because Priya belongs to B0002, not Daniel's branch.
EXEC api.usp_ManagerUpdateOfficer
    @StaffID = 'S00005',
    @StaffName = N'Priya Nair',
    @Phone = '012-3101098',
    @BranchID = 'B0002',
    @Salary = NULL;
GO
