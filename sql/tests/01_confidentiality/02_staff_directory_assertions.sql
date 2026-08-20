-- Connect as: any non-customer demonstration login.
USE [SmartBankDB];
GO

-- Every non-customer authenticated user can read the staff directory.
SELECT StaffID, StaffName, Phone
FROM api.vw_StaffDirectory
ORDER BY StaffID;
GO

-- EXPECTED DENIAL: the base staff table remains protected.
DECLARE @BaseTableReadDenied bit = 0;
BEGIN TRY
    SELECT * FROM core.Staff;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() <> 229
        THROW;

    SET @BaseTableReadDenied = 1;
    SELECT N'PASS - direct core.Staff read denied' AS Result,
           ERROR_NUMBER() AS ActualErrorNumber,
           ERROR_MESSAGE() AS ActualErrorMessage;
END CATCH;

IF @BaseTableReadDenied = 0
    THROW 51102, 'FAIL: an authenticated user unexpectedly read core.Staff directly.', 1;
GO
