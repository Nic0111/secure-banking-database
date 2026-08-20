-- Run as: sa (server administrator).
-- Wires the SQL login for the officer record the manager hired in
-- 02_manager_manages_staff.sql. Run that script as sb_manager_daniel first.
USE [master];
GO

-- Login creation needs server-level ALTER ANY LOGIN, so the server
-- administrator performs it. No SmartBank role, including the DBA, can
-- create or alter SQL logins.
IF SUSER_ID(N'sb_officer_demo') IS NULL
    CREATE LOGIN [sb_officer_demo] WITH PASSWORD = N'SBan!Off_2026#Demo';
GO

USE [SmartBankDB];
GO

IF USER_ID(N'sb_officer_demo') IS NULL
    CREATE USER [sb_officer_demo] FOR LOGIN [sb_officer_demo];
IF NOT EXISTS
(
    SELECT 1
    FROM sys.database_role_members
    INNER JOIN sys.database_principals AS member ON member.principal_id = sys.database_role_members.member_principal_id
    INNER JOIN sys.database_principals AS role ON role.principal_id = sys.database_role_members.role_principal_id
    WHERE member.name = N'sb_officer_demo' AND role.name = N'rl_officer'
)
    EXEC sp_addrolemember N'rl_officer', N'sb_officer_demo';
IF NOT EXISTS (SELECT 1 FROM sec.PrincipalMap WHERE LoginName = N'sb_officer_demo')
    INSERT sec.PrincipalMap (LoginName, DatabaseUserName, UserType, StaffID)
    VALUES (N'sb_officer_demo', N'sb_officer_demo', 'OFFICER', 'S00008');

SELECT LoginName, DatabaseUserName, UserType, StaffID, IsActive
FROM sec.PrincipalMap
WHERE LoginName = N'sb_officer_demo';
GO

-- Verify in a fresh SSMS window connected as sb_officer_demo
-- (password SBan!Off_2026#Demo):
--   EXEC api.usp_GetMyStaffProfile;          -> own profile, salary 5200.00
--   SELECT * FROM core.Staff;                -> permission denied
GO
