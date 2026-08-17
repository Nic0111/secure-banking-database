/*
ASSIGNMENT SECTION:
Sections 1-3 - Consolidated confidentiality, integrity and availability evidence

REQUIREMENT:
Provide one read-only summary that connects identities, authorization, data
protection, audit integrity and recovery/backup controls to the assignment.

RUN AS:
sa at the end of the demonstration.

EXPECTED RESULT:
The result sets summarize the deployed security posture and demonstration evidence.
Any unmet item is shown explicitly rather than converted into a false pass.

PASS CONDITION:
Role boundaries, enabled RLS/audit/TDE controls, consistent ledger/balances,
encrypted verified backups and recovery evidence can be traced to their detailed
numbered scripts.

DATABASE CHANGES:
None. This script is read-only.
*/
USE [SmartBankDB];
GO
SET NOCOUNT ON;
GO

IF IS_SRVROLEMEMBER(N'sysadmin') <> 1
    THROW 51990, 'Run consolidated evidence as sa or another sysadmin.', 1;

-- 1. Server, databases, recovery model and transparent encryption.
SELECT CAST(SERVERPROPERTY('ServerName') AS nvarchar(128)) AS ServerName,
       CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(128)) AS ProductVersion,
       CAST(SERVERPROPERTY('Edition') AS nvarchar(128)) AS Edition,
       databaseInfo.name AS DatabaseName,
       databaseInfo.state_desc AS DatabaseState,
       databaseInfo.recovery_model_desc AS RecoveryModel,
       encryption.encryption_state AS TdeState,
       encryption.key_algorithm AS TdeAlgorithm,
       encryption.key_length AS TdeKeyLength
FROM sys.databases AS databaseInfo
LEFT JOIN sys.dm_database_encryption_keys AS encryption
    ON encryption.database_id = databaseInfo.database_id
WHERE databaseInfo.name IN (N'SmartBankDB', N'SmartBankAnalyticsDB')
ORDER BY databaseInfo.name;

-- 2. Golden baseline and transparent demo deltas.
DECLARE @Dataset table (Entity nvarchar(50), BaselineRows bigint, ActualRows bigint);
INSERT @Dataset
VALUES (N'Staff', 7, (SELECT COUNT_BIG(*) FROM core.Staff)),
       (N'Customers', 12, (SELECT COUNT_BIG(*) FROM core.Customer)),
       (N'Accounts', 18, (SELECT COUNT_BIG(*) FROM core.Account)),
       (N'Transactions', 44, (SELECT COUNT_BIG(*) FROM core.TransactionRecord)),
       (N'Recovery target', 10, (SELECT COUNT_BIG(*) FROM demo.RecoveryTarget));
SELECT Entity, BaselineRows, ActualRows, ActualRows - BaselineRows AS DemoDelta,
       IIF(ActualRows = BaselineRows, N'GOLDEN BASELINE', N'DEMO-CHANGED') AS DatasetState
FROM @Dataset ORDER BY Entity;

-- 3. Authentication chain and authorization matrix.
SELECT loginInfo.name AS ServerLogin, loginInfo.type_desc AS LoginType,
       loginInfo.is_disabled AS LoginDisabled,
       databaseUser.name AS DatabaseUser,
       principalMap.UserType, principalMap.StaffID, principalMap.CustomerID,
       principalMap.IsActive
FROM master.sys.server_principals AS loginInfo
LEFT JOIN sys.database_principals AS databaseUser ON databaseUser.sid = loginInfo.sid
LEFT JOIN sec.PrincipalMap AS principalMap ON principalMap.LoginName = loginInfo.name
WHERE loginInfo.name LIKE N'sb[_]%'
ORDER BY loginInfo.name;

SELECT DatabaseUser, DatabaseRole, UserType, StaffID, CustomerID, IsActive
FROM api.vw_UserRoleMembership
ORDER BY DatabaseRole, DatabaseUser;

SELECT PrincipalName, PrincipalType, PermissionState, PermissionName,
       SecurableClass, SecurableName
