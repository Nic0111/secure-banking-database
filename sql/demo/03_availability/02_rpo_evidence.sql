-- Run as: sa.
USE [msdb];
GO

-- Show the five-minute log-backup schedule.
SELECT job.name AS JobName, job.enabled AS IsEnabled, schedule.name AS ScheduleName,
       schedule.freq_subday_interval AS IntervalMinutes
FROM dbo.sysjobs AS job
INNER JOIN dbo.sysjobschedules AS jobSchedule ON jobSchedule.job_id = job.job_id
INNER JOIN dbo.sysschedules AS schedule ON schedule.schedule_id = jobSchedule.schedule_id
WHERE job.name = N'SmartBank - Log Backup';

-- Show recent encrypted log backups and their timestamps.
SELECT TOP (20) backup_finish_date AS FinishedAt, has_backup_checksums, key_algorithm,
       first_lsn, last_lsn
FROM dbo.backupset
WHERE database_name = N'SmartBankDB' AND type = 'L'
ORDER BY backup_finish_date DESC;
GO
