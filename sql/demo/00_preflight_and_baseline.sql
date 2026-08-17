/*
ASSIGNMENT SECTION:
Sections 1-3 - Demonstration preflight

REQUIREMENT:
Confirm that the security implementation is deployed and the demonstration starts
from the same golden dataset.

RUN AS:
sa, before opening any role-specific demonstration connection.

EXPECTED RESULT:
Every check is PASS. The golden row counts are 7 staff, 12 customers,
18 accounts, 44 ledger rows and 10 recovery-target rows.

PASS CONDITION:
The final summary is PASS and no preflight check is reported as FAIL.

DATABASE CHANGES:
None. This script is read-only.
*/
USE [SmartBankDB];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF IS_SRVROLEMEMBER(N'sysadmin') <> 1
    THROW 51000, 'Run the preflight as sa or another sysadmin login.', 1;

DECLARE @Checks table
(
    CheckArea nvarchar(60) NOT NULL,
    CheckName nvarchar(160) NOT NULL,
    ExpectedValue nvarchar(200) NOT NULL,
    ActualValue nvarchar(200) NOT NULL,
    Passed bit NOT NULL
);

INSERT @Checks
VALUES
    (N'Environment', N'Database is online', N'ONLINE',
     COALESCE((SELECT state_desc FROM sys.databases WHERE name = DB_NAME()), N'MISSING'),
     IIF((SELECT state_desc FROM sys.databases WHERE name = DB_NAME()) = N'ONLINE', 1, 0)),
    (N'Environment', N'FULL recovery model', N'FULL',
     COALESCE((SELECT recovery_model_desc FROM sys.databases WHERE name = DB_NAME()), N'MISSING'),
     IIF((SELECT recovery_model_desc FROM sys.databases WHERE name = DB_NAME()) = N'FULL', 1, 0)),
    (N'Environment', N'Analytics database exists', N'1', CONVERT(nvarchar(20), IIF(DB_ID(N'SmartBankAnalyticsDB') IS NULL, 0, 1)),
     IIF(DB_ID(N'SmartBankAnalyticsDB') IS NULL, 0, 1));

DECLARE @RequiredObjects table (ObjectName nvarchar(300) PRIMARY KEY);
INSERT @RequiredObjects (ObjectName)
VALUES
    (N'core.Staff'), (N'core.StaffEmployment'), (N'core.Customer'),
    (N'core.Account'), (N'core.TransactionRecord'), (N'sec.PrincipalMap'),
    (N'audit.DmlAudit'), (N'audit.ApplicationEvent'), (N'ops.BackupRun'),
    (N'ops.RecoveryMarker'), (N'demo.RecoveryTarget'),
    (N'api.vw_StaffDirectory'), (N'api.vw_CustomerAccountSummary'),
    (N'api.vw_MyAccounts'), (N'api.vw_MyTransactions'),
    (N'api.usp_GetMyStaffProfile'), (N'api.usp_ManagerGetStaffProfiles'),
    (N'api.usp_GetMyCustomerProfile'), (N'api.usp_UpdateOwnStaffProfile'),
    (N'api.usp_ManagerUpdateOfficer'), (N'api.usp_OfficerOpenAccount'),
    (N'api.usp_OfficerSetAccountStatus'), (N'api.usp_PerformTransaction'),
    (N'audit.usp_ReadNativeAudit'), (N'ops.usp_BackupHealth');

DECLARE @RequiredObjectCount int = (SELECT COUNT(*) FROM @RequiredObjects);
DECLARE @PresentObjectCount int =
(
    SELECT COUNT(*) FROM @RequiredObjects WHERE OBJECT_ID(ObjectName) IS NOT NULL
);
INSERT @Checks
VALUES (N'Implementation', N'Required demonstration objects', CONVERT(nvarchar(20), @RequiredObjectCount),
        CONVERT(nvarchar(20), @PresentObjectCount), IIF(@PresentObjectCount = @RequiredObjectCount, 1, 0));

DECLARE @RequiredLogins table (LoginName sysname PRIMARY KEY);
INSERT @RequiredLogins
VALUES (N'sb_dba_aisha'), (N'sb_manager_daniel'), (N'sb_manager_siti'),
       (N'sb_officer_farid'), (N'sb_officer_priya'),
       (N'sb_customer_amelia'), (N'sb_customer_hafiz'), (N'sb_auditor_noor');

DECLARE @EnabledLoginCount int =
(
    SELECT COUNT(*)
    FROM @RequiredLogins AS requiredLogin
    INNER JOIN master.sys.server_principals AS loginInfo
        ON loginInfo.name = requiredLogin.LoginName
    WHERE loginInfo.type_desc = N'SQL_LOGIN' AND loginInfo.is_disabled = 0
);
DECLARE @MappedIdentityCount int =
(
    SELECT COUNT(*)
    FROM @RequiredLogins AS requiredLogin
    INNER JOIN sys.database_principals AS databaseUser
        ON databaseUser.name = requiredLogin.LoginName
    INNER JOIN sec.PrincipalMap AS principalMap
        ON principalMap.LoginName = requiredLogin.LoginName
       AND principalMap.DatabaseUserName = databaseUser.name
       AND principalMap.IsActive = 1
);
INSERT @Checks
VALUES
    (N'Authentication', N'Enabled SQL logins', N'8', CONVERT(nvarchar(20), @EnabledLoginCount), IIF(@EnabledLoginCount = 8, 1, 0)),
    (N'Authentication', N'Database users with active business mapping', N'8', CONVERT(nvarchar(20), @MappedIdentityCount), IIF(@MappedIdentityCount = 8, 1, 0));