FROM api.vw_RolePermissionMatrix
ORDER BY PrincipalName, SecurableName, PermissionName;

-- Explicitly surface the currently known staff-own-update permission gap.
SELECT roleInfo.name AS StaffRole,
       permissionInfo.state_desc AS ExecuteState,
       IIF(permissionInfo.state_desc = N'GRANT_WITH_GRANT_OPTION' OR permissionInfo.state_desc = N'GRANT', N'PASS', N'FAIL') AS RequirementResult,
       N'EXECUTE api.usp_UpdateOwnStaffProfile' AS RequiredPermission
FROM (VALUES (N'rl_dba'), (N'rl_manager'), (N'rl_officer')) AS expectedRole(RoleName)
INNER JOIN sys.database_principals AS roleInfo ON roleInfo.name = expectedRole.RoleName
LEFT JOIN sys.database_permissions AS permissionInfo
    ON permissionInfo.grantee_principal_id = roleInfo.principal_id
   AND permissionInfo.class = 1
   AND permissionInfo.major_id = OBJECT_ID(N'api.usp_UpdateOwnStaffProfile')
   AND permissionInfo.permission_name = N'EXECUTE'
ORDER BY roleInfo.name;

-- 4. Row isolation, masking and cryptographic controls.
SELECT policy.name AS SecurityPolicy,
       OBJECT_SCHEMA_NAME(predicate.target_object_id) + N'.' + OBJECT_NAME(predicate.target_object_id) AS ProtectedTable,
       predicate.predicate_type_desc AS PredicateType,
       predicate.operation_desc AS Operation,
       predicate.predicate_definition AS PredicateDefinition,
       policy.is_enabled AS IsEnabled
FROM sys.security_policies AS policy
INNER JOIN sys.security_predicates AS predicate ON predicate.object_id = policy.object_id
ORDER BY policy.name, ProtectedTable, predicate.predicate_type_desc;

SELECT OBJECT_SCHEMA_NAME(masked.object_id) + N'.' + OBJECT_NAME(masked.object_id) AS ProtectedObject,
       masked.name AS ColumnName, masked.masking_function AS MaskingFunction
FROM sys.masked_columns AS masked
WHERE masked.is_masked = 1
ORDER BY ProtectedObject, masked.column_id;

SELECT certificateInfo.name AS CertificateName,
       certificateInfo.subject AS CertificateSubject,
       certificateInfo.expiry_date AS CertificateExpiry,
       symmetricKey.name AS SymmetricKeyName,
       symmetricKey.algorithm_desc AS SymmetricKeyAlgorithm,
       symmetricKey.key_length AS SymmetricKeyLength
FROM sys.certificates AS certificateInfo
LEFT JOIN sys.symmetric_keys AS symmetricKey
    ON symmetricKey.name = N'SmartBank_Column_Key'
WHERE certificateInfo.name = N'SmartBank_Column_Certificate';

SELECT COUNT_BIG(*) AS TransactionCredentialRows,
       MIN(DATALENGTH(Salt)) AS MinimumSaltBytes,
       MIN(DATALENGTH(PinHash)) AS MinimumHashBytes,
       MAX(FailedAttempts) AS HighestFailedAttemptCount
FROM sec.TransactionCredential;

-- 5. Integrity and audit summaries.
SELECT ActionType, COUNT_BIG(*) AS DmlAuditRows, MAX(EventTime) AS LatestEventUtc
FROM audit.DmlAudit GROUP BY ActionType ORDER BY ActionType;
SELECT Succeeded, EventType, COUNT_BIG(*) AS ApplicationEventRows,
       MAX(EventTime) AS LatestEventUtc
FROM audit.ApplicationEvent GROUP BY Succeeded, EventType ORDER BY Succeeded, EventType;
SELECT serverAudit.name AS ServerAudit, serverAudit.is_state_enabled AS ServerAuditEnabled,
       databaseAudit.name AS DatabaseAuditSpecification,
       databaseAudit.is_state_enabled AS DatabaseAuditEnabled
