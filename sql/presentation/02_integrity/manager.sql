-- show all staff
EXEC api.usp_ManagerGetStaffProfiles;
GO

-- update
-- @Salary = NULL preserves the officer's existing encrypted salary.
EXEC api.usp_ManagerUpdateOfficer
    @StaffID = 'S00004',
    @StaffName = N'Farid Iskandar',
    @Phone = '012-3101099',
    @BranchID = 'B0001',
    @Salary = NULL;
GO

-- show
EXEC api.usp_ManagerGetStaffProfiles;
GO

-- update salary
-- A non-NULL @Salary is encrypted and stored; SalaryLastChangedAt is bumped.
EXEC api.usp_ManagerUpdateOfficer
    @StaffID = 'S00004',
    @StaffName = N'Farid Iskandar',
    @Phone = '012-3101099',
    @BranchID = 'B0001',
    @Salary = 5400.00;
GO

-- show
EXEC api.usp_ManagerGetStaffProfiles;
GO

-- negative test: other branch
EXEC api.usp_ManagerUpdateOfficer
    @StaffID = 'S00005',
    @StaffName = N'Priya Nair',
    @Phone = '012-3101098',
    @BranchID = 'B0002',
    @Salary = NULL;
GO
