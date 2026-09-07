-- Run as: sb_dba_aisha or sb_dba_kavitha.
USE [SmartBankDB];
GO

-- The DBA can see only the DBA profile through the approved procedure.
EXEC api.usp_GetMyStaffProfile;

-- The shared directory is available to all authenticated users.
SELECT StaffID, StaffName, Phone FROM api.vw_StaffDirectory ORDER BY StaffID;

-- Expected result: permission denied. The DBA does not read customer business data.
SELECT TOP (1) * FROM api.vw_CustomerAccountSummary;
GO
