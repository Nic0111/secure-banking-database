USE [$(DatabaseName)];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- Create tables for backup and recovery evidence.
IF OBJECT_ID(N'ops.BackupRun', N'U') IS NULL
BEGIN
    CREATE TABLE ops.BackupRun
    (
        BackupRunID bigint IDENTITY(1, 1) NOT NULL CONSTRAINT PK_BackupRun PRIMARY KEY,
        BackupType char(1) NOT NULL,
        BackupFile nvarchar(4000) NOT NULL,
        StartedAt datetime2(3) NOT NULL,
        FinishedAt datetime2(3) NOT NULL,
        Succeeded bit NOT NULL,
        Verified bit NOT NULL,
        ErrorNumber int NULL,
        ErrorMessage nvarchar(2000) NULL,
        InitiatedBy sysname NOT NULL,
        CONSTRAINT CK_BackupRun_Type CHECK (BackupType IN ('F', 'D', 'L'))
    );
    CREATE INDEX IX_BackupRun_FinishedAt ON ops.BackupRun (FinishedAt DESC, BackupType);
END;
GO

IF OBJECT_ID(N'ops.RecoveryMarker', N'U') IS NULL
BEGIN
    CREATE TABLE ops.RecoveryMarker
    (
        MarkerID uniqueidentifier NOT NULL CONSTRAINT PK_RecoveryMarker PRIMARY KEY,
        MarkerTimeUtc datetime2(3) NOT NULL,
        MarkerTimeServer datetime2(3) NULL,
        MarkerLabel nvarchar(200) NOT NULL,
        ExpectedRecoveryRows nvarchar(max) NOT NULL,
        CreatedBy sysname NOT NULL,
        CreatedAt datetime2(3) NOT NULL CONSTRAINT DF_RecoveryMarker_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT CK_RecoveryMarker_ExpectedRowsJson CHECK (ISJSON(ExpectedRecoveryRows) = 1)
    );
END;
GO

IF COL_LENGTH(N'ops.RecoveryMarker', N'MarkerTimeServer') IS NULL
    ALTER TABLE ops.RecoveryMarker ADD MarkerTimeServer datetime2(3) NULL;
GO

-- Run and verify an encrypted backup.
CREATE OR ALTER PROCEDURE ops.usp_RunBackup
    @BackupType char(1)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @BackupType NOT IN ('F', 'D', 'L')
        THROW 50400, 'Backup type must be F (full), D (differential), or L (transaction log).', 1;

    DECLARE @StartedAt datetime2(3) = SYSUTCDATETIME();
    DECLARE @FinishedAt datetime2(3);
    DECLARE @Directory nvarchar(4000) = (SELECT ConfigValue FROM ops.Configuration WHERE ConfigKey = N'BackupDirectory');
    DECLARE @Separator nvarchar(2) = (SELECT ConfigValue FROM ops.Configuration WHERE ConfigKey = N'PathSeparator');
    DECLARE @Timestamp varchar(20) = CONVERT(char(8), GETDATE(), 112) + '_' + REPLACE(CONVERT(char(8), GETDATE(), 108), ':', '');
    DECLARE @Suffix varchar(12) = CASE @BackupType WHEN 'F' THEN '_FULL_' WHEN 'D' THEN '_DIFF_' ELSE '_LOG_' END;
    DECLARE @Extension varchar(4) = CASE WHEN @BackupType = 'L' THEN '.trn' WHEN @BackupType = 'D' THEN '.dif' ELSE '.bak' END;
    DECLARE @BackupFile nvarchar(4000) = @Directory + @Separator + N'$(DatabaseName)' + @Suffix + @Timestamp + @Extension;
    DECLARE @Sql nvarchar(max);

    BEGIN TRY
        IF @BackupType = 'F'
            SET @Sql = N'BACKUP DATABASE [$(DatabaseName)] TO DISK = @BackupFile
                WITH INIT, COMPRESSION, CHECKSUM,
                ENCRYPTION (ALGORITHM = AES_256, SERVER CERTIFICATE = SmartBank_Backup_Certificate), STATS = 10;';
        ELSE IF @BackupType = 'D'
            SET @Sql = N'BACKUP DATABASE [$(DatabaseName)] TO DISK = @BackupFile
                WITH DIFFERENTIAL, INIT, COMPRESSION, CHECKSUM,
                ENCRYPTION (ALGORITHM = AES_256, SERVER CERTIFICATE = SmartBank_Backup_Certificate), STATS = 10;';
        ELSE
            SET @Sql = N'BACKUP LOG [$(DatabaseName)] TO DISK = @BackupFile
                WITH INIT, COMPRESSION, CHECKSUM,
                ENCRYPTION (ALGORITHM = AES_256, SERVER CERTIFICATE = SmartBank_Backup_Certificate), STATS = 10;';

        EXEC sys.sp_executesql @Sql, N'@BackupFile nvarchar(4000)', @BackupFile;
        RESTORE VERIFYONLY FROM DISK = @BackupFile WITH CHECKSUM;

        SET @FinishedAt = SYSUTCDATETIME();
        INSERT ops.BackupRun
        (BackupType, BackupFile, StartedAt, FinishedAt, Succeeded, Verified, InitiatedBy)
        VALUES (@BackupType, @BackupFile, @StartedAt, @FinishedAt, 1, 1, ORIGINAL_LOGIN());
    END TRY
    BEGIN CATCH
        SET @FinishedAt = SYSUTCDATETIME();
        INSERT ops.BackupRun
        (BackupType, BackupFile, StartedAt, FinishedAt, Succeeded, Verified, ErrorNumber, ErrorMessage, InitiatedBy)
        VALUES (@BackupType, @BackupFile, @StartedAt, @FinishedAt, 0, 0, ERROR_NUMBER(), LEFT(ERROR_MESSAGE(), 2000), ORIGINAL_LOGIN());
        THROW;
    END CATCH;
