USE [master];
GO
SET NOCOUNT ON;
GO

-- Create and configure the analytics database.
IF DB_ID(N'$(AnalyticsDatabaseName)') IS NULL
    CREATE DATABASE [$(AnalyticsDatabaseName)];
GO
ALTER DATABASE [$(AnalyticsDatabaseName)] SET RECOVERY SIMPLE;
ALTER DATABASE [$(AnalyticsDatabaseName)] SET PAGE_VERIFY CHECKSUM;
GO

USE [$(AnalyticsDatabaseName)];
GO
-- Enable transparent data encryption for analytics data.
IF NOT EXISTS (SELECT 1 FROM sys.dm_database_encryption_keys WHERE database_id = DB_ID())
    CREATE DATABASE ENCRYPTION KEY WITH ALGORITHM = AES_256
        ENCRYPTION BY SERVER CERTIFICATE SmartBank_TDE_Certificate;
GO
IF NOT EXISTS
(
    SELECT 1 FROM sys.dm_database_encryption_keys
    WHERE database_id = DB_ID() AND encryption_state = 3
)
    ALTER DATABASE [$(AnalyticsDatabaseName)] SET ENCRYPTION ON;
GO

-- Create the anonymized analytics tables.
IF OBJECT_ID(N'dbo.CustomerAnon', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.CustomerAnon
    (
        CustomerToken char(16) NOT NULL CONSTRAINT PK_CustomerAnon PRIMARY KEY,
        DisplayName nvarchar(100) NOT NULL,
        SyntheticEmail varchar(254) NOT NULL,
        MaskedPhone varchar(20) NOT NULL,
        Region varchar(30) NOT NULL,
        Status varchar(12) NOT NULL,
        RefreshedAt datetime2(3) NOT NULL
    );
END;
GO

IF OBJECT_ID(N'dbo.AccountAnon', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AccountAnon
    (
        AccountToken char(16) NOT NULL CONSTRAINT PK_AccountAnon PRIMARY KEY,
        CustomerToken char(16) NOT NULL,
        AccountType varchar(20) NOT NULL,
        BalanceBand varchar(30) NOT NULL,
        Status varchar(12) NOT NULL,
        RefreshedAt datetime2(3) NOT NULL,
        CONSTRAINT FK_AccountAnon_CustomerAnon FOREIGN KEY (CustomerToken) REFERENCES dbo.CustomerAnon (CustomerToken)
    );
END;
GO

IF OBJECT_ID(N'dbo.TransactionAnon', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.TransactionAnon
    (
        TransactionToken char(16) NOT NULL CONSTRAINT PK_TransactionAnon PRIMARY KEY,
        CorrelationToken char(16) NOT NULL,
        AccountToken char(16) NOT NULL,
        MonthBucket date NOT NULL,
        AmountBand varchar(30) NOT NULL,
        Direction varchar(6) NOT NULL,
        TransactionType varchar(10) NOT NULL,
        Channel varchar(12) NOT NULL,
        RefreshedAt datetime2(3) NOT NULL,
        CONSTRAINT FK_TransactionAnon_AccountAnon FOREIGN KEY (AccountToken) REFERENCES dbo.AccountAnon (AccountToken)
    );
END;
GO

-- Refresh the anonymized analytics copy.
CREATE OR ALTER PROCEDURE dbo.usp_RefreshMaskedData
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @RefreshedAt datetime2(3) = SYSUTCDATETIME();

    CREATE TABLE #CustomerMap (CustomerID char(6) PRIMARY KEY, CustomerToken char(16) UNIQUE NOT NULL);
    CREATE TABLE #AccountMap (AccountID varchar(10) PRIMARY KEY, AccountToken char(16) UNIQUE NOT NULL);
    CREATE TABLE #CorrelationMap (CorrelationID uniqueidentifier PRIMARY KEY, CorrelationToken char(16) UNIQUE NOT NULL);

    INSERT #CustomerMap (CustomerID, CustomerToken)
        SELECT CustomerID, 'CUS-' + LEFT(REPLACE(CONVERT(char(36), NEWID()), '-', ''), 12)
        FROM [$(DatabaseName)].core.Customer;
    INSERT #AccountMap (AccountID, AccountToken)
        SELECT AccountID, 'ACC-' + LEFT(REPLACE(CONVERT(char(36), NEWID()), '-', ''), 12)
        FROM [$(DatabaseName)].core.Account;
    INSERT #CorrelationMap (CorrelationID, CorrelationToken)
        SELECT source.CorrelationID, 'COR-' + LEFT(REPLACE(CONVERT(char(36), NEWID()), '-', ''), 12)
        FROM (SELECT DISTINCT CorrelationID FROM [$(DatabaseName)].core.TransactionRecord) AS source;

    BEGIN TRANSACTION;
    DELETE dbo.TransactionAnon;
    DELETE dbo.AccountAnon;
    DELETE dbo.CustomerAnon;

    INSERT dbo.CustomerAnon
    (CustomerToken, DisplayName, SyntheticEmail, MaskedPhone, Region, Status, RefreshedAt)
    SELECT map.CustomerToken,
           N'Customer ' + RIGHT(map.CustomerToken, 4),
           'anon.' + LOWER(RIGHT(map.CustomerToken, 8)) + '@example.invalid',
           'XXX-XXX-0000',
           CASE ABS(CHECKSUM(map.CustomerToken)) % 4
                WHEN 0 THEN 'Kuala Lumpur' WHEN 1 THEN 'Petaling Jaya'
                WHEN 2 THEN 'Shah Alam' ELSE 'Cyberjaya' END,
           customer.Status,
           @RefreshedAt
    FROM [$(DatabaseName)].core.Customer AS customer
    INNER JOIN #CustomerMap AS map ON map.CustomerID = customer.CustomerID;

    INSERT dbo.AccountAnon
    (AccountToken, CustomerToken, AccountType, BalanceBand, Status, RefreshedAt)
    SELECT accountMap.AccountToken, customerMap.CustomerToken, account.AccountType,
           CASE WHEN account.Balance < 1000 THEN 'RM0-RM999'
                WHEN account.Balance < 5000 THEN 'RM1,000-RM4,999'
                WHEN account.Balance < 10000 THEN 'RM5,000-RM9,999'
                ELSE 'RM10,000+' END,
           account.Status, @RefreshedAt
    FROM [$(DatabaseName)].core.Account AS account
    INNER JOIN #AccountMap AS accountMap ON accountMap.AccountID = account.AccountID
    INNER JOIN #CustomerMap AS customerMap ON customerMap.CustomerID = account.CustomerID;

    INSERT dbo.TransactionAnon
    (TransactionToken, CorrelationToken, AccountToken, MonthBucket, AmountBand,
     Direction, TransactionType, Channel, RefreshedAt)
    SELECT 'TRN-' + LEFT(REPLACE(CONVERT(char(36), NEWID()), '-', ''), 12),
           correlationMap.CorrelationToken,
           accountMap.AccountToken,
           DATEFROMPARTS(YEAR(transactionRecord.TransDate), MONTH(transactionRecord.TransDate), 1),
           CASE WHEN transactionRecord.Amount < 100 THEN 'Below RM100'
                WHEN transactionRecord.Amount < 500 THEN 'RM100-RM499'
                WHEN transactionRecord.Amount < 1000 THEN 'RM500-RM999'
                ELSE 'RM1,000+' END,
           transactionRecord.Direction, transactionRecord.TransactionType, transactionRecord.Channel, @RefreshedAt
    FROM [$(DatabaseName)].core.TransactionRecord AS transactionRecord
    INNER JOIN #AccountMap AS accountMap ON accountMap.AccountID = transactionRecord.AccountID
    INNER JOIN #CorrelationMap AS correlationMap ON correlationMap.CorrelationID = transactionRecord.CorrelationID;

    COMMIT TRANSACTION;
END;
GO

-- Check that the analytics copy contains no direct identifiers.
CREATE OR ALTER PROCEDURE dbo.usp_StaticMaskingQualityCheck
AS
BEGIN
    SET NOCOUNT ON;
    SELECT (SELECT COUNT(*) FROM dbo.CustomerAnon) AS CustomerRows,
           (SELECT COUNT(*) FROM dbo.AccountAnon) AS AccountRows,
           (SELECT COUNT(*) FROM dbo.TransactionAnon) AS TransactionRows,
           (SELECT COUNT(*) FROM dbo.CustomerAnon WHERE SyntheticEmail NOT LIKE '%@example.invalid') AS UnsafeEmailRows,
           (SELECT COUNT(*) FROM dbo.CustomerAnon WHERE MaskedPhone <> 'XXX-XXX-0000') AS UnsafePhoneRows,
           (SELECT COUNT(*) FROM dbo.CustomerAnon WHERE DisplayName NOT LIKE 'Customer %') AS UnsafeNameRows;
END;
GO

-- Populate the analytics copy immediately.
EXEC dbo.usp_RefreshMaskedData;
GO

-- Give the auditor read-only analytics access.
IF DATABASE_PRINCIPAL_ID(N'rl_analytics_reader') IS NULL CREATE ROLE rl_analytics_reader AUTHORIZATION dbo;
IF SUSER_ID(N'sb_auditor_noor') IS NOT NULL AND USER_ID(N'sb_auditor_noor') IS NULL
    CREATE USER [sb_auditor_noor] FOR LOGIN [sb_auditor_noor];
IF USER_ID(N'sb_auditor_noor') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.database_role_members WHERE role_principal_id = DATABASE_PRINCIPAL_ID(N'rl_analytics_reader') AND member_principal_id = USER_ID(N'sb_auditor_noor'))
    ALTER ROLE rl_analytics_reader ADD MEMBER [sb_auditor_noor];
GRANT SELECT ON SCHEMA::dbo TO rl_analytics_reader;
GRANT EXECUTE ON OBJECT::dbo.usp_StaticMaskingQualityCheck TO rl_analytics_reader;
REVOKE CONTROL ON SCHEMA::dbo FROM rl_analytics_reader;
DENY INSERT, UPDATE, DELETE, ALTER ON SCHEMA::dbo TO rl_analytics_reader;
GO

-- Schedule the nightly refresh.
USE [msdb];
GO
DECLARE @Today int = CONVERT(int, CONVERT(char(8), GETDATE(), 112));
IF NOT EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'SmartBank - Static Mask Refresh')
BEGIN
    EXEC dbo.sp_add_job @job_name = N'SmartBank - Static Mask Refresh', @enabled = 1,
         @description = N'Nightly irreversible static masking and anonymization refresh for non-production analytics.', @owner_login_name = N'sa';
    EXEC dbo.sp_add_jobstep @job_name = N'SmartBank - Static Mask Refresh', @step_name = N'Refresh anonymized analytics copy',
         @subsystem = N'TSQL', @database_name = N'$(AnalyticsDatabaseName)',
         @command = N'EXEC dbo.usp_RefreshMaskedData; EXEC dbo.usp_StaticMaskingQualityCheck;', @retry_attempts = 2, @retry_interval = 5;
    EXEC dbo.sp_add_jobschedule @job_name = N'SmartBank - Static Mask Refresh', @name = N'SmartBank Static Mask Daily 03:00',
         @freq_type = 4, @freq_interval = 1, @active_start_date = @Today, @active_start_time = 030000;
    EXEC dbo.sp_add_jobserver @job_name = N'SmartBank - Static Mask Refresh';
END;

EXEC dbo.sp_update_job @job_name = N'SmartBank - Static Mask Refresh', @enabled = 1;

IF EXISTS
(
    SELECT 1
    FROM dbo.sysjobs AS job
    WHERE job.name = N'SmartBank - Static Mask Refresh'
      AND
      (
          job.enabled = 0
          OR NOT EXISTS (SELECT 1 FROM dbo.sysjobsteps AS step WHERE step.job_id = job.job_id)
          OR NOT EXISTS (SELECT 1 FROM dbo.sysjobschedules AS schedule WHERE schedule.job_id = job.job_id)
          OR NOT EXISTS (SELECT 1 FROM dbo.sysjobservers AS server WHERE server.job_id = job.job_id)
      )
)
    THROW 50403, 'The SmartBank static-mask job exists without its required step, schedule or target server.', 1;
GO
