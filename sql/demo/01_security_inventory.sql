USE [SmartBankDB];
GO

SELECT * FROM api.vw_UserRoleMembership ORDER BY DatabaseRole, DatabaseUser;
SELECT * FROM api.vw_RolePermissionMatrix ORDER BY PrincipalName, SecurableName, PermissionName;

SELECT policy.name AS PolicyName, policy.is_enabled,
       OBJECT_SCHEMA_NAME(predicate.target_object_id) AS TargetSchema,
       OBJECT_NAME(predicate.target_object_id) AS TargetTable,
       predicate.predicate_definition
FROM sys.security_policies AS policy
INNER JOIN sys.security_predicates AS predicate ON predicate.object_id = policy.object_id;

SELECT OBJECT_SCHEMA_NAME(object_id) AS SchemaName, OBJECT_NAME(object_id) AS TableName,
       name AS ColumnName, masking_function
FROM sys.masked_columns WHERE is_masked = 1;

SELECT databaseName = DB_NAME(database_id), encryption_state_desc, key_algorithm, key_length
FROM sys.dm_database_encryption_keys WHERE database_id IN (DB_ID(N'SmartBankDB'), DB_ID(N'SmartBankAnalyticsDB'));

SELECT name, algorithm_desc, key_length FROM sys.symmetric_keys;
SELECT name, subject, expiry_date, pvt_key_encryption_type_desc FROM sys.certificates;

SELECT classificationSchema = schema_name(objects.schema_id), classificationTable = objects.name,
       classificationColumn = columns.name, sensitivity.label, sensitivity.information_type, sensitivity.rank_desc
FROM sys.sensitivity_classifications AS sensitivity
INNER JOIN sys.objects AS objects ON objects.object_id = sensitivity.major_id
INNER JOIN sys.columns AS columns ON columns.object_id = sensitivity.major_id AND columns.column_id = sensitivity.minor_id;
GO

USE [msdb];
GO
SELECT job.name, job.enabled, schedule.name AS ScheduleName, schedule.active_start_time,
       schedule.freq_subday_type, schedule.freq_subday_interval
FROM dbo.sysjobs AS job
LEFT JOIN dbo.sysjobschedules AS jobSchedule ON jobSchedule.job_id = job.job_id
LEFT JOIN dbo.sysschedules AS schedule ON schedule.schedule_id = jobSchedule.schedule_id
WHERE job.name LIKE N'SmartBank - %';
GO