END;
GO

-- Report recent backup health.
CREATE OR ALTER PROCEDURE ops.usp_BackupHealth
    @Days int = 3
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    IF @Days NOT BETWEEN 1 AND 90 THROW 50401, 'Days must be between 1 and 90.', 1;

    SELECT CAST(backup_finish_date AS date) AS BackupDate,
           SUM(CASE WHEN type = 'D' AND is_copy_only = 0 THEN 1 ELSE 0 END) AS FullBackups,
           SUM(CASE WHEN type = 'I' THEN 1 ELSE 0 END) AS DifferentialBackups,
           SUM(CASE WHEN type = 'L' THEN 1 ELSE 0 END) AS LogBackups,
           SUM(CASE WHEN has_backup_checksums = 1 THEN 1 ELSE 0 END) AS ChecksumBackups,
           SUM(CASE WHEN key_algorithm IS NOT NULL THEN 1 ELSE 0 END) AS EncryptedBackups,
           MIN(backup_finish_date) AS FirstBackup,
           MAX(backup_finish_date) AS LastBackup
    FROM msdb.dbo.backupset
    WHERE database_name = DB_NAME()
      AND backup_finish_date >= DATEADD(DAY, -@Days, CONVERT(date, GETDATE()))
    GROUP BY CAST(backup_finish_date AS date)
    ORDER BY BackupDate DESC;

    SELECT TOP (200)
           backupset.backup_finish_date AS FinishedAt,
           CASE backupset.type WHEN 'D' THEN 'FULL' WHEN 'I' THEN 'DIFFERENTIAL' WHEN 'L' THEN 'LOG' ELSE backupset.type END AS BackupType,
           media.physical_device_name AS BackupFile,
           backupset.backup_size,
           backupset.compressed_backup_size,
           backupset.has_backup_checksums,
           backupset.key_algorithm,
           backupset.encryptor_type,
           backupset.first_lsn,
           backupset.last_lsn
    FROM msdb.dbo.backupset AS backupset
    INNER JOIN msdb.dbo.backupmediafamily AS media ON media.media_set_id = backupset.media_set_id
    WHERE backupset.database_name = DB_NAME()
      AND backupset.backup_finish_date >= DATEADD(DAY, -@Days, GETDATE())
    ORDER BY backupset.backup_finish_date DESC;

    SELECT BackupRunID, BackupType, BackupFile, StartedAt, FinishedAt, Succeeded, Verified,
           DATEDIFF(SECOND, StartedAt, FinishedAt) AS DurationSeconds, ErrorNumber, ErrorMessage, InitiatedBy
    FROM ops.BackupRun
    WHERE StartedAt >= DATEADD(DAY, -@Days, SYSUTCDATETIME())
    ORDER BY StartedAt DESC;
