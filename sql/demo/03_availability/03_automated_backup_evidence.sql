-- Run as: sa.
USE [msdb];
GO

-- Show encrypted, checksummed backups for the three completed days before today.
SELECT CAST(backup_finish_date AS date) AS BackupDate,
       CASE type WHEN 'D' THEN N'FULL' WHEN 'I' THEN N'DIFFERENTIAL' WHEN 'L' THEN N'LOG' END AS BackupType,
       COUNT(*) AS BackupCount,
       SUM(CASE WHEN has_backup_checksums = 1 AND key_algorithm = N'AES_256' THEN 1 ELSE 0 END) AS EncryptedCheckedBackups
FROM dbo.backupset
WHERE database_name = N'SmartBankDB'
  AND type IN ('D', 'I', 'L')
  AND backup_finish_date >= DATEADD(DAY, -3, CONVERT(date, GETDATE()))
  AND backup_finish_date < CONVERT(date, GETDATE())
GROUP BY CAST(backup_finish_date AS date), type
ORDER BY BackupDate DESC, BackupType;

-- Show whether each scheduled job succeeded on the same three days.
SELECT CAST(msdb.dbo.agent_datetime(history.run_date, history.run_time) AS date) AS BackupDate,
       job.name AS JobName,
       COUNT(*) AS Runs,
       SUM(CASE WHEN history.run_status = 1 THEN 1 ELSE 0 END) AS SuccessfulRuns,
       SUM(CASE WHEN history.run_status <> 1 THEN 1 ELSE 0 END) AS NonSuccessfulRuns
FROM dbo.sysjobs AS job
INNER JOIN dbo.sysjobhistory AS history ON history.job_id = job.job_id
WHERE job.name IN (N'SmartBank - Full Backup', N'SmartBank - Differential Backup', N'SmartBank - Log Backup')
  AND history.step_id = 0
  AND msdb.dbo.agent_datetime(history.run_date, history.run_time) >= DATEADD(DAY, -3, CONVERT(date, GETDATE()))
  AND msdb.dbo.agent_datetime(history.run_date, history.run_time) < CONVERT(date, GETDATE())
GROUP BY CAST(msdb.dbo.agent_datetime(history.run_date, history.run_time) AS date), job.name
ORDER BY BackupDate DESC, JobName;
GO
