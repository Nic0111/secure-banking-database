-- Run in fresh connections as: sb_manager_daniel and sb_manager_siti.
USE [SmartBankDB];
GO

-- Each manager sees their own profile and all officers, but not the other manager.
DECLARE @PeerManagerStaffID char(6) =
    CASE ORIGINAL_LOGIN()
        WHEN N'sb_manager_daniel' THEN 'S00007'
        WHEN N'sb_manager_siti' THEN 'S00002'
    END;
IF @PeerManagerStaffID IS NULL
    THROW 51110, 'Run this test only as a configured manager login.', 1;

CREATE TABLE #VisibleStaff
(
    StaffID char(6), StaffName nvarchar(100), Position varchar(20),
    BranchName nvarchar(100), Phone varchar(20), Salary decimal(19, 2), IsActive bit
);
INSERT #VisibleStaff EXEC api.usp_ManagerGetStaffProfiles;
IF EXISTS (SELECT 1 FROM #VisibleStaff WHERE StaffID = @PeerManagerStaffID)
    THROW 51111, 'FAIL: a manager can view the other manager''s employment profile.', 1;

EXEC api.usp_GetMyStaffProfile;
SELECT * FROM #VisibleStaff ORDER BY Position, StaffID;
SELECT * FROM api.vw_CustomerAccountSummary;
GO

-- EXPECTED DENIAL: a manager cannot read encrypted employment data directly.
SELECT * FROM core.StaffEmployment;
-- EXPECTED DENIAL: only customers can submit transactions.
EXEC api.usp_PerformTransaction 'DEPOSIT', 'A000000001', NULL, 10.00, '482731', 'ONLINE';
GO
