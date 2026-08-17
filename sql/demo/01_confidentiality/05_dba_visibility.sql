/*
ASSIGNMENT SECTION:
Section 1 - Confidentiality

REQUIREMENT:
5. DBA may view only their own staff record.

RUN AS:
sb_dba_aisha in a fresh SQL-authenticated connection.

EXPECTED RESULT:
The DBA receives Aisha's own full staff record and the common name/contact
directory. Manager staff profiles, customer accounts, transactions and direct
business-table reads are denied.

PASS CONDITION:
Exactly one full profile with StaffID S00001 is returned and all broader business
data attempts are rejected.

DATABASE CHANGES:
None. This script is read-only.
*/
USE [SmartBankDB];
GO
SET NOCOUNT ON;
GO

IF ORIGINAL_LOGIN() <> N'sb_dba_aisha' OR IS_ROLEMEMBER(N'rl_dba') <> 1
    THROW 51140, 'Run this script as sb_dba_aisha.', 1;

CREATE TABLE #OwnProfile
(
    StaffID char(6), StaffName nvarchar(100), Position varchar(20),
    BranchName nvarchar(100), Phone varchar(20), Salary decimal(19, 2), IsActive bit
);
INSERT #OwnProfile EXEC api.usp_GetMyStaffProfile;
SELECT N'DBA own record' AS Evidence, * FROM #OwnProfile;

IF (SELECT COUNT(*) FROM #OwnProfile) <> 1
   OR NOT EXISTS (SELECT 1 FROM #OwnProfile WHERE StaffID = 'S00001' AND Position = 'DBA')
    THROW 51141, 'FAIL - DBA own-record visibility is incorrect.', 1;

SELECT N'Common staff name/contact directory' AS Evidence, StaffID, StaffName, Phone
FROM api.vw_StaffDirectory ORDER BY StaffID;

DECLARE @Denied table (Attempt nvarchar(100), ErrorNumber int, ErrorMessage nvarchar(4000));
BEGIN TRY
    EXEC sys.sp_executesql N'EXEC api.usp_ManagerGetStaffProfiles;';
    THROW 51142, 'FAIL - DBA unexpectedly executed the manager profile procedure.', 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51142 THROW;
    INSERT @Denied VALUES (N'Manager staff profiles', ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;
BEGIN TRY
    EXEC sys.sp_executesql N'SELECT TOP (1) * FROM api.vw_CustomerAccountSummary;';
    THROW 51143, 'FAIL - DBA unexpectedly read customer accounts.', 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51143 THROW;
    INSERT @Denied VALUES (N'Customer accounts', ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;
BEGIN TRY
    EXEC sys.sp_executesql N'SELECT TOP (1) * FROM api.vw_MyTransactions;';
    THROW 51144, 'FAIL - DBA unexpectedly read customer transactions.', 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51144 THROW;
    INSERT @Denied VALUES (N'Customer transactions', ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;
BEGIN TRY
    EXEC sys.sp_executesql N'SELECT TOP (1) * FROM core.Staff;';
    THROW 51145, 'FAIL - DBA unexpectedly read core.Staff directly.', 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51145 THROW;
    INSERT @Denied VALUES (N'Direct core.Staff read', ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;

SELECT N'PASS' AS Result, Attempt, ErrorNumber, ErrorMessage AS ExpectedDenial
FROM @Denied ORDER BY Attempt;
IF (SELECT COUNT(*) FROM @Denied) <> 4
    THROW 51146, 'FAIL - not all DBA overreach attempts were denied.', 1;
GO
