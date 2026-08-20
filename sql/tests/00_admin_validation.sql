:setvar DatabaseName "SmartBankDB"
:setvar AnalyticsDatabaseName "SmartBankAnalyticsDB"

USE [$(DatabaseName)];
GO
SET NOCOUNT ON;
GO

IF (SELECT recovery_model_desc FROM sys.databases WHERE name = DB_NAME()) <> 'FULL'
    THROW 51000, 'FAIL: SmartBankDB is not using FULL recovery.', 1;
IF NOT EXISTS (SELECT 1 FROM sys.dm_database_encryption_keys WHERE database_id = DB_ID() AND encryption_state = 3 AND key_length = 256)
    THROW 51001, 'FAIL: SmartBankDB TDE is not fully encrypted with AES-256.', 1;
IF (SELECT COUNT(*) FROM core.Staff) < 7 THROW 51002, 'FAIL: insufficient staff seed data.', 1;
IF (SELECT COUNT(*) FROM core.Customer) < 12 THROW 51003, 'FAIL: insufficient customer seed data.', 1;
IF (SELECT COUNT(*) FROM core.Account) < 18 THROW 51004, 'FAIL: insufficient account seed data.', 1;
IF (SELECT COUNT(*) FROM core.TransactionRecord) < 40 THROW 51005, 'FAIL: insufficient transaction seed data.', 1;
IF (SELECT COUNT(*) FROM sys.security_policies WHERE is_enabled = 1) < 2 THROW 51006, 'FAIL: RLS policies are not enabled.', 1;
IF (SELECT COUNT(*) FROM sys.masked_columns WHERE is_masked = 1) < 2 THROW 51007, 'FAIL: DDM columns are missing.', 1;
IF NOT EXISTS (SELECT 1 FROM sys.database_audit_specifications WHERE name = N'SmartBank_DatabaseAuditSpecification' AND is_state_enabled = 1)
    THROW 51008, 'FAIL: database audit specification is not enabled.', 1;
IF NOT EXISTS (SELECT 1 FROM msdb.dbo.backupset WHERE database_name = DB_NAME() AND type = 'D' AND key_algorithm = 'AES_256' AND has_backup_checksums = 1)
    THROW 51009, 'FAIL: no encrypted, checksummed full backup is registered.', 1;
IF (SELECT COUNT(*) FROM sys.sql_logins WHERE name IN
    (N'sb_dba_aisha', N'sb_manager_daniel', N'sb_manager_siti', N'sb_officer_farid',
     N'sb_officer_priya', N'sb_customer_amelia', N'sb_customer_hafiz', N'sb_auditor_noor')) <> 8
    THROW 51011, 'FAIL: one or more demonstration SQL logins are missing.', 1;
IF EXISTS
(
    SELECT 1
    FROM sys.sql_logins
    WHERE name IN
        (N'sb_dba_aisha', N'sb_manager_daniel', N'sb_manager_siti', N'sb_officer_farid',
         N'sb_officer_priya', N'sb_customer_amelia', N'sb_customer_hafiz', N'sb_auditor_noor')
      AND is_policy_checked = 0
)
    THROW 51012, 'FAIL: password policy is disabled for a demonstration login.', 1;
IF NOT EXISTS
(
    SELECT 1
    FROM sec.PrincipalMap
    WHERE LoginName = N'sb_manager_siti'
      AND DatabaseUserName = N'sb_manager_siti'
      AND UserType = 'MANAGER'
      AND StaffID = 'S00002'
      AND IsActive = 1
)
    THROW 51013, 'FAIL: the second manager identity mapping is missing or inactive.', 1;
IF NOT EXISTS
(
    SELECT 1
    FROM sys.database_role_members
    WHERE role_principal_id = DATABASE_PRINCIPAL_ID(N'rl_manager')
      AND member_principal_id = USER_ID(N'sb_manager_siti')
)
    THROW 51014, 'FAIL: the second manager is not assigned to rl_manager.', 1;
