/*
ASSIGNMENT SECTION:
Section 1 - Confidentiality

REQUIREMENT:
4. Bank Officers may view only their own staff record, all customer accounts and
all transactions.

RUN AS:
Run once as sb_officer_farid and once as sb_officer_priya using fresh connections.

EXPECTED RESULT:
The profile procedure returns only the connected officer. The account and
transaction views return all 18 and 44 baseline rows. Manager-only staff access
and direct protected-table access are denied.

PASS CONDITION:
The returned StaffID matches the authenticated officer, global account/transaction
counts match baseline, and both broader staff-access attempts fail.

DATABASE CHANGES:
None. This script is read-only.
*/
USE [SmartBankDB];
GO
SET NOCOUNT ON;
GO

IF IS_ROLEMEMBER(N'rl_officer') <> 1
    THROW 51130, 'Run this script as one of the two bank-officer logins.', 1;

DECLARE @ExpectedOfficerID char(6) =
    CASE ORIGINAL_LOGIN()
        WHEN N'sb_officer_farid' THEN 'S00003'
        WHEN N'sb_officer_priya' THEN 'S00004'
    END;
IF @ExpectedOfficerID IS NULL
    THROW 51131, 'The connected login is not a mapped demonstration officer.', 1;

CREATE TABLE #OwnProfile
(
    StaffID char(6), StaffName nvarchar(100), Position varchar(20),
    BranchName nvarchar(100), Phone varchar(20), Salary decimal(19, 2), IsActive bit
);
INSERT #OwnProfile EXEC api.usp_GetMyStaffProfile;
SELECT N'Connected officer own record' AS Evidence, * FROM #OwnProfile;

IF (SELECT COUNT(*) FROM #OwnProfile) <> 1
   OR NOT EXISTS (SELECT 1 FROM #OwnProfile WHERE StaffID = @ExpectedOfficerID AND Position = 'BANK_OFFICER')
    THROW 51132, 'FAIL - the officer profile is not restricted to the connected officer.', 1;

SELECT N'All customer accounts' AS Evidence, *
FROM api.vw_CustomerAccountSummary ORDER BY AccountID;
SELECT N'All transactions' AS Evidence, *
FROM api.vw_MyTransactions ORDER BY TransID;

IF (SELECT COUNT(*) FROM api.vw_CustomerAccountSummary) <> 18
   OR (SELECT COUNT(*) FROM api.vw_MyTransactions) <> 44
    THROW 51133, 'FAIL - officer account or transaction visibility does not match the golden baseline.', 1;

BEGIN TRY
    EXEC sys.sp_executesql N'EXEC api.usp_ManagerGetStaffProfiles;';
    THROW 51134, 'FAIL - officer unexpectedly executed the manager staff procedure.', 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51134 THROW;
    SELECT N'PASS' AS Result, N'Manager-only staff access was denied.' AS Evidence,
           ERROR_MESSAGE() AS ExpectedDenial;
END CATCH;

BEGIN TRY
    EXEC sys.sp_executesql N'SELECT TOP (1) * FROM core.StaffEmployment;';
    THROW 51135, 'FAIL - officer direct employment-table access unexpectedly succeeded.', 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51135 THROW;
    SELECT N'PASS' AS Result,
           N'Officer has the required API visibility without direct protected-table access.' AS Evidence,
           ERROR_MESSAGE() AS ExpectedDenial;
END CATCH;
GO
