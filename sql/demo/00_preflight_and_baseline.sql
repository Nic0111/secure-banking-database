-- Run as: sa
-- Check that the database, demo users, and backup jobs are ready.
USE [SmartBankDB];
GO

SELECT name AS DatabaseName, state_desc AS State, recovery_model_desc AS RecoveryModel
FROM sys.databases
WHERE name IN (N'SmartBankDB', N'SmartBankAnalyticsDB');

SELECT loginInfo.name AS LoginName, databaseUser.name AS DatabaseUser, roleInfo.name AS DatabaseRole
FROM master.sys.server_principals AS loginInfo
LEFT JOIN sys.database_principals AS databaseUser ON databaseUser.sid = loginInfo.sid
LEFT JOIN sys.database_role_members AS membership ON membership.member_principal_id = databaseUser.principal_id
LEFT JOIN sys.database_principals AS roleInfo ON roleInfo.principal_id = membership.role_principal_id
WHERE loginInfo.name LIKE N'sb[_]%'
ORDER BY loginInfo.name, roleInfo.name;

SELECT N'Staff' AS Item, COUNT(*) AS Rows FROM core.Staff
UNION ALL SELECT N'Customers', COUNT(*) FROM core.Customer
UNION ALL SELECT N'Accounts', COUNT(*) FROM core.Account
UNION ALL SELECT N'Transactions', COUNT(*) FROM core.TransactionRecord
UNION ALL SELECT N'Recovery target', COUNT(*) FROM demo.RecoveryTarget;

-- Show the automated backup jobs.
SELECT job.name AS JobName, job.enabled AS IsEnabled, schedule.name AS ScheduleName,
       schedule.freq_subday_interval AS Interval, schedule.active_start_time AS StartTime
FROM msdb.dbo.sysjobs AS job
LEFT JOIN msdb.dbo.sysjobschedules AS jobSchedule ON jobSchedule.job_id = job.job_id
LEFT JOIN msdb.dbo.sysschedules AS schedule ON schedule.schedule_id = jobSchedule.schedule_id
WHERE job.name LIKE N'SmartBank - %'
ORDER BY job.name;
GO
