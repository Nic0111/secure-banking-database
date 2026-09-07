-- Run as: sa.
-- Wires the SQL login for the officer record the manager hired in
-- 02_manager_manages_staff.sql. Run that script as sb_manager_daniel first.
USE [master];
GO

-- Login creation needs server-level ALTER ANY LOGIN, so the server
-- administrator performs it. No SmartBank role, including the DBA, can
-- create or alter SQL logins.
IF SUSER_ID(N'sb_officer_demo') IS NULL
    CREATE LOGIN [sb_officer_demo]
    WITH PASSWORD = N'SBan!Off_2026#Demo', DEFAULT_DATABASE = [SmartBankDB];
ELSE
    ALTER LOGIN [sb_officer_demo] WITH DEFAULT_DATABASE = [SmartBankDB];
GO

USE [SmartBankDB];
GO

-- Do not give a login to an officer who was already deactivated.
IF NOT EXISTS
(
    SELECT 1
    FROM core.Staff AS staff
    INNER JOIN core.StaffEmployment AS employment ON employment.StaffID = staff.StaffID
    WHERE staff.StaffID = 'S00008'
      AND staff.IsActive = 1
      AND employment.Position = 'BANK_OFFICER'
)
    THROW 52500, 'S00008 must be an active bank officer before a login is wired.', 1;

IF EXISTS
(
    SELECT 1
    FROM sec.PrincipalMap
    WHERE LoginName = N'sb_officer_demo'
      AND (DatabaseUserName <> N'sb_officer_demo' OR UserType <> 'OFFICER'
           OR StaffID <> 'S00008' OR IsActive = 0)
)
    THROW 52501, 'The existing demo-login mapping is incompatible or inactive. Reset before wiring it again.', 1;

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
    ALTER ROLE rl_officer ADD MEMBER [sb_officer_demo];
IF NOT EXISTS
(
    SELECT 1
    FROM sys.database_role_members
    WHERE role_principal_id = DATABASE_PRINCIPAL_ID(N'rl_authenticated')
      AND member_principal_id = USER_ID(N'sb_officer_demo')
)
    ALTER ROLE rl_authenticated ADD MEMBER [sb_officer_demo];
IF NOT EXISTS (SELECT 1 FROM sec.PrincipalMap WHERE LoginName = N'sb_officer_demo')
    INSERT sec.PrincipalMap (LoginName, DatabaseUserName, UserType, StaffID)
    VALUES (N'sb_officer_demo', N'sb_officer_demo', 'OFFICER', 'S00008');

SELECT LoginName, DatabaseUserName, UserType, StaffID, IsActive
FROM sec.PrincipalMap
WHERE LoginName = N'sb_officer_demo';
GO

-- Deny the new non-DBA login direct backup-catalog access.
USE [msdb];
GO
IF USER_ID(N'sb_officer_demo') IS NULL
    CREATE USER [sb_officer_demo] FOR LOGIN [sb_officer_demo];
ELSE
    ALTER USER [sb_officer_demo] WITH LOGIN = [sb_officer_demo];
DENY SELECT ON OBJECT::dbo.backupset TO [sb_officer_demo];
DENY SELECT ON OBJECT::dbo.backupmediafamily TO [sb_officer_demo];
GO

-- Verify in a fresh SSMS window connected as sb_officer_demo
-- (password SBan!Off_2026#Demo):
--   EXEC api.usp_GetMyStaffProfile;          -> own profile, salary 5200.00
--   SELECT * FROM core.Staff;                -> permission denied
GO