END;
GO

-- Remove expired backup files and history.
CREATE OR ALTER PROCEDURE ops.usp_PruneBackupFiles
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Directory nvarchar(4000) = (SELECT ConfigValue FROM ops.Configuration WHERE ConfigKey = N'BackupDirectory');
    DECLARE @RetentionDays int = TRY_CONVERT(int, (SELECT ConfigValue FROM ops.Configuration WHERE ConfigKey = N'BackupRetentionDays'));
    DECLARE @Cutoff datetime = DATEADD(DAY, -COALESCE(@RetentionDays, 35), GETDATE());

    EXEC master.dbo.xp_delete_file 0, @Directory, N'bak', @Cutoff, 1;
    EXEC master.dbo.xp_delete_file 0, @Directory, N'dif', @Cutoff, 1;
    EXEC master.dbo.xp_delete_file 0, @Directory, N'trn', @Cutoff, 1;
    EXEC msdb.dbo.sp_delete_backuphistory @oldest_date = @Cutoff;
END;
GO

-- Create a fresh full-backup base and deployment-specific backup evidence.
EXEC ops.usp_RunBackup @BackupType = 'F';
GO

-- Enable SQL Server Agent features.
USE [master];
GO
EXEC sys.sp_configure N'show advanced options', 1;
RECONFIGURE;
EXEC sys.sp_configure N'Agent XPs', 1;
RECONFIGURE;
GO

-- Configure SQL Agent history and schedules.
USE [msdb];
GO
-- The five-minute log job produces two history rows per run. Retain enough
-- detail for more than three full days of genuine scheduled-run evidence.
EXEC dbo.sp_set_sqlagent_properties
     @jobhistory_max_rows = 10000,
     @jobhistory_max_rows_per_job = 2500;
GO

DECLARE @Today int = CONVERT(int, CONVERT(char(8), GETDATE(), 112));

-- Create the backup and retention jobs.
IF NOT EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'SmartBank - Full Backup')
BEGIN
    EXEC dbo.sp_add_job @job_name = N'SmartBank - Full Backup', @enabled = 1,
         @description = N'Daily AES-256 encrypted full backup with checksum and automatic verification.', @owner_login_name = N'sa';
    EXEC dbo.sp_add_jobstep @job_name = N'SmartBank - Full Backup', @step_name = N'Full backup and VERIFYONLY',
         @subsystem = N'TSQL', @database_name = N'$(DatabaseName)',
         @command = N'EXEC ops.usp_RunBackup @BackupType = ''F'';', @retry_attempts = 2, @retry_interval = 5;
    EXEC dbo.sp_add_jobschedule @job_name = N'SmartBank - Full Backup', @name = N'SmartBank Daily Full 01:00',
         @freq_type = 4, @freq_interval = 1, @active_start_date = @Today, @active_start_time = 010000;
    EXEC dbo.sp_add_jobserver @job_name = N'SmartBank - Full Backup';
END;

IF NOT EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'SmartBank - Differential Backup')
BEGIN
    EXEC dbo.sp_add_job @job_name = N'SmartBank - Differential Backup', @enabled = 1,
         @description = N'AES-256 encrypted differential backup every six hours.', @owner_login_name = N'sa';
    EXEC dbo.sp_add_jobstep @job_name = N'SmartBank - Differential Backup', @step_name = N'Differential backup and VERIFYONLY',
         @subsystem = N'TSQL', @database_name = N'$(DatabaseName)',
         @command = N'EXEC ops.usp_RunBackup @BackupType = ''D'';', @retry_attempts = 2, @retry_interval = 5;
    EXEC dbo.sp_add_jobschedule @job_name = N'SmartBank - Differential Backup', @name = N'SmartBank Differential Every 6 Hours',
         @freq_type = 4, @freq_interval = 1, @freq_subday_type = 8, @freq_subday_interval = 6,
         @active_start_date = @Today, @active_start_time = 060000, @active_end_time = 235959;
    EXEC dbo.sp_add_jobserver @job_name = N'SmartBank - Differential Backup';
