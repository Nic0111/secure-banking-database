-- Run in two fresh connections: first as sb_manager_daniel, then as sb_manager_siti.
USE [SmartBankDB];
GO

SELECT * FROM api.vw_StaffDirectory;                -- SUCCESS: public staff directory.
EXEC api.usp_GetMyStaffProfile;                     -- SUCCESS: manager's own full/decrypted record.

-- SUCCESS: own record plus all officers, with the other manager excluded.
DECLARE @PeerManagerStaffID char(6) =
    CASE ORIGINAL_LOGIN()
        WHEN N'sb_manager_daniel' THEN 'S00007'
        WHEN N'sb_manager_siti' THEN 'S00002'
    END;
IF @PeerManagerStaffID IS NULL
    THROW 51021, 'Run this test only as a configured manager login.', 1;

DROP TABLE IF EXISTS #VisibleStaff;
CREATE TABLE #VisibleStaff
(
    StaffID char(6),
    StaffName nvarchar(100),
    Position varchar(20),
    BranchName nvarchar(100),
    Phone varchar(20),
    Salary decimal(19, 2),
    IsActive bit
);
INSERT #VisibleStaff EXEC api.usp_ManagerGetStaffProfiles;
IF EXISTS (SELECT 1 FROM #VisibleStaff WHERE StaffID = @PeerManagerStaffID)
    THROW 51022, 'FAIL: a manager can view the other manager''s confidential employment profile.', 1;
SELECT * FROM #VisibleStaff ORDER BY Position, StaffID;

SELECT * FROM api.vw_CustomerAccountSummary;        -- SUCCESS: all accounts; customer name/email remain dynamically masked.
SELECT * FROM api.vw_MyTransactions ORDER BY TransDate DESC; -- SUCCESS: all transaction records.

-- SUCCESS: each manager updates only that manager's own non-salary contact columns.
DECLARE @ExpectedName nvarchar(100) =
    CASE ORIGINAL_LOGIN()
        WHEN N'sb_manager_daniel' THEN N'Daniel Wong'
        WHEN N'sb_manager_siti' THEN N'Siti Aminah'
    END;
DECLARE @ExpectedPhone varchar(20) =
    CASE ORIGINAL_LOGIN()
        WHEN N'sb_manager_daniel' THEN '012-3101002'
        WHEN N'sb_manager_siti' THEN '012-3101007'
    END;
EXEC api.usp_UpdateOwnStaffProfile @StaffName = @ExpectedName, @Phone = @ExpectedPhone;

-- SUCCESS: controlled officer update; salary is only changed inside the procedure.
EXEC api.usp_ManagerUpdateOfficer
    @StaffID = 'S00003', @StaffName = N'Farid Iskandar', @Phone = '012-3101093',
    @BranchID = 'B0001', @Salary = 5300.00;
GO

-- EXPECTED VALIDATION FAILURE: a manager cannot update the other manager through the officer API.
IF ORIGINAL_LOGIN() = N'sb_manager_daniel'
    EXEC api.usp_ManagerUpdateOfficer @StaffID = 'S00007', @StaffName = N'Siti Aminah',
         @Phone = '012-3101007', @BranchID = 'B0002', @Salary = 10900.00;
ELSE IF ORIGINAL_LOGIN() = N'sb_manager_siti'
    EXEC api.usp_ManagerUpdateOfficer @StaffID = 'S00002', @StaffName = N'Daniel Wong',
         @Phone = '012-3101002', @BranchID = 'B0001', @Salary = 11500.00;
GO

-- EXPECTED VALIDATION FAILURE: a manager cannot deactivate the other manager through the officer API.
IF ORIGINAL_LOGIN() = N'sb_manager_daniel'
    EXEC api.usp_ManagerDeactivateOfficer @StaffID = 'S00007';
ELSE IF ORIGINAL_LOGIN() = N'sb_manager_siti'
    EXEC api.usp_ManagerDeactivateOfficer @StaffID = 'S00002';
GO

-- EXPECTED DENIAL: manager cannot directly update base data.
UPDATE core.StaffEmployment SET SalaryCipher = 0x00 WHERE StaffID = 'S00003';
GO

-- EXPECTED DENIAL: only customers can execute transactions.
EXEC api.usp_PerformTransaction 'DEPOSIT', 'A000000001', NULL, 10.00, '482731', 'ONLINE';
GO
