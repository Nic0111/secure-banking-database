-- Run as: sa first, then run again in a fresh SSMS connection for each user.
USE [SmartBankDB];
GO

-- Run as sa to show every login, user, and role.
IF IS_SRVROLEMEMBER(N'sysadmin') = 1
BEGIN
    SELECT loginInfo.name AS LoginName, loginInfo.is_disabled AS IsDisabled,
           databaseUser.name AS DatabaseUser, principalMap.UserType,
           roleInfo.name AS DatabaseRole
    FROM master.sys.server_principals AS loginInfo
    LEFT JOIN sys.database_principals AS databaseUser ON databaseUser.sid = loginInfo.sid
    LEFT JOIN sec.PrincipalMap AS principalMap ON principalMap.LoginName = loginInfo.name
    LEFT JOIN sys.database_role_members AS membership ON membership.member_principal_id = databaseUser.principal_id
    LEFT JOIN sys.database_principals AS roleInfo ON roleInfo.principal_id = membership.role_principal_id
    WHERE loginInfo.name LIKE N'sb[_]%'
    ORDER BY loginInfo.name, roleInfo.name;
END
ELSE
BEGIN
    -- Run as a named user to prove the real SSMS login and mapped role.
    SELECT ORIGINAL_LOGIN() AS LoginName, USER_NAME() AS DatabaseUser,
           DB_NAME() AS DatabaseName,
           IS_ROLEMEMBER(N'rl_authenticated') AS IsAuthenticated,
           CASE WHEN IS_ROLEMEMBER(N'rl_dba') = 1 THEN N'DBA'
                WHEN IS_ROLEMEMBER(N'rl_manager') = 1 THEN N'Manager'
                WHEN IS_ROLEMEMBER(N'rl_officer') = 1 THEN N'Officer'
                WHEN IS_ROLEMEMBER(N'rl_customer') = 1 THEN N'Customer'
                WHEN IS_ROLEMEMBER(N'rl_security_auditor') = 1 THEN N'Auditor'
           END AS RoleShown;
END;
GO
