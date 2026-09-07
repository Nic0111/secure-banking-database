-- Run in fresh connections as: sb_manager_daniel and sb_manager_siti.
USE [SmartBankDB];
GO

-- Each manager sees their own profile separately and this procedure returns the officers and the DBA in the manager's own branch.
DECLARE @ManagerStaffID char(6) =
    CASE ORIGINAL_LOGIN()
        WHEN N'sb_manager_daniel' THEN 'S00001'
        WHEN N'sb_manager_siti' THEN 'S00002'
    END;
DECLARE @PeerManagerStaffID char(6) =
    CASE ORIGINAL_LOGIN()
        WHEN N'sb_manager_daniel' THEN 'S00002'
        WHEN N'sb_manager_siti' THEN 'S00001'
    END;
IF @ManagerStaffID IS NULL OR @PeerManagerStaffID IS NULL
    THROW 51110, 'Run this test only as a configured manager login.', 1;

CREATE TABLE #VisibleStaff
(
    StaffID char(6), StaffName nvarchar(100), Position varchar(20),
    BranchName nvarchar(100), Phone varchar(20), Salary decimal(19, 2), IsActive bit
);
INSERT #VisibleStaff EXEC api.usp_ManagerGetStaffProfiles;
IF EXISTS (SELECT 1 FROM #VisibleStaff WHERE StaffID = @ManagerStaffID)
    THROW 51114, 'FAIL: the manager staff-list procedure returned the logged-in manager.', 1;

IF EXISTS (SELECT 1 FROM #VisibleStaff WHERE StaffID = @PeerManagerStaffID)
    THROW 51111, 'FAIL: a manager can view the other manager''s employment profile.', 1;

DECLARE @OwnBranchOfficerID char(6) =
    CASE ORIGINAL_LOGIN()
        WHEN N'sb_manager_daniel' THEN 'S00004'
        WHEN N'sb_manager_siti' THEN 'S00005'
    END;
DECLARE @OtherBranchOfficerID char(6) =
    CASE ORIGINAL_LOGIN()
        WHEN N'sb_manager_daniel' THEN 'S00005'
        WHEN N'sb_manager_siti' THEN 'S00004'
    END;

DECLARE @OwnBranchDbaID char(6) =
    CASE ORIGINAL_LOGIN()
        WHEN N'sb_manager_daniel' THEN 'S00003'
        WHEN N'sb_manager_siti' THEN 'S00009'
    END;
DECLARE @OtherBranchDbaID char(6) =
    CASE ORIGINAL_LOGIN()
        WHEN N'sb_manager_daniel' THEN 'S00009'
        WHEN N'sb_manager_siti' THEN 'S00003'
    END;

IF NOT EXISTS (SELECT 1 FROM #VisibleStaff WHERE StaffID = @OwnBranchDbaID AND Position = 'DBA')
    THROW 51115, 'FAIL: the manager staff-list procedure omitted the own-branch DBA profile.', 1;

IF EXISTS (SELECT 1 FROM #VisibleStaff WHERE StaffID = @OtherBranchDbaID)
    THROW 51119, 'FAIL: a manager can view a DBA assigned to another branch.', 1;

IF NOT EXISTS (SELECT 1 FROM #VisibleStaff WHERE StaffID = @OwnBranchOfficerID AND Position = 'BANK_OFFICER')
    THROW 51124, 'FAIL: the manager staff-list procedure omitted an own-branch officer.', 1;

IF EXISTS (SELECT 1 FROM #VisibleStaff WHERE StaffID = @OtherBranchOfficerID)
    THROW 51118, 'FAIL: a manager can view an officer assigned to another branch.', 1;

EXEC api.usp_GetMyStaffProfile;
SELECT * FROM #VisibleStaff ORDER BY Position, StaffID;
SELECT * FROM api.vw_CustomerAccountSummary;
GO

-- EXPECTED DENIAL: a manager cannot read encrypted employment data directly.
DECLARE @EmploymentReadDenied bit = 0;
BEGIN TRY
    SELECT * FROM core.StaffEmployment;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() <> 229
        THROW;

    SET @EmploymentReadDenied = 1;
    SELECT N'PASS - direct employment read denied' AS Result,
           ERROR_NUMBER() AS ActualErrorNumber,
           ERROR_MESSAGE() AS ActualErrorMessage;
END CATCH;

IF @EmploymentReadDenied = 0
    THROW 51112, 'FAIL: a manager unexpectedly read core.StaffEmployment directly.', 1;

-- EXPECTED DENIAL: only customers can submit transactions.
DECLARE @TransactionExecuteDenied bit = 0;
BEGIN TRY
    EXEC api.usp_PerformTransaction 'DEPOSIT', 'A000000001', NULL, 10.00, '482731', 'ONLINE';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() <> 229
        THROW;

    SET @TransactionExecuteDenied = 1;
    SELECT N'PASS - customer transaction procedure denied to manager' AS Result,
           ERROR_NUMBER() AS ActualErrorNumber,
           ERROR_MESSAGE() AS ActualErrorMessage;
END CATCH;

IF @TransactionExecuteDenied = 0
    THROW 51113, 'FAIL: a manager unexpectedly executed the customer transaction procedure.', 1;
GO