IF
(
    SELECT COUNT(*)
    FROM msdb.sys.database_permissions AS permission
    INNER JOIN msdb.sys.database_principals AS principal ON principal.principal_id = permission.grantee_principal_id
    WHERE principal.name IN
        (N'sb_manager_daniel', N'sb_manager_siti', N'sb_officer_farid', N'sb_officer_priya',
         N'sb_customer_amelia', N'sb_customer_hafiz', N'sb_auditor_noor')
      AND permission.state = N'D'
      AND permission.permission_name = N'SELECT'
      AND permission.major_id = OBJECT_ID(N'msdb.dbo.backupset')
) <> 7
    THROW 51015, 'FAIL: every non-DBA SmartBank login must be denied direct backupset access.', 1;
IF NOT EXISTS
(
    SELECT 1
    FROM msdb.sys.database_permissions AS permission
    INNER JOIN msdb.sys.database_principals AS principal ON principal.principal_id = permission.grantee_principal_id
    WHERE principal.name = N'sb_dba_aisha'
      AND permission.state = N'G'
      AND permission.permission_name = N'SELECT'
      AND permission.major_id = OBJECT_ID(N'msdb.dbo.backupset')
)
    THROW 51016, 'FAIL: the DBA is missing direct backupset access.', 1;

SELECT N'PASS - baseline deployment' AS Result,
       (SELECT COUNT(*) FROM core.Staff) AS StaffRows,
       (SELECT COUNT(*) FROM core.Customer) AS CustomerRows,
       (SELECT COUNT(*) FROM core.Account) AS AccountRows,
       (SELECT COUNT(*) FROM core.TransactionRecord) AS TransactionRows;

SELECT name AS LoginName, is_policy_checked, is_expiration_checked, default_database_name
FROM sys.sql_logins
WHERE name LIKE N'sb[_]%'
ORDER BY name;

SELECT databaseName = DB_NAME(database_id), encryption_state_desc, key_algorithm, key_length, percent_complete
FROM sys.dm_database_encryption_keys WHERE database_id = DB_ID();

SELECT policy.name AS PolicyName, policy.is_enabled,
       OBJECT_SCHEMA_NAME(predicate.target_object_id) AS TargetSchema,
       OBJECT_NAME(predicate.target_object_id) AS TargetTable,
       predicate.predicate_definition
FROM sys.security_policies AS policy
INNER JOIN sys.security_predicates AS predicate ON predicate.object_id = policy.object_id
ORDER BY PolicyName, TargetTable;

SELECT tableName = OBJECT_SCHEMA_NAME(mask.object_id) + N'.' + OBJECT_NAME(mask.object_id),
       columnName = mask.name, mask.masking_function
FROM sys.masked_columns AS mask WHERE mask.is_masked = 1;

SELECT CustomerID, CustomerName, Email,
       ICNumberCipher, PhoneCipher, AddressCipher
FROM core.Customer ORDER BY CustomerID;

EXEC api.usp_VerifyLedgerChain;
EXEC api.usp_VerifyAccountBalances;
EXEC ops.usp_BackupHealth @Days = 3;

SELECT * FROM api.vw_UserRoleMembership ORDER BY DatabaseRole, DatabaseUser;
SELECT * FROM api.vw_RolePermissionMatrix ORDER BY PrincipalName, SecurableName, PermissionName;
SELECT * FROM audit.vw_AuditMatrix;

USE [$(AnalyticsDatabaseName)];
GO
IF NOT EXISTS (SELECT 1 FROM sys.dm_database_encryption_keys WHERE database_id = DB_ID() AND encryption_state = 3)
    THROW 51010, 'FAIL: analytics database TDE is not enabled.', 1;
EXEC dbo.usp_StaticMaskingQualityCheck;
SELECT TOP (5) * FROM dbo.CustomerAnon ORDER BY CustomerToken;
SELECT TOP (5) * FROM dbo.AccountAnon ORDER BY AccountToken;
SELECT TOP (5) * FROM dbo.TransactionAnon ORDER BY TransactionToken;
GO

USE [msdb];
GO
SELECT job.name, job.enabled, schedule.name AS ScheduleName,
       schedule.freq_type, schedule.freq_subday_type, schedule.freq_subday_interval,
       schedule.active_start_time
FROM dbo.sysjobs AS job
LEFT JOIN dbo.sysjobschedules AS jobSchedule ON jobSchedule.job_id = job.job_id
LEFT JOIN dbo.sysschedules AS schedule ON schedule.schedule_id = jobSchedule.schedule_id
WHERE job.name LIKE N'SmartBank - %'
ORDER BY job.name;
GO
