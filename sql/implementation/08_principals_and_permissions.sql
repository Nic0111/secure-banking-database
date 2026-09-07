USE [master];
GO
SET NOCOUNT ON;
GO

-- Create the demonstration logins.
DECLARE @Logins table (LoginName sysname PRIMARY KEY, LoginPassword nvarchar(256));
INSERT @Logins (LoginName, LoginPassword)
VALUES (N'sb_dba_aisha', N'$(DbaLoginPassword)'),
       (N'sb_dba_kavitha', N'$(DbaKavithaLoginPassword)'),
       (N'sb_manager_daniel', N'$(ManagerDanielLoginPassword)'),
       (N'sb_manager_siti', N'$(ManagerSitiLoginPassword)'),
       (N'sb_officer_farid', N'$(OfficerFaridLoginPassword)'),
       (N'sb_officer_priya', N'$(OfficerPriyaLoginPassword)'),
       (N'sb_customer_amelia', N'$(CustomerAmeliaLoginPassword)'),
       (N'sb_customer_hafiz', N'$(CustomerHafizLoginPassword)'),
       (N'sb_auditor_noor', N'$(AuditorLoginPassword)');

IF (SELECT COUNT(DISTINCT LoginPassword) FROM @Logins) <> (SELECT COUNT(*) FROM @Logins)
    THROW 50310, 'Every SmartBank demonstration login must have a distinct password.', 1;

