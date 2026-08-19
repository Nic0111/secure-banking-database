-- Run as: sa.
USE [SmartBankDB];
GO

DECLARE @StartTime datetime2(3) = SYSUTCDATETIME();

-- Create a temporary user, give it a role and permission, then show the grant.
CREATE USER [sb_demo_temporary_user] WITHOUT LOGIN;
ALTER ROLE rl_authenticated ADD MEMBER [sb_demo_temporary_user];
GRANT SELECT ON OBJECT::api.vw_StaffDirectory TO [sb_demo_temporary_user];

SELECT principalInfo.name AS DatabaseUser, roleInfo.name AS DatabaseRole,
       permissionInfo.state_desc AS PermissionState, permissionInfo.permission_name AS PermissionName
FROM sys.database_principals AS principalInfo
LEFT JOIN sys.database_role_members AS membership ON membership.member_principal_id = principalInfo.principal_id
LEFT JOIN sys.database_principals AS roleInfo ON roleInfo.principal_id = membership.role_principal_id
LEFT JOIN sys.database_permissions AS permissionInfo ON permissionInfo.grantee_principal_id = principalInfo.principal_id
WHERE principalInfo.name = N'sb_demo_temporary_user';

-- Undo the temporary change after showing it.
REVOKE SELECT ON OBJECT::api.vw_StaffDirectory FROM [sb_demo_temporary_user];
ALTER ROLE rl_authenticated DROP MEMBER [sb_demo_temporary_user];
DROP USER [sb_demo_temporary_user];

-- Show the user, role, and permission changes in SQL Server Audit.
WAITFOR DELAY '00:00:02';
EXEC audit.usp_ReadNativeAudit @StartTime = @StartTime, @EndTime = NULL, @OnlyFailures = 0;
GO
