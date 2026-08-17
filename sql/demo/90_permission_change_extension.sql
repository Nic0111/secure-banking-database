/*
ASSIGNMENT SECTION:
Section 2 - Integrity (extension evidence)

REQUIREMENT:
Demonstrate that user, role-membership and permission changes are controlled,
reversible and recorded by native audit.

RUN AS:
sa after the core assignment demonstrations.

EXPECTED RESULT:
A temporary contained user is created, added to rl_authenticated, granted and
revoked directory access, removed from the role and dropped. Native audit records
the lifecycle without exposing statement text on screen.

PASS CONDITION:
The temporary user no longer exists and recent native audit metadata contains the
principal/role/permission change events.

DATABASE CHANGES:
Reversible creation, membership, grant, revoke and deletion of
sb_demo_temporary_user. Audit evidence is retained.
*/
USE [SmartBankDB];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF IS_SRVROLEMEMBER(N'sysadmin') <> 1
    THROW 51900, 'Run the permission-change extension as sa or another sysadmin.', 1;

DECLARE @DemoStart datetime2(3) = DATEADD(SECOND, -2, SYSUTCDATETIME());

-- Clean only a leftover user from an interrupted previous run.
IF USER_ID(N'sb_demo_temporary_user') IS NOT NULL
BEGIN
    REVOKE SELECT ON OBJECT::api.vw_StaffDirectory FROM [sb_demo_temporary_user];
    IF EXISTS
    (
        SELECT 1 FROM sys.database_role_members
        WHERE role_principal_id = DATABASE_PRINCIPAL_ID(N'rl_authenticated')
          AND member_principal_id = USER_ID(N'sb_demo_temporary_user')
    )
        ALTER ROLE rl_authenticated DROP MEMBER [sb_demo_temporary_user];
    DROP USER [sb_demo_temporary_user];
END;

CREATE USER [sb_demo_temporary_user] WITHOUT LOGIN;
ALTER ROLE rl_authenticated ADD MEMBER [sb_demo_temporary_user];
GRANT SELECT ON OBJECT::api.vw_StaffDirectory TO [sb_demo_temporary_user];

SELECT N'Permission granted' AS Stage,
       principalInfo.name AS DatabaseUser,
       permissionInfo.state_desc AS PermissionState,
       permissionInfo.permission_name AS PermissionName,
       OBJECT_SCHEMA_NAME(permissionInfo.major_id) + N'.' + OBJECT_NAME(permissionInfo.major_id) AS Securable
FROM sys.database_permissions AS permissionInfo
INNER JOIN sys.database_principals AS principalInfo
    ON principalInfo.principal_id = permissionInfo.grantee_principal_id
WHERE principalInfo.name = N'sb_demo_temporary_user';

REVOKE SELECT ON OBJECT::api.vw_StaffDirectory FROM [sb_demo_temporary_user];
ALTER ROLE rl_authenticated DROP MEMBER [sb_demo_temporary_user];
DROP USER [sb_demo_temporary_user];

IF USER_ID(N'sb_demo_temporary_user') IS NOT NULL
    THROW 51901, 'FAIL - temporary permission-demo user was not removed.', 1;

WAITFOR DELAY '00:00:02';
CREATE TABLE #NativeAudit
(
    EventTimeUtc datetime2(7), ActionID varchar(4), Succeeded bit, SessionID int,
    ServerPrincipal sysname NULL, DatabasePrincipal sysname NULL, DatabaseName sysname NULL,
    SchemaName sysname NULL, ObjectName sysname NULL, StatementText nvarchar(max) NULL,
    ApplicationName nvarchar(256) NULL, ClientAddress varchar(128) NULL,
    AdditionalInformation nvarchar(max) NULL, AuditFile nvarchar(4000) NULL
);
INSERT #NativeAudit
EXEC audit.usp_ReadNativeAudit @StartTime = @DemoStart, @EndTime = NULL, @OnlyFailures = 0;

SELECT EventTimeUtc, ActionID, Succeeded, ServerPrincipal, DatabasePrincipal,
       DatabaseName, SchemaName, ObjectName, ApplicationName, ClientAddress
FROM #NativeAudit
WHERE DatabaseName = DB_NAME() AND ServerPrincipal = ORIGINAL_LOGIN()
ORDER BY EventTimeUtc;

IF (SELECT COUNT(*) FROM #NativeAudit
    WHERE DatabaseName = DB_NAME() AND ServerPrincipal = ORIGINAL_LOGIN()) < 4
    THROW 51902, 'FAIL - permission lifecycle has not yet appeared in native audit.', 1;

SELECT N'PASS' AS Result,
       N'The reversible permission lifecycle completed and native audit evidence is present.' AS Evidence;
GO
