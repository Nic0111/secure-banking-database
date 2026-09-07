-- Reset the SmartBank coursework databases before a fresh deployment.
-- Removes the SmartBank databases, Agent jobs, and demonstration logins.
-- Server certificates, the server audit, and backup history are retained.
USE [msdb];
GO

-- Remove SmartBank Agent jobs and their execution history.
IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'SmartBank - Full Backup')
    EXEC dbo.sp_delete_job @job_name = N'SmartBank - Full Backup', @delete_unused_schedule = 1, @delete_history = 1;
IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'SmartBank - Differential Backup')
    EXEC dbo.sp_delete_job @job_name = N'SmartBank - Differential Backup', @delete_unused_schedule = 1, @delete_history = 1;
IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'SmartBank - Log Backup')
    EXEC dbo.sp_delete_job @job_name = N'SmartBank - Log Backup', @delete_unused_schedule = 1, @delete_history = 1;
IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'SmartBank - Backup Retention')
    EXEC dbo.sp_delete_job @job_name = N'SmartBank - Backup Retention', @delete_unused_schedule = 1, @delete_history = 1;
IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'SmartBank - Static Mask Refresh')
    EXEC dbo.sp_delete_job @job_name = N'SmartBank - Static Mask Refresh', @delete_unused_schedule = 1, @delete_history = 1;
GO

USE [master];
GO

-- Remove recovery copies before the main databases.
IF DB_ID(N'SmartBankDB_RestoreValidation') IS NOT NULL
BEGIN
    ALTER DATABASE [SmartBankDB_RestoreValidation] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [SmartBankDB_RestoreValidation];
END;

IF DB_ID(N'SmartBankDB_PITR') IS NOT NULL
BEGIN
    ALTER DATABASE [SmartBankDB_PITR] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [SmartBankDB_PITR];
END;

IF DB_ID(N'SmartBankDB_RestoreDemo') IS NOT NULL
BEGIN
    ALTER DATABASE [SmartBankDB_RestoreDemo] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [SmartBankDB_RestoreDemo];
END;
GO

-- Remove the analytics and operational databases.
IF DB_ID(N'SmartBankAnalyticsDB') IS NOT NULL
BEGIN
    ALTER DATABASE [SmartBankAnalyticsDB] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [SmartBankAnalyticsDB];
END;

IF DB_ID(N'SmartBankDB') IS NOT NULL
BEGIN
    ALTER DATABASE [SmartBankDB] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [SmartBankDB];
END;
GO

-- Remove the demonstration server logins and auditor role.
IF SUSER_ID(N'sb_dba_aisha') IS NOT NULL DROP LOGIN [sb_dba_aisha];
IF SUSER_ID(N'sb_dba_kavitha') IS NOT NULL DROP LOGIN [sb_dba_kavitha];
IF SUSER_ID(N'sb_manager_daniel') IS NOT NULL DROP LOGIN [sb_manager_daniel];
IF SUSER_ID(N'sb_manager_siti') IS NOT NULL DROP LOGIN [sb_manager_siti];
IF SUSER_ID(N'sb_officer_farid') IS NOT NULL DROP LOGIN [sb_officer_farid];
IF SUSER_ID(N'sb_officer_priya') IS NOT NULL DROP LOGIN [sb_officer_priya];
IF SUSER_ID(N'sb_customer_amelia') IS NOT NULL DROP LOGIN [sb_customer_amelia];
IF SUSER_ID(N'sb_customer_hafiz') IS NOT NULL DROP LOGIN [sb_customer_hafiz];
IF SUSER_ID(N'sb_auditor_noor') IS NOT NULL DROP LOGIN [sb_auditor_noor];
IF SUSER_ID(N'SmartBankAuditReader') IS NOT NULL DROP SERVER ROLE [SmartBankAuditReader];
GO