DECLARE @RoleMembershipCount int =
(
    SELECT COUNT(*)
    FROM sys.database_role_members AS membership
    INNER JOIN sys.database_principals AS roleInfo ON roleInfo.principal_id = membership.role_principal_id
    INNER JOIN sys.database_principals AS memberInfo ON memberInfo.principal_id = membership.member_principal_id
    WHERE roleInfo.name IN (N'rl_dba', N'rl_manager', N'rl_officer', N'rl_customer', N'rl_security_auditor')
      AND memberInfo.name IN (SELECT LoginName FROM @RequiredLogins)
);
INSERT @Checks
VALUES (N'Authorization', N'Business-role memberships', N'8', CONVERT(nvarchar(20), @RoleMembershipCount),
        IIF(@RoleMembershipCount = 8, 1, 0));

DECLARE @EnabledPolicyCount int =
(
    SELECT COUNT(*) FROM sys.security_policies
    WHERE name IN (N'StaffEmploymentSecurityPolicy', N'CustomerDataSecurityPolicy') AND is_enabled = 1
);
INSERT @Checks
VALUES (N'Confidentiality', N'Enabled row-level security policies', N'2', CONVERT(nvarchar(20), @EnabledPolicyCount),
        IIF(@EnabledPolicyCount = 2, 1, 0));

INSERT @Checks
SELECT N'Golden dataset', N'Staff rows', N'7', CONVERT(nvarchar(20), COUNT_BIG(*)), IIF(COUNT_BIG(*) = 7, 1, 0) FROM core.Staff
UNION ALL SELECT N'Golden dataset', N'Customer rows', N'12', CONVERT(nvarchar(20), COUNT_BIG(*)), IIF(COUNT_BIG(*) = 12, 1, 0) FROM core.Customer
UNION ALL SELECT N'Golden dataset', N'Account rows', N'18', CONVERT(nvarchar(20), COUNT_BIG(*)), IIF(COUNT_BIG(*) = 18, 1, 0) FROM core.Account
UNION ALL SELECT N'Golden dataset', N'Ledger rows', N'44', CONVERT(nvarchar(20), COUNT_BIG(*)), IIF(COUNT_BIG(*) = 44, 1, 0) FROM core.TransactionRecord
UNION ALL SELECT N'Golden dataset', N'Recovery-target rows', N'10', CONVERT(nvarchar(20), COUNT_BIG(*)), IIF(COUNT_BIG(*) = 10, 1, 0) FROM demo.RecoveryTarget;

DECLARE @AuditState int =
(
    SELECT COUNT(*) FROM master.sys.server_audits
    WHERE name = N'SmartBank_ServerAudit' AND is_state_enabled = 1
);
DECLARE @DatabaseAuditState int =
(
    SELECT COUNT(*) FROM sys.database_audit_specifications
    WHERE name = N'SmartBank_DatabaseAuditSpecification' AND is_state_enabled = 1
);
INSERT @Checks
VALUES
    (N'Audit', N'Server audit enabled', N'1', CONVERT(nvarchar(20), @AuditState), IIF(@AuditState = 1, 1, 0)),
    (N'Audit', N'Database audit specification enabled', N'1', CONVERT(nvarchar(20), @DatabaseAuditState), IIF(@DatabaseAuditState = 1, 1, 0));

DECLARE @EnabledJobCount int =
(
    SELECT COUNT(*) FROM msdb.dbo.sysjobs
    WHERE name IN
    (
        N'SmartBank - Full Backup', N'SmartBank - Differential Backup',
        N'SmartBank - Log Backup', N'SmartBank - Backup Retention'
    ) AND enabled = 1
);
INSERT @Checks
VALUES (N'Availability', N'Enabled backup and retention jobs', N'4', CONVERT(nvarchar(20), @EnabledJobCount),
        IIF(@EnabledJobCount = 4, 1, 0));

SELECT CheckArea, CheckName, ExpectedValue, ActualValue,
       IIF(Passed = 1, N'PASS', N'FAIL') AS Result
FROM @Checks
ORDER BY Passed, CheckArea, CheckName;

IF EXISTS (SELECT 1 FROM @Checks WHERE Passed = 0)
    THROW 51001, 'Preflight failed. Restore the golden baseline or redeploy before continuing.', 1;

SELECT N'PASS' AS PreflightResult,
       N'Implementation and golden dataset are ready for the assignment demonstration.' AS Evidence,
       SYSUTCDATETIME() AS CheckedAtUtc;
GO
