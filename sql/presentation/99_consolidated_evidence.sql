USE [SmartBankDB];
GO

-- Show databases and encryption.
SELECT databaseInfo.name AS DatabaseName, databaseInfo.state_desc AS State,
       databaseInfo.recovery_model_desc AS RecoveryModel,
       encryption.encryption_state_desc AS TdeState, encryption.key_algorithm AS TdeAlgorithm
FROM sys.databases AS databaseInfo
LEFT JOIN sys.dm_database_encryption_keys AS encryption ON encryption.database_id = databaseInfo.database_id
WHERE databaseInfo.name IN (N'SmartBankDB', N'SmartBankAnalyticsDB');

-- Show users, roles, and granted permissions.
SELECT * FROM api.vw_UserRoleMembership ORDER BY DatabaseRole, DatabaseUser;
SELECT * FROM api.vw_RolePermissionMatrix ORDER BY PrincipalName, SecurableName, PermissionName;

-- Show row-level security and dynamic masking.
SELECT name AS PolicyName, is_enabled AS IsEnabled FROM sys.security_policies;
SELECT OBJECT_SCHEMA_NAME(object_id) + N'.' + OBJECT_NAME(object_id) AS ObjectName,
       name AS ColumnName, masking_function
FROM sys.masked_columns
WHERE is_masked = 1;

-- Show audit and recovery evidence.
SELECT TOP (20) EventTime, EventType, OperationName, Succeeded, ActorLogin, ErrorNumber
FROM audit.ApplicationEvent
ORDER BY EventTime DESC;
SELECT name, state_desc FROM sys.databases
WHERE name IN (N'SmartBankDB_PITR', N'SmartBankDB_RestoreDemo');
GO