FROM master.sys.server_audits AS serverAudit
CROSS JOIN sys.database_audit_specifications AS databaseAudit
WHERE serverAudit.name = N'SmartBank_ServerAudit'
  AND databaseAudit.name = N'SmartBank_DatabaseAuditSpecification';

EXEC api.usp_VerifyLedgerChain;
EXEC api.usp_VerifyAccountBalances;

-- 6. Backup automation and verification evidence.
SELECT CASE backupset.type WHEN 'D' THEN N'FULL' WHEN 'I' THEN N'DIFFERENTIAL'
                           WHEN 'L' THEN N'LOG' ELSE backupset.type END AS BackupType,
       COUNT_BIG(*) AS BackupCount,
       MAX(backupset.backup_finish_date) AS LatestBackupServerTime,
       MIN(CONVERT(int, backupset.has_backup_checksums)) AS AllHaveChecksum,
       MIN(backupset.key_algorithm) AS EncryptionAlgorithm
FROM msdb.dbo.backupset AS backupset
WHERE backupset.database_name = DB_NAME() AND backupset.type IN ('D', 'I', 'L')
GROUP BY backupset.type ORDER BY BackupType;

SELECT BackupType, COUNT_BIG(*) AS RecordedRuns,
       SUM(CONVERT(bigint, Succeeded)) AS SuccessfulRuns,
       SUM(CONVERT(bigint, Verified)) AS VerifiedRuns,
       MAX(FinishedAt) AS LatestRunUtc
FROM ops.BackupRun GROUP BY BackupType ORDER BY BackupType;

SELECT job.name AS JobName, job.enabled AS IsEnabled,
       scheduleInfo.name AS ScheduleName, scheduleInfo.enabled AS ScheduleEnabled,
       scheduleInfo.freq_type, scheduleInfo.freq_subday_type,
       scheduleInfo.freq_subday_interval, scheduleInfo.active_start_time
FROM msdb.dbo.sysjobs AS job
LEFT JOIN msdb.dbo.sysjobschedules AS jobSchedule ON jobSchedule.job_id = job.job_id
LEFT JOIN msdb.dbo.sysschedules AS scheduleInfo ON scheduleInfo.schedule_id = jobSchedule.schedule_id
WHERE job.name LIKE N'SmartBank - %'
ORDER BY job.name, scheduleInfo.name;

-- 7. Recovery evidence state. Detailed row comparison is in 03_availability/01.
SELECT databaseInfo.name AS ValidationDatabase, databaseInfo.state_desc AS StateDescription
FROM sys.databases AS databaseInfo
WHERE databaseInfo.name IN
      (N'SmartBankDB_RestoreDemo', N'SmartBankDB_PITR')
ORDER BY databaseInfo.name;

SELECT TOP (5) MarkerID, MarkerTimeUtc, MarkerTimeServer, MarkerLabel, CreatedBy, CreatedAt
FROM ops.RecoveryMarker
WHERE MarkerLabel LIKE N'PITR:%'
ORDER BY CreatedAt DESC;

IF DB_ID(N'SmartBankDB_PITR') IS NOT NULL
BEGIN
    DECLARE @RecoveryComparisonSql nvarchar(max) =
        N'SELECT N''Live database'' AS DatabaseCopy, COUNT_BIG(*) AS RecoveryRowCount
          FROM SmartBankDB.demo.RecoveryTarget
          UNION ALL
          SELECT N''Point-in-time restored database'', COUNT_BIG(*)
          FROM SmartBankDB_PITR.demo.RecoveryTarget;';
    EXEC sys.sp_executesql @RecoveryComparisonSql;
END
ELSE
    SELECT N'PENDING' AS RecoveryEvidence,
           N'Follow sql/recovery/README.md: run the point-in-time scenario, operation, and validation scripts before capturing PITR comparison evidence.' AS NextAction;
GO
