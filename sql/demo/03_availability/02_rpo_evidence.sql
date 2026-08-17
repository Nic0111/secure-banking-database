/*
ASSIGNMENT SECTION:
Section 3 - Availability

REQUIREMENT:
2. Demonstrate the stated recovery point objective (RPO).

RUN AS:
sa while SQL Server Agent is running.

EXPECTED RESULT:
The SmartBank log-backup job is enabled and scheduled every five minutes. The
latest successful encrypted/checksummed log backup is no more than five minutes old.

PASS CONDITION:
The configured interval is exactly five minutes and measured latest-log-backup age
is at most 300 seconds at the time of capture.

DATABASE CHANGES:
None. This script is read-only.
*/
USE [SmartBankDB];
GO
SET NOCOUNT ON;
GO

IF IS_SRVROLEMEMBER(N'sysadmin') <> 1
    THROW 51310, 'Run RPO evidence as sa or another sysadmin.', 1;

DECLARE @ScheduleIntervalMinutes int;
SELECT @ScheduleIntervalMinutes = scheduleInfo.freq_subday_interval
FROM msdb.dbo.sysjobs AS job
INNER JOIN msdb.dbo.sysjobschedules AS jobSchedule ON jobSchedule.job_id = job.job_id
INNER JOIN msdb.dbo.sysschedules AS scheduleInfo ON scheduleInfo.schedule_id = jobSchedule.schedule_id
WHERE job.name = N'SmartBank - Log Backup'
  AND job.enabled = 1 AND scheduleInfo.enabled = 1
  AND scheduleInfo.freq_subday_type = 4;

DECLARE @LatestLogBackup datetime, @LatestChecksum bit, @LatestAlgorithm nvarchar(32);
SELECT TOP (1)
       @LatestLogBackup = backup_finish_date,
       @LatestChecksum = has_backup_checksums,
       @LatestAlgorithm = key_algorithm
FROM msdb.dbo.backupset
WHERE database_name = DB_NAME() AND type = 'L'
ORDER BY backup_finish_date DESC;

DECLARE @LatestAgeSeconds int = DATEDIFF(SECOND, @LatestLogBackup, GETDATE());

SELECT job.name AS JobName, job.enabled AS JobEnabled,
       scheduleInfo.name AS ScheduleName, scheduleInfo.enabled AS ScheduleEnabled,
       scheduleInfo.freq_subday_interval AS IntervalMinutes,
       @LatestLogBackup AS LatestLogBackupServerTime,
       @LatestAgeSeconds AS LatestLogBackupAgeSeconds,
       @LatestChecksum AS HasChecksum,
       @LatestAlgorithm AS EncryptionAlgorithm,
       IIF(@ScheduleIntervalMinutes = 5 AND @LatestAgeSeconds BETWEEN 0 AND 300
           AND @LatestChecksum = 1 AND @LatestAlgorithm = N'AES_256', N'PASS', N'FAIL') AS Result
FROM msdb.dbo.sysjobs AS job
INNER JOIN msdb.dbo.sysjobschedules AS jobSchedule ON jobSchedule.job_id = job.job_id
INNER JOIN msdb.dbo.sysschedules AS scheduleInfo ON scheduleInfo.schedule_id = jobSchedule.schedule_id
WHERE job.name = N'SmartBank - Log Backup';

;WITH RecentLogBackups AS
(
    SELECT backup_finish_date,
           LAG(backup_finish_date) OVER (ORDER BY backup_finish_date) AS PreviousFinishTime
    FROM msdb.dbo.backupset
    WHERE database_name = DB_NAME() AND type = 'L'
      AND backup_finish_date >= DATEADD(DAY, -1, GETDATE())
)
SELECT COUNT(*) AS LogBackupsInLast24Hours,
       MAX(DATEDIFF(SECOND, PreviousFinishTime, backup_finish_date)) AS LargestObservedFinishGapSeconds,
       MIN(backup_finish_date) AS FirstObservedBackup,
       MAX(backup_finish_date) AS LastObservedBackup
FROM RecentLogBackups;

IF @ScheduleIntervalMinutes IS NULL OR @ScheduleIntervalMinutes <> 5 OR @LatestLogBackup IS NULL
   OR @LatestAgeSeconds NOT BETWEEN 0 AND 300
   OR @LatestChecksum <> 1 OR @LatestAlgorithm <> N'AES_256'
    THROW 51311, 'FAIL - current measured evidence does not meet the five-minute RPO.', 1;
GO
