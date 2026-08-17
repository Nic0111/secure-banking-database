-- Connect as: sa.
USE [msdb];
GO

-- Verify that the log-backup schedule is configured for the five-minute RPO.
IF NOT EXISTS
(
    SELECT 1
    FROM dbo.sysjobs AS job
    INNER JOIN dbo.sysjobschedules AS jobSchedule ON jobSchedule.job_id = job.job_id
    INNER JOIN dbo.sysschedules AS schedule ON schedule.schedule_id = jobSchedule.schedule_id
    WHERE job.name = N'SmartBank - Log Backup'
      AND job.enabled = 1
      AND schedule.freq_subday_type = 4
      AND schedule.freq_subday_interval = 5
)
    THROW 51310, 'FAIL: the five-minute log-backup schedule is missing.', 1;

SELECT TOP (50) backup_start_date, backup_finish_date, first_lsn, last_lsn
FROM dbo.backupset
WHERE database_name = N'SmartBankDB' AND type = 'L'
ORDER BY backup_finish_date DESC;
GO
