/*
ASSIGNMENT SECTION:
Section 1 - Confidentiality

REQUIREMENT:
3. Bank Managers may view their own record, all staff (Bank Officers) records,
all customer accounts and all transactions.

RUN AS:
Run once as sb_manager_daniel and once as sb_manager_siti using fresh connections.

EXPECTED RESULT:
Each manager sees their own full staff record plus all four officer records, all
18 baseline accounts and all 44 baseline transactions. The peer manager and DBA
full records are excluded, and direct core-table access is denied.

PASS CONDITION:
The staff result contains exactly the connected manager and four officers; account
and transaction counts match the golden baseline with no direct table permission.

DATABASE CHANGES:
None. This script is read-only.
*/
USE [SmartBankDB];
GO
SET NOCOUNT ON;
GO

IF IS_ROLEMEMBER(N'rl_manager') <> 1
    THROW 51120, 'Run this script as one of the two bank-manager logins.', 1;

DECLARE @ExpectedManagerID char(6) =
    CASE ORIGINAL_LOGIN()
        WHEN N'sb_manager_daniel' THEN 'S00002'
        WHEN N'sb_manager_siti' THEN 'S00007'
    END;
IF @ExpectedManagerID IS NULL
    THROW 51121, 'The connected login is not a mapped demonstration manager.', 1;

CREATE TABLE #StaffProfiles
(
    StaffID char(6), StaffName nvarchar(100), Position varchar(20),
    BranchName nvarchar(100), Phone varchar(20), Salary decimal(19, 2), IsActive bit
);
INSERT #StaffProfiles EXEC api.usp_ManagerGetStaffProfiles;

SELECT N'Manager and supervised officers' AS Evidence, *
FROM #StaffProfiles
ORDER BY Position, StaffID;

IF (SELECT COUNT(*) FROM #StaffProfiles) <> 5
   OR NOT EXISTS (SELECT 1 FROM #StaffProfiles WHERE StaffID = @ExpectedManagerID AND Position = 'BANK_MANAGER')
   OR (SELECT COUNT(*) FROM #StaffProfiles WHERE Position = 'BANK_OFFICER') <> 4
   OR EXISTS (SELECT 1 FROM #StaffProfiles WHERE Position = 'DBA')
   OR EXISTS (SELECT 1 FROM #StaffProfiles WHERE Position = 'BANK_MANAGER' AND StaffID <> @ExpectedManagerID)
    THROW 51122, 'FAIL - manager staff visibility exceeds or falls short of the assignment boundary.', 1;

SELECT N'All customer accounts' AS Evidence, *
FROM api.vw_CustomerAccountSummary
ORDER BY AccountID;

SELECT N'All transactions' AS Evidence, *
FROM api.vw_MyTransactions
ORDER BY TransID;

IF (SELECT COUNT(*) FROM api.vw_CustomerAccountSummary) <> 18
   OR (SELECT COUNT(*) FROM api.vw_MyTransactions) <> 44
    THROW 51123, 'FAIL - manager account or transaction visibility does not match the golden baseline.', 1;

BEGIN TRY
    EXEC sys.sp_executesql N'SELECT TOP (1) * FROM core.Customer;';
    THROW 51124, 'FAIL - manager direct core.Customer access unexpectedly succeeded.', 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51124 THROW;
    SELECT N'PASS' AS Result,
           N'Manager has the required API visibility without direct protected-table access.' AS Evidence,
           ERROR_MESSAGE() AS ExpectedDenial;
END CATCH;
GO
