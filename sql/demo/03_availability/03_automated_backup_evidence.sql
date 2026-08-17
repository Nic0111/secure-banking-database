/*
ASSIGNMENT SECTION:
Section 3 - Availability

REQUIREMENT:
3. Backups must be automated and provide usable recovery evidence.

RUN AS:
sa after the full, differential and log SQL Server Agent jobs have each completed
successfully at least once.

EXPECTED RESULT:
All three jobs are enabled with a step, schedule and target server. Recent backups
of each type use AES-256 encryption and checksums, and ops.BackupRun records a
successful RESTORE VERIFYONLY result.

PASS CONDITION:
FULL, DIFFERENTIAL and LOG each have an enabled job, successful job history,
encrypted/checksummed backup metadata and a verified successful run.

DATABASE CHANGES:
None. This script is read-only.
*/
USE [SmartBankDB];
GO
SET NOCOUNT ON;
GO

IF IS_SRVROLEMEMBER(N'sysadmin') <> 1
    THROW 51320, 'Run automated-backup evidence as sa or another sysadmin.', 1;

DECLARE @RequiredJobs table
(
    JobName sysname PRIMARY KEY,
    BackupCode char(1) NOT NULL,
    MsdbBackupType char(1) NOT NULL,
    FriendlyType varchar(20) NOT NULL
);
INSERT @RequiredJobs
VALUES (N'SmartBank - Full Backup', 'F', 'D', 'FULL'),
       (N'SmartBank - Differential Backup', 'D', 'I', 'DIFFERENTIAL'),
       (N'SmartBank - Log Backup', 'L', 'L', 'LOG');

SELECT requiredJob.FriendlyType AS BackupType,
       job.name AS JobName, job.enabled AS JobEnabled,
       stepInfo.StepCount, scheduleInfo.ScheduleCount, serverInfo.TargetServerCount,
       lastHistory.LastRunServerTime, lastHistory.LastOutcome,
       latestBackup.backup_finish_date AS LatestBackupServerTime,
       latestBackup.has_backup_checksums AS HasChecksum,
       latestBackup.key_algorithm AS EncryptionAlgorithm,
       latestBackup.encryptor_type AS EncryptorType,
       latestRun.FinishedAt AS LatestVerifiedRunUtc,
       latestRun.Succeeded, latestRun.Verified
FROM @RequiredJobs AS requiredJob
LEFT JOIN msdb.dbo.sysjobs AS job ON job.name = requiredJob.JobName
OUTER APPLY
(
    SELECT COUNT(*) AS StepCount FROM msdb.dbo.sysjobsteps WHERE job_id = job.job_id
) AS stepInfo
OUTER APPLY
(
    SELECT COUNT(*) AS ScheduleCount FROM msdb.dbo.sysjobschedules WHERE job_id = job.job_id
) AS scheduleInfo
OUTER APPLY
(
    SELECT COUNT(*) AS TargetServerCount FROM msdb.dbo.sysjobservers WHERE job_id = job.job_id
) AS serverInfo
OUTER APPLY
(
    SELECT TOP (1)
           msdb.dbo.agent_datetime(run_date, run_time) AS LastRunServerTime,
           CASE run_status WHEN 0 THEN N'Failed' WHEN 1 THEN N'Succeeded'
                WHEN 2 THEN N'Retry' WHEN 3 THEN N'Cancelled' ELSE N'Unknown' END AS LastOutcome
    FROM msdb.dbo.sysjobhistory
    WHERE job_id = job.job_id AND step_id = 0
    ORDER BY instance_id DESC
) AS lastHistory
OUTER APPLY
(
    SELECT TOP (1) backup_finish_date, has_backup_checksums, key_algorithm, encryptor_type
    FROM msdb.dbo.backupset
    WHERE database_name = DB_NAME() AND type = requiredJob.MsdbBackupType
    ORDER BY backup_finish_date DESC
) AS latestBackup
OUTER APPLY
(
    SELECT TOP (1) FinishedAt, Succeeded, Verified
    FROM ops.BackupRun
    WHERE BackupType = requiredJob.BackupCode
    ORDER BY FinishedAt DESC, BackupRunID DESC
) AS latestRun
ORDER BY CASE requiredJob.BackupCode WHEN 'F' THEN 1 WHEN 'D' THEN 2 ELSE 3 END;

IF EXISTS
(
    SELECT 1
    FROM @RequiredJobs AS requiredJob
    LEFT JOIN msdb.dbo.sysjobs AS job ON job.name = requiredJob.JobName
    OUTER APPLY
    (
        SELECT TOP (1) run_status
        FROM msdb.dbo.sysjobhistory
        WHERE job_id = job.job_id AND step_id = 0
        ORDER BY instance_id DESC
    ) AS lastHistory
    OUTER APPLY
    (
        SELECT TOP (1) has_backup_checksums, key_algorithm
        FROM msdb.dbo.backupset
        WHERE database_name = DB_NAME() AND type = requiredJob.MsdbBackupType
        ORDER BY backup_finish_date DESC
    ) AS latestBackup
    OUTER APPLY
    (
        SELECT TOP (1) Succeeded, Verified
        FROM ops.BackupRun
        WHERE BackupType = requiredJob.BackupCode
        ORDER BY FinishedAt DESC, BackupRunID DESC
    ) AS latestRun
    WHERE job.job_id IS NULL OR job.enabled <> 1
       OR NOT EXISTS (SELECT 1 FROM msdb.dbo.sysjobsteps WHERE job_id = job.job_id)
       OR NOT EXISTS (SELECT 1 FROM msdb.dbo.sysjobschedules WHERE job_id = job.job_id)
       OR NOT EXISTS (SELECT 1 FROM msdb.dbo.sysjobservers WHERE job_id = job.job_id)
       OR ISNULL(lastHistory.run_status, -1) <> 1
       OR ISNULL(latestBackup.has_backup_checksums, 0) <> 1
       OR ISNULL(latestBackup.key_algorithm, N'') <> N'AES_256'
       OR ISNULL(latestRun.Succeeded, 0) <> 1 OR ISNULL(latestRun.Verified, 0) <> 1
)
    THROW 51321, 'FAIL - one or more automated backup types lacks complete successful evidence.', 1;

SELECT N'PASS' AS Result,
       N'Full, differential and log backups are scheduled, encrypted, checked and automatically verified.' AS Evidence;
GO