DECLARE @LoginName sysname, @LoginPassword nvarchar(256), @CreateLoginSql nvarchar(max);
DECLARE login_cursor CURSOR LOCAL FAST_FORWARD FOR SELECT LoginName, LoginPassword FROM @Logins;
OPEN login_cursor;
FETCH NEXT FROM login_cursor INTO @LoginName, @LoginPassword;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF SUSER_ID(@LoginName) IS NULL
       OR PWDCOMPARE(@LoginPassword, CONVERT(varbinary(256), LOGINPROPERTY(@LoginName, 'PasswordHash'))) = 0
    BEGIN
        SET @CreateLoginSql = CASE WHEN SUSER_ID(@LoginName) IS NULL THEN N'CREATE' ELSE N'ALTER' END +
            N' LOGIN ' + QUOTENAME(@LoginName) +
            N' WITH PASSWORD = N''' + REPLACE(@LoginPassword, N'''', N'''''') +
            N''', CHECK_POLICY = ON, CHECK_EXPIRATION = OFF, DEFAULT_DATABASE = [$(DatabaseName)];';
        EXEC sys.sp_executesql @CreateLoginSql;
    END;
    SET @CreateLoginSql = N'ALTER LOGIN ' + QUOTENAME(@LoginName) +
        N' WITH CHECK_POLICY = ON, CHECK_EXPIRATION = OFF, DEFAULT_DATABASE = [$(DatabaseName)];';
    EXEC sys.sp_executesql @CreateLoginSql;
    FETCH NEXT FROM login_cursor INTO @LoginName, @LoginPassword;
END;
CLOSE login_cursor;
DEALLOCATE login_cursor;
GO

-- Grant the auditor server-level audit access.
IF SUSER_ID(N'SmartBankAuditReader') IS NULL
    CREATE SERVER ROLE SmartBankAuditReader AUTHORIZATION sa;
GRANT VIEW SERVER SECURITY AUDIT TO SmartBankAuditReader;
IF NOT EXISTS
(
    SELECT 1
    FROM sys.server_role_members
    WHERE role_principal_id = SUSER_ID(N'SmartBankAuditReader')
      AND member_principal_id = SUSER_ID(N'sb_auditor_noor')
)
    ALTER SERVER ROLE SmartBankAuditReader ADD MEMBER [sb_auditor_noor];
GO

-- Restrict raw backup-catalog access to the SmartBank DBA.
USE [msdb];
GO
IF USER_ID(N'sb_dba_aisha') IS NULL CREATE USER [sb_dba_aisha] FOR LOGIN [sb_dba_aisha];
IF USER_ID(N'sb_dba_kavitha') IS NULL CREATE USER [sb_dba_kavitha] FOR LOGIN [sb_dba_kavitha];
IF USER_ID(N'sb_manager_daniel') IS NULL CREATE USER [sb_manager_daniel] FOR LOGIN [sb_manager_daniel];
IF USER_ID(N'sb_manager_siti') IS NULL CREATE USER [sb_manager_siti] FOR LOGIN [sb_manager_siti];
IF USER_ID(N'sb_officer_farid') IS NULL CREATE USER [sb_officer_farid] FOR LOGIN [sb_officer_farid];
IF USER_ID(N'sb_officer_priya') IS NULL CREATE USER [sb_officer_priya] FOR LOGIN [sb_officer_priya];
IF USER_ID(N'sb_customer_amelia') IS NULL CREATE USER [sb_customer_amelia] FOR LOGIN [sb_customer_amelia];
IF USER_ID(N'sb_customer_hafiz') IS NULL CREATE USER [sb_customer_hafiz] FOR LOGIN [sb_customer_hafiz];
IF USER_ID(N'sb_auditor_noor') IS NULL CREATE USER [sb_auditor_noor] FOR LOGIN [sb_auditor_noor];
GO

-- Reconnect persistent msdb users after a reset recreates the logins.
ALTER USER [sb_dba_aisha] WITH LOGIN = [sb_dba_aisha];
ALTER USER [sb_dba_kavitha] WITH LOGIN = [sb_dba_kavitha];
ALTER USER [sb_manager_daniel] WITH LOGIN = [sb_manager_daniel];
ALTER USER [sb_manager_siti] WITH LOGIN = [sb_manager_siti];
ALTER USER [sb_officer_farid] WITH LOGIN = [sb_officer_farid];
ALTER USER [sb_officer_priya] WITH LOGIN = [sb_officer_priya];
ALTER USER [sb_customer_amelia] WITH LOGIN = [sb_customer_amelia];
ALTER USER [sb_customer_hafiz] WITH LOGIN = [sb_customer_hafiz];
ALTER USER [sb_auditor_noor] WITH LOGIN = [sb_auditor_noor];
GO

GRANT SELECT ON OBJECT::dbo.backupset TO [sb_dba_aisha];
GRANT SELECT ON OBJECT::dbo.backupmediafamily TO [sb_dba_aisha];
GRANT SELECT ON OBJECT::dbo.backupset TO [sb_dba_kavitha];
GRANT SELECT ON OBJECT::dbo.backupmediafamily TO [sb_dba_kavitha];
DENY SELECT ON OBJECT::dbo.backupset TO [sb_manager_daniel], [sb_manager_siti], [sb_officer_farid], [sb_officer_priya], [sb_customer_amelia], [sb_customer_hafiz], [sb_auditor_noor];
DENY SELECT ON OBJECT::dbo.backupmediafamily TO [sb_manager_daniel], [sb_manager_siti], [sb_officer_farid], [sb_officer_priya], [sb_customer_amelia], [sb_customer_hafiz], [sb_auditor_noor];
GO

USE [$(DatabaseName)];
GO
-- Create database roles and users.
REVOKE CONNECT FROM guest;
GO

IF DATABASE_PRINCIPAL_ID(N'rl_authenticated') IS NULL CREATE ROLE rl_authenticated AUTHORIZATION dbo;
IF DATABASE_PRINCIPAL_ID(N'rl_dba') IS NULL CREATE ROLE rl_dba AUTHORIZATION dbo;
IF DATABASE_PRINCIPAL_ID(N'rl_manager') IS NULL CREATE ROLE rl_manager AUTHORIZATION dbo;
IF DATABASE_PRINCIPAL_ID(N'rl_officer') IS NULL CREATE ROLE rl_officer AUTHORIZATION dbo;
IF DATABASE_PRINCIPAL_ID(N'rl_customer') IS NULL CREATE ROLE rl_customer AUTHORIZATION dbo;
IF DATABASE_PRINCIPAL_ID(N'rl_security_auditor') IS NULL CREATE ROLE rl_security_auditor AUTHORIZATION dbo;
GO

IF USER_ID(N'sb_dba_aisha') IS NULL CREATE USER [sb_dba_aisha] FOR LOGIN [sb_dba_aisha];
IF USER_ID(N'sb_dba_kavitha') IS NULL CREATE USER [sb_dba_kavitha] FOR LOGIN [sb_dba_kavitha];
IF USER_ID(N'sb_manager_daniel') IS NULL CREATE USER [sb_manager_daniel] FOR LOGIN [sb_manager_daniel];
IF USER_ID(N'sb_manager_siti') IS NULL CREATE USER [sb_manager_siti] FOR LOGIN [sb_manager_siti];
IF USER_ID(N'sb_officer_farid') IS NULL CREATE USER [sb_officer_farid] FOR LOGIN [sb_officer_farid];
IF USER_ID(N'sb_officer_priya') IS NULL CREATE USER [sb_officer_priya] FOR LOGIN [sb_officer_priya];
IF USER_ID(N'sb_customer_amelia') IS NULL CREATE USER [sb_customer_amelia] FOR LOGIN [sb_customer_amelia];
IF USER_ID(N'sb_customer_hafiz') IS NULL CREATE USER [sb_customer_hafiz] FOR LOGIN [sb_customer_hafiz];
IF USER_ID(N'sb_auditor_noor') IS NULL CREATE USER [sb_auditor_noor] FOR LOGIN [sb_auditor_noor];
GO

-- Assign users to their roles.
IF NOT EXISTS (SELECT 1 FROM sys.database_role_members WHERE role_principal_id = DATABASE_PRINCIPAL_ID(N'rl_authenticated') AND member_principal_id = USER_ID(N'sb_dba_aisha')) ALTER ROLE rl_authenticated ADD MEMBER [sb_dba_aisha];
IF NOT EXISTS (SELECT 1 FROM sys.database_role_members WHERE role_principal_id = DATABASE_PRINCIPAL_ID(N'rl_dba') AND member_principal_id = USER_ID(N'sb_dba_aisha')) ALTER ROLE rl_dba ADD MEMBER [sb_dba_aisha];
IF NOT EXISTS (SELECT 1 FROM sys.database_role_members WHERE role_principal_id = DATABASE_PRINCIPAL_ID(N'rl_authenticated') AND member_principal_id = USER_ID(N'sb_dba_kavitha')) ALTER ROLE rl_authenticated ADD MEMBER [sb_dba_kavitha];
IF NOT EXISTS (SELECT 1 FROM sys.database_role_members WHERE role_principal_id = DATABASE_PRINCIPAL_ID(N'rl_dba') AND member_principal_id = USER_ID(N'sb_dba_kavitha')) ALTER ROLE rl_dba ADD MEMBER [sb_dba_kavitha];
IF NOT EXISTS (SELECT 1 FROM sys.database_role_members WHERE role_principal_id = DATABASE_PRINCIPAL_ID(N'rl_authenticated') AND member_principal_id = USER_ID(N'sb_manager_daniel')) ALTER ROLE rl_authenticated ADD MEMBER [sb_manager_daniel];
IF NOT EXISTS (SELECT 1 FROM sys.database_role_members WHERE role_principal_id = DATABASE_PRINCIPAL_ID(N'rl_manager') AND member_principal_id = USER_ID(N'sb_manager_daniel')) ALTER ROLE rl_manager ADD MEMBER [sb_manager_daniel];
IF NOT EXISTS (SELECT 1 FROM sys.database_role_members WHERE role_principal_id = DATABASE_PRINCIPAL_ID(N'rl_authenticated') AND member_principal_id = USER_ID(N'sb_manager_siti')) ALTER ROLE rl_authenticated ADD MEMBER [sb_manager_siti];
IF NOT EXISTS (SELECT 1 FROM sys.database_role_members WHERE role_principal_id = DATABASE_PRINCIPAL_ID(N'rl_manager') AND member_principal_id = USER_ID(N'sb_manager_siti')) ALTER ROLE rl_manager ADD MEMBER [sb_manager_siti];
IF NOT EXISTS (SELECT 1 FROM sys.database_role_members WHERE role_principal_id = DATABASE_PRINCIPAL_ID(N'rl_authenticated') AND member_principal_id = USER_ID(N'sb_officer_farid')) ALTER ROLE rl_authenticated ADD MEMBER [sb_officer_farid];
IF NOT EXISTS (SELECT 1 FROM sys.database_role_members WHERE role_principal_id = DATABASE_PRINCIPAL_ID(N'rl_officer') AND member_principal_id = USER_ID(N'sb_officer_farid')) ALTER ROLE rl_officer ADD MEMBER [sb_officer_farid];
IF NOT EXISTS (SELECT 1 FROM sys.database_role_members WHERE role_principal_id = DATABASE_PRINCIPAL_ID(N'rl_authenticated') AND member_principal_id = USER_ID(N'sb_officer_priya')) ALTER ROLE rl_authenticated ADD MEMBER [sb_officer_priya];
IF NOT EXISTS (SELECT 1 FROM sys.database_role_members WHERE role_principal_id = DATABASE_PRINCIPAL_ID(N'rl_officer') AND member_principal_id = USER_ID(N'sb_officer_priya')) ALTER ROLE rl_officer ADD MEMBER [sb_officer_priya];
IF NOT EXISTS (SELECT 1 FROM sys.database_role_members WHERE role_principal_id = DATABASE_PRINCIPAL_ID(N'rl_authenticated') AND member_principal_id = USER_ID(N'sb_customer_amelia')) ALTER ROLE rl_authenticated ADD MEMBER [sb_customer_amelia];
IF NOT EXISTS (SELECT 1 FROM sys.database_role_members WHERE role_principal_id = DATABASE_PRINCIPAL_ID(N'rl_customer') AND member_principal_id = USER_ID(N'sb_customer_amelia')) ALTER ROLE rl_customer ADD MEMBER [sb_customer_amelia];
IF NOT EXISTS (SELECT 1 FROM sys.database_role_members WHERE role_principal_id = DATABASE_PRINCIPAL_ID(N'rl_authenticated') AND member_principal_id = USER_ID(N'sb_customer_hafiz')) ALTER ROLE rl_authenticated ADD MEMBER [sb_customer_hafiz];
IF NOT EXISTS (SELECT 1 FROM sys.database_role_members WHERE role_principal_id = DATABASE_PRINCIPAL_ID(N'rl_customer') AND member_principal_id = USER_ID(N'sb_customer_hafiz')) ALTER ROLE rl_customer ADD MEMBER [sb_customer_hafiz];
IF NOT EXISTS (SELECT 1 FROM sys.database_role_members WHERE role_principal_id = DATABASE_PRINCIPAL_ID(N'rl_authenticated') AND member_principal_id = USER_ID(N'sb_auditor_noor')) ALTER ROLE rl_authenticated ADD MEMBER [sb_auditor_noor];
IF NOT EXISTS (SELECT 1 FROM sys.database_role_members WHERE role_principal_id = DATABASE_PRINCIPAL_ID(N'rl_security_auditor') AND member_principal_id = USER_ID(N'sb_auditor_noor')) ALTER ROLE rl_security_auditor ADD MEMBER [sb_auditor_noor];
GO

-- Remove default access to protected schemas.
DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::core TO public;
DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::sec TO public;
REVOKE SELECT, INSERT, UPDATE, DELETE ON SCHEMA::audit FROM public;
REVOKE SELECT, INSERT, UPDATE, DELETE ON SCHEMA::ops FROM public;
DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::history TO public;
DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::demo TO public;
DENY EXECUTE ON SCHEMA::core TO public;
DENY EXECUTE ON SCHEMA::sec TO public;
REVOKE EXECUTE ON SCHEMA::audit FROM public;
REVOKE EXECUTE ON SCHEMA::ops FROM public;
GO

-- Grant the common directory view.
GRANT SELECT ON OBJECT::api.vw_StaffDirectory TO rl_authenticated;
-- Customers keep the ID-free directory instead of the internal StaffID view.
DENY SELECT ON OBJECT::api.vw_StaffDirectory TO rl_customer;
GO

-- Grant DBA permissions.
GRANT EXECUTE ON OBJECT::api.usp_GetMyStaffProfile TO rl_dba;
GRANT EXECUTE ON OBJECT::api.usp_UpdateOwnStaffProfile TO rl_dba;
GRANT CREATE TABLE TO rl_dba;
GRANT ALTER ON SCHEMA::core TO rl_dba;
GRANT VIEW DEFINITION ON SCHEMA::core TO rl_dba;
DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::core TO rl_dba;
GO

-- Grant manager permissions.
GRANT EXECUTE ON OBJECT::api.usp_GetMyStaffProfile TO rl_manager;
GRANT EXECUTE ON OBJECT::api.usp_ManagerGetStaffProfiles TO rl_manager;
GRANT EXECUTE ON OBJECT::api.usp_UpdateOwnStaffProfile TO rl_manager;
GRANT EXECUTE ON OBJECT::api.usp_ManagerAddOfficer TO rl_manager;
GRANT EXECUTE ON OBJECT::api.usp_ManagerUpdateOfficer TO rl_manager;
GRANT EXECUTE ON OBJECT::api.usp_ManagerDeactivateOfficer TO rl_manager;
GRANT SELECT ON OBJECT::api.vw_CustomerAccountSummary TO rl_manager;
GRANT SELECT ON OBJECT::api.vw_MyTransactions TO rl_manager;
GO

-- Grant officer permissions.
GRANT EXECUTE ON OBJECT::api.usp_GetMyStaffProfile TO rl_officer;
GRANT EXECUTE ON OBJECT::api.usp_UpdateOwnStaffProfile TO rl_officer;
GRANT EXECUTE ON OBJECT::api.usp_OfficerCreateCustomer TO rl_officer;
GRANT EXECUTE ON OBJECT::api.usp_OfficerOpenAccount TO rl_officer;
GRANT EXECUTE ON OBJECT::api.usp_OfficerSetAccountStatus TO rl_officer;
GRANT SELECT ON OBJECT::api.vw_CustomerAccountSummary TO rl_officer;
GRANT SELECT ON OBJECT::api.vw_MyTransactions TO rl_officer;
GO

-- Grant customer permissions.
GRANT EXECUTE ON OBJECT::api.usp_GetMyCustomerProfile TO rl_customer;
GRANT EXECUTE ON OBJECT::api.usp_SetTransactionPin TO rl_customer;
GRANT EXECUTE ON OBJECT::api.usp_PerformTransaction TO rl_customer;
GRANT EXECUTE ON OBJECT::api.usp_CustomerDepositToAccount TO rl_customer;
GRANT SELECT ON OBJECT::api.vw_MyAccounts TO rl_customer;
GRANT SELECT ON OBJECT::api.vw_MyTransactions TO rl_customer;
GRANT SELECT ON OBJECT::api.vw_StaffDirectoryPublic TO rl_customer;
GO

-- Grant security-auditor permissions.
GRANT SELECT ON OBJECT::audit.vw_DmlAudit TO rl_security_auditor;
GRANT SELECT ON OBJECT::audit.vw_AuditMatrix TO rl_security_auditor;
GRANT SELECT ON OBJECT::audit.ApplicationEvent TO rl_security_auditor;
GRANT EXECUTE ON OBJECT::audit.usp_ReadNativeAudit TO rl_security_auditor;
GRANT EXECUTE ON OBJECT::api.usp_VerifyLedgerChain TO rl_security_auditor;
GRANT EXECUTE ON OBJECT::api.usp_VerifyAccountBalances TO rl_security_auditor;
GRANT VIEW DEFINITION TO rl_security_auditor;
GO

-- Provide role and permission reports for the auditor.
CREATE OR ALTER VIEW api.vw_UserRoleMembership
AS
    SELECT member.name AS DatabaseUser,
           role.name AS DatabaseRole,
           principalMap.UserType,
           principalMap.StaffID,
           principalMap.CustomerID,
           principalMap.IsActive
    FROM sys.database_role_members AS membership
    INNER JOIN sys.database_principals AS role ON role.principal_id = membership.role_principal_id
    INNER JOIN sys.database_principals AS member ON member.principal_id = membership.member_principal_id
    LEFT JOIN sec.PrincipalMap AS principalMap ON principalMap.DatabaseUserName = member.name
    WHERE role.name LIKE N'rl[_]%';
GO

CREATE OR ALTER VIEW api.vw_RolePermissionMatrix
AS
    SELECT principal.name AS PrincipalName,
           principal.type_desc AS PrincipalType,
           permission.state_desc AS PermissionState,
           permission.permission_name AS PermissionName,
           permission.class_desc AS SecurableClass,
           CASE permission.class
               WHEN 0 THEN DB_NAME()
               WHEN 1 THEN QUOTENAME(OBJECT_SCHEMA_NAME(permission.major_id)) + N'.' + QUOTENAME(OBJECT_NAME(permission.major_id))
               WHEN 3 THEN QUOTENAME(SCHEMA_NAME(permission.major_id))
               ELSE CONVERT(nvarchar(128), permission.major_id)
           END AS SecurableName
    FROM sys.database_permissions AS permission
    INNER JOIN sys.database_principals AS principal ON principal.principal_id = permission.grantee_principal_id
    WHERE principal.name LIKE N'rl[_]%' OR principal.name = N'public';
GO

GRANT SELECT ON OBJECT::api.vw_UserRoleMembership TO rl_security_auditor;
GRANT SELECT ON OBJECT::api.vw_RolePermissionMatrix TO rl_security_auditor;
GO
