/*
ASSIGNMENT SECTION:
Section 1 - Confidentiality

REQUIREMENT:
1. All users must be authenticated.

RUN AS:
First run as sa for the inventory. Then open a fresh SQL-authenticated connection
for every required login and rerun this file. Also attempt one deliberately wrong
password at the SSMS connection dialog; do not type or display that password here.

EXPECTED RESULT:
sa sees eight enabled logins, mapped database users, active business identities and
correct role memberships. Each fresh connection reports its own ORIGINAL_LOGIN(),
database user and authenticated role.

PASS CONDITION:
All eight correct credentials establish separate sessions, the wrong credential is
rejected, and the failed login later appears in SQL Server Audit.

DATABASE CHANGES:
None. This script is read-only.
*/
USE [SmartBankDB];
GO
SET NOCOUNT ON;
GO

IF IS_SRVROLEMEMBER(N'sysadmin') = 1
BEGIN
    DECLARE @Expected table (LoginName sysname PRIMARY KEY, ExpectedRole sysname NOT NULL);
    INSERT @Expected
    VALUES (N'sb_dba_aisha', N'rl_dba'),
           (N'sb_manager_daniel', N'rl_manager'),
           (N'sb_manager_siti', N'rl_manager'),
           (N'sb_officer_farid', N'rl_officer'),
           (N'sb_officer_priya', N'rl_officer'),
           (N'sb_customer_amelia', N'rl_customer'),
           (N'sb_customer_hafiz', N'rl_customer'),
           (N'sb_auditor_noor', N'rl_security_auditor');

    SELECT expected.LoginName,
           loginInfo.type_desc AS ServerPrincipalType,
           loginInfo.is_disabled AS LoginDisabled,
           CONVERT(bit, LOGINPROPERTY(expected.LoginName, 'IsLocked')) AS LoginLocked,
           databaseUser.name AS DatabaseUser,
           principalMap.UserType,
           principalMap.StaffID,
           principalMap.CustomerID,
           expected.ExpectedRole,
           CONVERT(bit, CASE WHEN membership.member_principal_id IS NULL THEN 0 ELSE 1 END) AS HasExpectedRole,
           CONVERT(bit, CASE WHEN authenticatedMembership.member_principal_id IS NULL THEN 0 ELSE 1 END) AS HasAuthenticatedRole
    FROM @Expected AS expected
    LEFT JOIN master.sys.server_principals AS loginInfo ON loginInfo.name = expected.LoginName
    LEFT JOIN sys.database_principals AS databaseUser ON databaseUser.name = expected.LoginName
    LEFT JOIN sec.PrincipalMap AS principalMap
        ON principalMap.LoginName = expected.LoginName AND principalMap.IsActive = 1
    LEFT JOIN sys.database_role_members AS membership
        ON membership.role_principal_id = DATABASE_PRINCIPAL_ID(expected.ExpectedRole)
       AND membership.member_principal_id = databaseUser.principal_id
    LEFT JOIN sys.database_role_members AS authenticatedMembership
        ON authenticatedMembership.role_principal_id = DATABASE_PRINCIPAL_ID(N'rl_authenticated')
       AND authenticatedMembership.member_principal_id = databaseUser.principal_id
    ORDER BY expected.LoginName;

    IF EXISTS
    (
        SELECT 1
        FROM @Expected AS expected
        LEFT JOIN master.sys.server_principals AS loginInfo ON loginInfo.name = expected.LoginName
        LEFT JOIN sys.database_principals AS databaseUser ON databaseUser.name = expected.LoginName
        LEFT JOIN sec.PrincipalMap AS principalMap
            ON principalMap.LoginName = expected.LoginName AND principalMap.IsActive = 1
        WHERE loginInfo.principal_id IS NULL OR loginInfo.is_disabled = 1
           OR databaseUser.principal_id IS NULL OR principalMap.LoginName IS NULL
           OR NOT EXISTS
              (
                  SELECT 1 FROM sys.database_role_members
                  WHERE role_principal_id = DATABASE_PRINCIPAL_ID(expected.ExpectedRole)
                    AND member_principal_id = databaseUser.principal_id
              )
           OR NOT EXISTS
              (
                  SELECT 1 FROM sys.database_role_members
                  WHERE role_principal_id = DATABASE_PRINCIPAL_ID(N'rl_authenticated')
                    AND member_principal_id = databaseUser.principal_id
              )
    )
        THROW 51100, 'FAIL - at least one required authentication chain is incomplete.', 1;

    SELECT N'PASS' AS Result,
           N'All required server logins, database users, active identity mappings and roles exist.' AS Evidence;
END
ELSE
BEGIN
    DECLARE @Login sysname = ORIGINAL_LOGIN();
    DECLARE @ExpectedRole sysname =
        CASE
            WHEN @Login = N'sb_dba_aisha' THEN N'rl_dba'
            WHEN @Login IN (N'sb_manager_daniel', N'sb_manager_siti') THEN N'rl_manager'
            WHEN @Login IN (N'sb_officer_farid', N'sb_officer_priya') THEN N'rl_officer'
            WHEN @Login IN (N'sb_customer_amelia', N'sb_customer_hafiz') THEN N'rl_customer'
            WHEN @Login = N'sb_auditor_noor' THEN N'rl_security_auditor'
        END;

    SELECT SUSER_SNAME() AS SessionLogin,
           ORIGINAL_LOGIN() AS AuthenticatedLogin,
           USER_NAME() AS DatabaseUser,
           DB_NAME() AS DatabaseName,
           @ExpectedRole AS ExpectedBusinessRole,
           IS_ROLEMEMBER(N'rl_authenticated') AS IsAuthenticatedMember,
           IS_ROLEMEMBER(@ExpectedRole) AS IsExpectedRoleMember,
           CONNECTIONPROPERTY('auth_scheme') AS AuthenticationScheme,
           SYSUTCDATETIME() AS CheckedAtUtc;

    IF @ExpectedRole IS NULL OR USER_NAME() <> @Login
       OR IS_ROLEMEMBER(N'rl_authenticated') <> 1 OR IS_ROLEMEMBER(@ExpectedRole) <> 1
        THROW 51101, 'FAIL - this session is not a correctly mapped SmartBank demonstration login.', 1;

    SELECT N'PASS' AS Result,
           N'This is a real authenticated server session with the expected database role.' AS Evidence;
END;
GO
