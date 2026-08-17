-- Connect as: any demonstration login.
USE [SmartBankDB];
GO

-- Every authenticated user can read the limited staff directory.
SELECT StaffID, StaffName, Phone
FROM api.vw_StaffDirectory
ORDER BY StaffID;
GO

-- EXPECTED DENIAL: the base staff table remains protected.
SELECT * FROM core.Staff;
GO
