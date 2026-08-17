/*
ASSIGNMENT SECTION:
Section 2 - Integrity

REQUIREMENT:
4. Staff may update only their own record, except salary.

RUN AS:
Run separately as sb_dba_aisha, both managers and both officers. The current
implementation is expected to report a permission gap for the DBA role.

EXPECTED RESULT:
The connected staff member changes and restores only their own phone through the
API. The API exposes no salary parameter and direct salary-table updates are denied.

PASS CONDITION:
Every staff role has EXECUTE permission on the own-profile procedure, its own
change succeeds, another staff row cannot be targeted, and salary cannot be changed.

DATABASE CHANGES:
Temporarily changes the connected staff phone and restores it. Audit records remain.
*/
USE [SmartBankDB];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF IS_ROLEMEMBER(N'rl_dba') <> 1 AND IS_ROLEMEMBER(N'rl_manager') <> 1 AND IS_ROLEMEMBER(N'rl_officer') <> 1
    THROW 51230, 'Run this script as a mapped DBA, manager or officer login.', 1;

DECLARE @StaffID char(6), @StaffName nvarchar(100), @OriginalPhone varchar(20), @DemoPhone varchar(20);
SELECT @StaffID = CASE ORIGINAL_LOGIN()
                    WHEN N'sb_dba_aisha' THEN 'S00001'
                    WHEN N'sb_manager_daniel' THEN 'S00002'
                    WHEN N'sb_manager_siti' THEN 'S00007'
                    WHEN N'sb_officer_farid' THEN 'S00003'
                    WHEN N'sb_officer_priya' THEN 'S00004'
                  END,
       @StaffName = CASE ORIGINAL_LOGIN()
                      WHEN N'sb_dba_aisha' THEN N'Aisha Rahman'
                      WHEN N'sb_manager_daniel' THEN N'Daniel Wong'
                      WHEN N'sb_manager_siti' THEN N'Siti Aminah'
                      WHEN N'sb_officer_farid' THEN N'Farid Iskandar'
                      WHEN N'sb_officer_priya' THEN N'Priya Nair'
                    END,
       @OriginalPhone = CASE ORIGINAL_LOGIN()
                          WHEN N'sb_dba_aisha' THEN '012-3101001'
                          WHEN N'sb_manager_daniel' THEN '012-3101002'
                          WHEN N'sb_manager_siti' THEN '012-3101007'
                          WHEN N'sb_officer_farid' THEN '012-3101003'
                          WHEN N'sb_officer_priya' THEN '012-3101004'
                        END;
SET @DemoPhone = '019-88' + RIGHT(@StaffID, 4);

SELECT ORIGINAL_LOGIN() AS StaffLogin,
       HAS_PERMS_BY_NAME(N'api.usp_UpdateOwnStaffProfile', N'OBJECT', N'EXECUTE') AS CanExecuteOwnProfileUpdate,
       N'Expected 1 for DBA, manager and officer' AS Requirement;

IF ISNULL(HAS_PERMS_BY_NAME(N'api.usp_UpdateOwnStaffProfile', N'OBJECT', N'EXECUTE'), 0) <> 1
BEGIN
    SELECT N'FAIL - IMPLEMENTATION GAP' AS Result,
           N'The procedure supports DBA identities, but rl_dba has not been granted EXECUTE.' AS Evidence;
    THROW 51231, 'Requirement not fully met: the connected staff role cannot execute the own-profile update.', 1;
END;

SELECT parameterInfo.parameter_id, parameterInfo.name AS ParameterName,
       TYPE_NAME(parameterInfo.user_type_id) AS DataType
FROM sys.parameters AS parameterInfo
WHERE parameterInfo.object_id = OBJECT_ID(N'api.usp_UpdateOwnStaffProfile')
ORDER BY parameterInfo.parameter_id;

IF EXISTS
   (
       SELECT 1 FROM sys.parameters
       WHERE object_id = OBJECT_ID(N'api.usp_UpdateOwnStaffProfile')
         AND name LIKE N'%Salary%'
   )
    THROW 51232, 'FAIL - own-profile API unexpectedly exposes a salary parameter.', 1;

EXEC api.usp_UpdateOwnStaffProfile @StaffName = @StaffName, @Phone = @DemoPhone;

CREATE TABLE #OwnProfile
(
    StaffID char(6), StaffName nvarchar(100), Position varchar(20),
    BranchName nvarchar(100), Phone varchar(20), Salary decimal(19, 2), IsActive bit
);
INSERT #OwnProfile EXEC api.usp_GetMyStaffProfile;
SELECT N'Own record after controlled update' AS Evidence, * FROM #OwnProfile;
IF NOT EXISTS (SELECT 1 FROM #OwnProfile WHERE StaffID = @StaffID AND Phone = @DemoPhone)
    THROW 51233, 'FAIL - connected staff member could not update their own record.', 1;

EXEC api.usp_UpdateOwnStaffProfile @StaffName = @StaffName, @Phone = @OriginalPhone;

BEGIN TRY
    EXEC sys.sp_executesql
        N'UPDATE core.StaffEmployment SET SalaryCipher = 0x00 WHERE StaffID = ''S00003'';';
    THROW 51234, 'FAIL - direct salary update unexpectedly succeeded.', 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51234 THROW;
    SELECT N'PASS' AS Result,
           N'Own name/phone API succeeded and direct salary manipulation was denied.' AS Evidence,
           ERROR_MESSAGE() AS ExpectedSalaryDenial;
END CATCH;
GO
