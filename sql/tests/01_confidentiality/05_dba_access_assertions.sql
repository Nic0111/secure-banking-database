-- Connect as: sb_dba_aisha or sb_dba_kavitha.
USE [SmartBankDB];
GO

-- The DBA sees the directory and only the DBA's own staff profile.
SELECT * FROM api.vw_StaffDirectory;
EXEC api.usp_GetMyStaffProfile;
GO

-- EXPECTED DENIAL: the DBA role cannot read business tables or manager data.
DECLARE @BusinessTableReadDenied bit = 0;
BEGIN TRY
    SELECT * FROM core.Staff;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() <> 229
        THROW;

    SET @BusinessTableReadDenied = 1;
    SELECT N'PASS - direct business-table read denied to DBA' AS Result,
           ERROR_NUMBER() AS ActualErrorNumber,
           ERROR_MESSAGE() AS ActualErrorMessage;
END CATCH;

IF @BusinessTableReadDenied = 0
    THROW 51116, 'FAIL: the DBA unexpectedly read core.Staff directly.', 1;

DECLARE @ManagerProcedureDenied bit = 0;
BEGIN TRY
    EXEC api.usp_ManagerGetStaffProfiles;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() <> 229
        THROW;

    SET @ManagerProcedureDenied = 1;
    SELECT N'PASS - manager procedure denied to DBA' AS Result,
           ERROR_NUMBER() AS ActualErrorNumber,
           ERROR_MESSAGE() AS ActualErrorMessage;
END CATCH;

IF @ManagerProcedureDenied = 0
    THROW 51117, 'FAIL: the DBA unexpectedly executed the manager profile procedure.', 1;
GO
