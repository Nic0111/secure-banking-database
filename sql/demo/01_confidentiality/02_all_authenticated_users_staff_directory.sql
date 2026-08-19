-- Run as: any SmartBank login.
USE [SmartBankDB];
GO

-- Every authenticated user can see the common staff directory.
SELECT StaffID, StaffName, Phone
FROM api.vw_StaffDirectory
ORDER BY StaffID;

-- Expected result: permission denied. Direct access to the protected table is blocked.
SELECT TOP (1) *
FROM core.Staff;
GO