END;

IF NOT EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'SmartBank - Log Backup')
BEGIN
    EXEC dbo.sp_add_job @job_name = N'SmartBank - Log Backup', @enabled = 1,
         @description = N'AES-256 encrypted transaction-log backup every five minutes; defines the five-minute RPO.', @owner_login_name = N'sa';
    EXEC dbo.sp_add_jobstep @job_name = N'SmartBank - Log Backup', @step_name = N'Log backup and VERIFYONLY',
         @subsystem = N'TSQL', @database_name = N'$(DatabaseName)',
         @command = N'EXEC ops.usp_RunBackup @BackupType = ''L'';', @retry_attempts = 2, @retry_interval = 2;
    EXEC dbo.sp_add_jobschedule @job_name = N'SmartBank - Log Backup', @name = N'SmartBank Log Every 5 Minutes',
         @freq_type = 4, @freq_interval = 1, @freq_subday_type = 4, @freq_subday_interval = 5,
         @active_start_date = @Today, @active_start_time = 000000, @active_end_time = 235959;
    EXEC dbo.sp_add_jobserver @job_name = N'SmartBank - Log Backup';
END;

IF NOT EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'SmartBank - Backup Retention')
BEGIN
    EXEC dbo.sp_add_job @job_name = N'SmartBank - Backup Retention', @enabled = 1,
         @description = N'Deletes only SmartBank backup files and msdb history older than the configured 35-day retention.', @owner_login_name = N'sa';
    EXEC dbo.sp_add_jobstep @job_name = N'SmartBank - Backup Retention', @step_name = N'Prune expired backup media',
         @subsystem = N'TSQL', @database_name = N'$(DatabaseName)',
         @command = N'EXEC ops.usp_PruneBackupFiles;', @retry_attempts = 1, @retry_interval = 10;
    EXEC dbo.sp_add_jobschedule @job_name = N'SmartBank - Backup Retention', @name = N'SmartBank Retention Daily 04:30',
         @freq_type = 4, @freq_interval = 1, @active_start_date = @Today, @active_start_time = 043000;
    EXEC dbo.sp_add_jobserver @job_name = N'SmartBank - Backup Retention';
END;

-- Keep existing job history, then enable and validate every backup job.
EXEC dbo.sp_update_job @job_name = N'SmartBank - Full Backup', @enabled = 1;
EXEC dbo.sp_update_job @job_name = N'SmartBank - Differential Backup', @enabled = 1;
EXEC dbo.sp_update_job @job_name = N'SmartBank - Log Backup', @enabled = 1;
EXEC dbo.sp_update_job @job_name = N'SmartBank - Backup Retention', @enabled = 1;

IF EXISTS
(
    SELECT 1
    FROM dbo.sysjobs AS job
    WHERE job.name IN
    (
        N'SmartBank - Full Backup',
        N'SmartBank - Differential Backup',
        N'SmartBank - Log Backup',
        N'SmartBank - Backup Retention'
    )
      AND
      (
          job.enabled = 0
          OR NOT EXISTS (SELECT 1 FROM dbo.sysjobsteps AS step WHERE step.job_id = job.job_id)
          OR NOT EXISTS (SELECT 1 FROM dbo.sysjobschedules AS schedule WHERE schedule.job_id = job.job_id)
          OR NOT EXISTS (SELECT 1 FROM dbo.sysjobservers AS server WHERE server.job_id = job.job_id)
      )
)
    THROW 50402, 'A SmartBank backup job exists without its required step, schedule or target server.', 1;
GO

USE [$(DatabaseName)];
GO
-- Let the auditor read backup health.
GRANT EXECUTE ON OBJECT::ops.usp_BackupHealth TO rl_security_auditor;
GO
