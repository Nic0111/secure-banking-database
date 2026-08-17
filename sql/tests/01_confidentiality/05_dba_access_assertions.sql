-- Connect as: sb_dba_aisha.
USE [SmartBankDB];
GO

-- The DBA sees the directory and only the DBA's own staff profile.
SELECT * FROM api.vw_StaffDirectory;
EXEC api.usp_GetMyStaffProfile;
GO

-- EXPECTED DENIAL: the DBA role cannot read business tables or manager data.
SELECT * FROM core.Staff;
EXEC api.usp_ManagerGetStaffProfiles;
GO
