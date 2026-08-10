-- Read-only consolidated evidence for the lecturer demonstration.
USE [SmartBankDB];
GO
SET NOCOUNT ON;
GO

SELECT CAST(SERVERPROPERTY('ServerName') AS nvarchar(128)) AS ServerName,
       CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(128)) AS ProductVersion,
       CAST(SERVERPROPERTY('Edition') AS nvarchar(128)) AS Edition,
       databaseInfo.name AS DatabaseName,
       databaseInfo.recovery_model_desc AS RecoveryModel,
       encryption.encryption_state AS TdeState,
       encryption.key_algorithm AS TdeAlgorithm,
       encryption.key_length AS TdeKeyLength
FROM sys.databases AS databaseInfo
LEFT JOIN sys.dm_database_encryption_keys AS encryption
    ON encryption.database_id = databaseInfo.database_id
WHERE databaseInfo.name IN (N'SmartBankDB', N'SmartBankAnalyticsDB');

SELECT N'Staff' AS Entity, COUNT_BIG(*) AS [RowCount] FROM core.Staff
UNION ALL SELECT N'Customers', COUNT_BIG(*) FROM core.Customer
UNION ALL SELECT N'Accounts', COUNT_BIG(*) FROM core.Account
UNION ALL SELECT N'Transactions', COUNT_BIG(*) FROM core.TransactionRecord
UNION ALL SELECT N'DML audit records', COUNT_BIG(*) FROM audit.DmlAudit
UNION ALL SELECT N'Application events', COUNT_BIG(*) FROM audit.ApplicationEvent;

SELECT roleInfo.name AS DatabaseRole, memberInfo.name AS DatabaseUser
FROM sys.database_role_members AS membership
JOIN sys.database_principals AS roleInfo ON roleInfo.principal_id = membership.role_principal_id
JOIN sys.database_principals AS memberInfo ON memberInfo.principal_id = membership.member_principal_id
WHERE roleInfo.name LIKE N'rl[_]%'
ORDER BY roleInfo.name, memberInfo.name;

SELECT policy.name AS SecurityPolicy,
       OBJECT_SCHEMA_NAME(predicate.target_object_id) + N'.' + OBJECT_NAME(predicate.target_object_id) AS ProtectedTable,
       predicate.predicate_type_desc AS PredicateType,
       predicate.operation_desc AS Operation,
       predicate.predicate_definition AS PredicateDefinition,
       policy.is_enabled AS IsEnabled
FROM sys.security_policies AS policy
JOIN sys.security_predicates AS predicate ON predicate.object_id = policy.object_id
ORDER BY policy.name, predicate.predicate_type_desc, predicate.operation_desc;

SELECT OBJECT_SCHEMA_NAME(masked.object_id) + N'.' + OBJECT_NAME(masked.object_id) AS ProtectedObject,
       masked.name AS ColumnName,
       masked.masking_function AS MaskingFunction
FROM sys.masked_columns AS masked
WHERE masked.is_masked = 1
ORDER BY ProtectedObject, masked.column_id;

SELECT COUNT_BIG(*) AS CredentialRows,
       MIN(DATALENGTH(Salt)) AS MinimumSaltBytes,
       MIN(DATALENGTH(PinHash)) AS MinimumHashBytes,
       MAX(FailedAttempts) AS HighestFailedAttemptCount
FROM sec.TransactionCredential;

SELECT ActionType, COUNT_BIG(*) AS EventCount, MAX(EventTime) AS LatestEventUtc
FROM audit.DmlAudit
GROUP BY ActionType
ORDER BY ActionType;

SELECT backupset.type AS BackupType,
       COUNT_BIG(*) AS BackupCount,
       MIN(backupset.backup_finish_date) AS FirstBackupServerTime,
       MAX(backupset.backup_finish_date) AS LatestBackupServerTime,
       MIN(backupset.key_algorithm) AS EncryptionAlgorithm,
       MIN(CONVERT(int, backupset.has_backup_checksums)) AS AllHaveChecksum
FROM msdb.dbo.backupset AS backupset
WHERE backupset.database_name = DB_NAME()
GROUP BY backupset.type
ORDER BY backupset.type;

SELECT job.name AS JobName,
       job.enabled AS IsEnabled,
       activity.last_executed_step_date AS LastStepServerTime,
       CASE history.run_status WHEN 0 THEN N'Failed' WHEN 1 THEN N'Succeeded'
            WHEN 2 THEN N'Retry' WHEN 3 THEN N'Cancelled' ELSE N'No completed run' END AS LastOutcome
FROM msdb.dbo.sysjobs AS job
LEFT JOIN msdb.dbo.sysjobactivity AS activity
    ON activity.job_id = job.job_id
   AND activity.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions)
OUTER APPLY
(
    SELECT TOP (1) historyInfo.run_status
    FROM msdb.dbo.sysjobhistory AS historyInfo
    WHERE historyInfo.job_id = job.job_id AND historyInfo.step_id = 0
    ORDER BY historyInfo.instance_id DESC
) AS history
WHERE job.name LIKE N'SmartBank - %'
ORDER BY job.name;

SELECT databaseInfo.name AS ValidationDatabase, databaseInfo.state_desc AS StateDescription
FROM sys.databases AS databaseInfo
WHERE databaseInfo.name IN (N'SmartBankDB_RestoreValidation', N'SmartBankDB_RestoreDemo', N'SmartBankDB_PITR')
ORDER BY databaseInfo.name;

IF DB_ID(N'SmartBankDB_PITR') IS NOT NULL
BEGIN
    SELECT N'Active database' AS DatabaseCopy, COUNT_BIG(*) AS RecoveryRowCount
    FROM SmartBankDB.demo.RecoveryTarget
    UNION ALL
    SELECT N'Point-in-time restored database', COUNT_BIG(*)
    FROM SmartBankDB_PITR.demo.RecoveryTarget;
END;
GO
