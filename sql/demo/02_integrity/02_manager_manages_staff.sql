/*
ASSIGNMENT SECTION:
Section 2 - Integrity

REQUIREMENT:
2. Bank Managers may manage Bank Officer staff records.

RUN AS:
Run as sb_manager_daniel or sb_manager_siti in a fresh connection.

EXPECTED RESULT:
The manager updates one officer through the controlled API and restores the golden
value. Updating a manager as if they were an officer and directly updating the
core table are both rejected.

PASS CONDITION:
The allowed officer update is visible, the original values are restored, and both
invalid/unauthorized attempts fail. The later audit script shows all outcomes.

DATABASE CHANGES:
Temporarily updates one officer's phone and encrypted salary, then restores both.
Audit records are intentionally retained.
*/
USE [SmartBankDB];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF IS_ROLEMEMBER(N'rl_manager') <> 1
    THROW 51210, 'Run this script as a bank-manager login.', 1;

DECLARE @OfficerID char(6) = IIF(ORIGINAL_LOGIN() = N'sb_manager_daniel', 'S00003', 'S00004');
DECLARE @OfficerName nvarchar(100) = IIF(@OfficerID = 'S00003', N'Farid Iskandar', N'Priya Nair');
DECLARE @OriginalPhone varchar(20) = IIF(@OfficerID = 'S00003', '012-3101003', '012-3101004');
DECLARE @DemoPhone varchar(20) = IIF(@OfficerID = 'S00003', '012-3199003', '012-3199004');
DECLARE @BranchID char(5) = IIF(@OfficerID = 'S00003', 'B0001', 'B0002');
DECLARE @OriginalSalary decimal(19, 2) = IIF(@OfficerID = 'S00003', 5200.00, 5400.00);
DECLARE @DemoSalary decimal(19, 2) = @OriginalSalary + 25.00;

EXEC api.usp_ManagerUpdateOfficer
     @StaffID = @OfficerID, @StaffName = @OfficerName, @Phone = @DemoPhone,
     @BranchID = @BranchID, @Salary = @DemoSalary;

CREATE TABLE #ManagerView
(
    StaffID char(6), StaffName nvarchar(100), Position varchar(20),
    BranchName nvarchar(100), Phone varchar(20), Salary decimal(19, 2), IsActive bit
);
INSERT #ManagerView EXEC api.usp_ManagerGetStaffProfiles;
SELECT N'Allowed manager update' AS Evidence, *
FROM #ManagerView WHERE StaffID = @OfficerID;
IF NOT EXISTS (SELECT 1 FROM #ManagerView WHERE StaffID = @OfficerID AND Phone = @DemoPhone AND Salary = @DemoSalary)
    THROW 51211, 'FAIL - controlled manager update was not visible.', 1;

EXEC api.usp_ManagerUpdateOfficer
     @StaffID = @OfficerID, @StaffName = @OfficerName, @Phone = @OriginalPhone,
     @BranchID = @BranchID, @Salary = @OriginalSalary;

DECLARE @Rejected table (Attempt nvarchar(120), ErrorNumber int, ErrorMessage nvarchar(4000));
BEGIN TRY
    EXEC api.usp_ManagerUpdateOfficer
         @StaffID = 'S00007', @StaffName = N'Siti Aminah', @Phone = '012-3101007',
         @BranchID = 'B0002', @Salary = 10900.00;
    THROW 51212, 'FAIL - manager-to-manager staff update unexpectedly succeeded.', 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51212 THROW;
    INSERT @Rejected VALUES (N'Update a manager through the officer-only API', ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    EXEC sys.sp_executesql N'UPDATE core.Staff SET Phone = ''012-0000000'' WHERE StaffID = ''S00003'';';
    THROW 51213, 'FAIL - direct manager update of core.Staff unexpectedly succeeded.', 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51213 THROW;
    INSERT @Rejected VALUES (N'Direct update of core.Staff', ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;

SELECT N'PASS' AS Result, Attempt, ErrorNumber, ErrorMessage AS ExpectedRejection
FROM @Rejected ORDER BY Attempt;
IF (SELECT COUNT(*) FROM @Rejected) <> 2
    THROW 51214, 'FAIL - one or more invalid manager operations were not rejected.', 1;
GO
