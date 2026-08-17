USE [SmartBankDB];
GO
EXEC ops.usp_BackupHealth @Days = 7;
GO

USE [msdb];
GO
SELECT job.name, activity.run_requested_date, activity.start_execution_date, activity.stop_execution_date,
       CASE WHEN activity.start_execution_date IS NOT NULL AND activity.stop_execution_date IS NULL THEN 'RUNNING' ELSE 'IDLE' END AS CurrentState
FROM dbo.sysjobs AS job
LEFT JOIN dbo.sysjobactivity AS activity ON activity.job_id = job.job_id
    AND activity.session_id = (SELECT MAX(session_id) FROM dbo.syssessions)
WHERE job.name LIKE N'SmartBank - %';

SELECT TOP (100) job.name, history.run_date, history.run_time, history.run_duration,
       history.run_status,
       CASE WHEN history.message LIKE N'%invoked by Schedule%'
            THEN 'SCHEDULED' ELSE 'MANUAL_OR_OTHER' END AS InvocationType,
       history.message
FROM dbo.sysjobhistory AS history
INNER JOIN dbo.sysjobs AS job ON job.job_id = history.job_id
WHERE job.name LIKE N'SmartBank - %' AND history.step_id = 0
ORDER BY history.instance_id DESC;

;WITH ScheduledBackupOutcomes AS
(
    SELECT job.name,
           CONVERT(date, CONVERT(char(8), history.run_date), 112) AS RunDate,
           history.run_status
    FROM dbo.sysjobhistory AS history
    INNER JOIN dbo.sysjobs AS job ON job.job_id = history.job_id
    WHERE job.name IN
          (N'SmartBank - Full Backup', N'SmartBank - Differential Backup', N'SmartBank - Log Backup')
      AND history.step_id = 0
      AND history.message LIKE N'%invoked by Schedule%'
),
DailyScheduledOutcomes AS
(
    SELECT RunDate,
           SUM(CASE WHEN run_status = 1 THEN 1 ELSE 0 END) AS ScheduledBackupsSucceeded,
           SUM(CASE WHEN run_status <> 1 THEN 1 ELSE 0 END) AS ScheduledBackupsNotSucceeded,
           COUNT(DISTINCT CASE WHEN run_status = 1 THEN name END) AS DistinctBackupJobsSucceeded
    FROM ScheduledBackupOutcomes
    GROUP BY RunDate
),
RecentThreeDates AS
(
    SELECT TOP (3) RunDate, ScheduledBackupsSucceeded,
           ScheduledBackupsNotSucceeded, DistinctBackupJobsSucceeded
    FROM DailyScheduledOutcomes
    ORDER BY RunDate DESC
)
SELECT RunDate,
       ScheduledBackupsSucceeded,
       ScheduledBackupsNotSucceeded,
       DistinctBackupJobsSucceeded,
       CASE WHEN COUNT(*) OVER () = 3
                  AND DATEDIFF(DAY, MIN(RunDate) OVER (), MAX(RunDate) OVER ()) = 2
                  AND SUM(ScheduledBackupsNotSucceeded) OVER () = 0
            THEN 'PASS - three consecutive dates with scheduled successes and no failed outcomes'
            ELSE 'NOT YET PASSING - inspect dates and outcomes' END AS ThreeDayEvidenceStatus
FROM RecentThreeDates
ORDER BY RunDate DESC;
GO
