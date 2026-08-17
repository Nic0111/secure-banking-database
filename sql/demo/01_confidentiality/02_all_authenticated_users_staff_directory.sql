/*
ASSIGNMENT SECTION:
Section 1 - Confidentiality

REQUIREMENT:
2. All authenticated users may view staff name and contact number.

RUN AS:
Rerun in a fresh connection as every demonstration login: DBA, both managers,
both officers, both customers and the security auditor.

EXPECTED RESULT:
The controlled directory returns the seven active staff IDs, names and phone
numbers. Direct access to the protected core.Staff table is denied.

PASS CONDITION:
Every authenticated login returns exactly seven directory rows through the API
view and the direct base-table query is rejected.

DATABASE CHANGES:
None. This script is read-only.
*/
USE [SmartBankDB];
GO
SET NOCOUNT ON;
GO

IF IS_ROLEMEMBER(N'rl_authenticated') <> 1
    THROW 51110, 'Run this script as a SmartBank authenticated demonstration login.', 1;

SELECT ORIGINAL_LOGIN() AS AuthenticatedLogin,
       USER_NAME() AS DatabaseUser,
       CONNECTIONPROPERTY('auth_scheme') AS AuthenticationScheme;

CREATE TABLE #Directory
(
    StaffID char(6) NOT NULL,
    StaffName nvarchar(100) NOT NULL,
    Phone varchar(20) NOT NULL
);

INSERT #Directory (StaffID, StaffName, Phone)
SELECT StaffID, StaffName, Phone FROM api.vw_StaffDirectory;

SELECT StaffID, StaffName, Phone
FROM #Directory
ORDER BY StaffID;

IF (SELECT COUNT(*) FROM #Directory) <> 7
    THROW 51111, 'FAIL - the authenticated staff directory does not match the golden baseline.', 1;

BEGIN TRY
    EXEC sys.sp_executesql N'SELECT TOP (1) * FROM core.Staff;';
    THROW 51112, 'FAIL - direct access to core.Staff unexpectedly succeeded.', 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51112 THROW;
    SELECT N'PASS' AS Result,
           N'Direct core.Staff access was denied; only the directory projection is available.' AS Evidence,
           ERROR_NUMBER() AS DenialErrorNumber,
           ERROR_MESSAGE() AS DenialMessage;
END CATCH;
GO
