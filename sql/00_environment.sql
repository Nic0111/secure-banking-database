USE [master];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DECLARE @ProductMajorVersion int = TRY_CONVERT(int, SERVERPROPERTY('ProductMajorVersion'));
DECLARE @Edition nvarchar(128) = CONVERT(nvarchar(128), SERVERPROPERTY('Edition'));

IF @ProductMajorVersion < 16
    THROW 50000, 'SmartBank requires SQL Server 2022 (16.x) or later.', 1;

IF @Edition LIKE N'%Express%'
    THROW 50001, 'SQL Server Express is unsupported: SQL Agent and encrypted backup creation are required.', 1;

IF N'$(BackupDirectory)' LIKE N'CHANGE_ME%'
   OR N'$(AuditDirectory)' LIKE N'CHANGE_ME%'
   OR N'$(CertificateDirectory)' LIKE N'CHANGE_ME%'
   OR N'$(MasterKeyPassword)' LIKE N'CHANGE_ME%'
   OR N'$(CertificateBackupPassword)' LIKE N'CHANGE_ME%'
    THROW 50002, 'Provide the required SQLCMD directories and key passwords with -v.', 1;

IF N'$(DemoTransactionPin)' = N'000000'
   OR LEN(N'$(DemoTransactionPin)') <> 6
   OR N'$(DemoTransactionPin)' LIKE N'%[^0-9]%'
    THROW 50006, 'Provide a non-default six-digit DemoTransactionPin with -v.', 1;

DECLARE @Exists int;
SELECT @Exists = file_is_a_directory FROM sys.dm_os_file_exists(N'$(BackupDirectory)');
IF ISNULL(@Exists, 0) <> 1
    EXEC master.dbo.xp_create_subdir N'$(BackupDirectory)';

SET @Exists = 0;
SELECT @Exists = file_is_a_directory FROM sys.dm_os_file_exists(N'$(AuditDirectory)');
IF ISNULL(@Exists, 0) <> 1
    EXEC master.dbo.xp_create_subdir N'$(AuditDirectory)';

SET @Exists = 0;
SELECT @Exists = file_is_a_directory FROM sys.dm_os_file_exists(N'$(CertificateDirectory)');
IF ISNULL(@Exists, 0) <> 1
    EXEC master.dbo.xp_create_subdir N'$(CertificateDirectory)';

SET @Exists = 0;
SELECT @Exists = file_is_a_directory FROM sys.dm_os_file_exists(N'$(BackupDirectory)');
IF ISNULL(@Exists, 0) <> 1
    THROW 50003, 'BackupDirectory could not be created or accessed by the SQL Server service account.', 1;

SET @Exists = 0;
SELECT @Exists = file_is_a_directory FROM sys.dm_os_file_exists(N'$(AuditDirectory)');
IF ISNULL(@Exists, 0) <> 1
    THROW 50004, 'AuditDirectory could not be created or accessed by the SQL Server service account.', 1;

SET @Exists = 0;
SELECT @Exists = file_is_a_directory FROM sys.dm_os_file_exists(N'$(CertificateDirectory)');
IF ISNULL(@Exists, 0) <> 1
    THROW 50005, 'CertificateDirectory could not be created or accessed by the SQL Server service account.', 1;
GO

IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
BEGIN
    DECLARE @CreateMasterKey nvarchar(max) =
        N'CREATE MASTER KEY ENCRYPTION BY PASSWORD = N''' +
        REPLACE(N'$(MasterKeyPassword)', N'''', N'''''') + N''';';
    EXEC sys.sp_executesql @CreateMasterKey;
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'SmartBank_TDE_Certificate')
    CREATE CERTIFICATE SmartBank_TDE_Certificate
        WITH SUBJECT = N'SmartBank TDE database encryption key protector',
             EXPIRY_DATE = '20361231';
GO

IF NOT EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'SmartBank_Backup_Certificate')
    CREATE CERTIFICATE SmartBank_Backup_Certificate
        WITH SUBJECT = N'SmartBank AES-256 backup encryption certificate',
             EXPIRY_DATE = '20361231';
GO

DECLARE @CertificateDirectory nvarchar(4000) = N'$(CertificateDirectory)';
DECLARE @Separator nchar(1) = N'$(PathSeparator)';
DECLARE @PrivateKeyPassword nvarchar(4000) = N'$(CertificateBackupPassword)';
DECLARE @CertificatePath nvarchar(4000);
DECLARE @PrivateKeyPath nvarchar(4000);
DECLARE @FileExists int;
DECLARE @BackupCertificateSql nvarchar(max);

SET @CertificatePath = @CertificateDirectory + @Separator + N'SmartBank_TDE_Certificate.cer';
SET @PrivateKeyPath = @CertificateDirectory + @Separator + N'SmartBank_TDE_Certificate.pvk';
SET @FileExists = 0;
EXEC master.dbo.xp_fileexist @CertificatePath, @FileExists OUTPUT;
IF @FileExists = 0
BEGIN
    SET @BackupCertificateSql =
        N'BACKUP CERTIFICATE SmartBank_TDE_Certificate TO FILE = N''' + REPLACE(@CertificatePath, N'''', N'''''') +
        N''' WITH PRIVATE KEY (FILE = N''' + REPLACE(@PrivateKeyPath, N'''', N'''''') +
        N''', ENCRYPTION BY PASSWORD = N''' + REPLACE(@PrivateKeyPassword, N'''', N'''''') + N''');';
    EXEC sys.sp_executesql @BackupCertificateSql;
END;

SET @CertificatePath = @CertificateDirectory + @Separator + N'SmartBank_Backup_Certificate.cer';
SET @PrivateKeyPath = @CertificateDirectory + @Separator + N'SmartBank_Backup_Certificate.pvk';
SET @FileExists = 0;
EXEC master.dbo.xp_fileexist @CertificatePath, @FileExists OUTPUT;
IF @FileExists = 0
BEGIN
    SET @BackupCertificateSql =
        N'BACKUP CERTIFICATE SmartBank_Backup_Certificate TO FILE = N''' + REPLACE(@CertificatePath, N'''', N'''''') +
        N''' WITH PRIVATE KEY (FILE = N''' + REPLACE(@PrivateKeyPath, N'''', N'''''') +
        N''', ENCRYPTION BY PASSWORD = N''' + REPLACE(@PrivateKeyPassword, N'''', N'''''') + N''');';
    EXEC sys.sp_executesql @BackupCertificateSql;
END;
GO

IF DB_ID(N'$(DatabaseName)') IS NULL
BEGIN
    DECLARE @CreateDatabase nvarchar(max) = N'CREATE DATABASE ' + QUOTENAME(N'$(DatabaseName)') + N';';
    EXEC sys.sp_executesql @CreateDatabase;
END;
GO

ALTER DATABASE [$(DatabaseName)] SET RECOVERY FULL;
ALTER DATABASE [$(DatabaseName)] SET PAGE_VERIFY CHECKSUM;
ALTER DATABASE [$(DatabaseName)] SET AUTO_CLOSE OFF;
ALTER DATABASE [$(DatabaseName)] SET AUTO_SHRINK OFF;
GO

USE [$(DatabaseName)];
GO
IF NOT EXISTS (SELECT 1 FROM sys.dm_database_encryption_keys WHERE database_id = DB_ID())
    CREATE DATABASE ENCRYPTION KEY
        WITH ALGORITHM = AES_256
        ENCRYPTION BY SERVER CERTIFICATE SmartBank_TDE_Certificate;
GO
IF NOT EXISTS
(
    SELECT 1 FROM sys.dm_database_encryption_keys
    WHERE database_id = DB_ID() AND encryption_state = 3
)
    ALTER DATABASE [$(DatabaseName)] SET ENCRYPTION ON;
GO

IF SCHEMA_ID(N'core') IS NULL EXEC(N'CREATE SCHEMA core AUTHORIZATION dbo;');
IF SCHEMA_ID(N'history') IS NULL EXEC(N'CREATE SCHEMA history AUTHORIZATION dbo;');
IF SCHEMA_ID(N'sec') IS NULL EXEC(N'CREATE SCHEMA sec AUTHORIZATION dbo;');
IF SCHEMA_ID(N'api') IS NULL EXEC(N'CREATE SCHEMA api AUTHORIZATION dbo;');
IF SCHEMA_ID(N'audit') IS NULL EXEC(N'CREATE SCHEMA audit AUTHORIZATION dbo;');
IF SCHEMA_ID(N'ops') IS NULL EXEC(N'CREATE SCHEMA ops AUTHORIZATION dbo;');
IF SCHEMA_ID(N'demo') IS NULL EXEC(N'CREATE SCHEMA demo AUTHORIZATION dbo;');
GO

IF OBJECT_ID(N'ops.Configuration', N'U') IS NULL
BEGIN
    CREATE TABLE ops.Configuration
    (
        ConfigKey sysname NOT NULL CONSTRAINT PK_Configuration PRIMARY KEY,
        ConfigValue nvarchar(4000) NOT NULL,
        IsSensitive bit NOT NULL CONSTRAINT DF_Configuration_IsSensitive DEFAULT (0),
        UpdatedAt datetime2(3) NOT NULL CONSTRAINT DF_Configuration_UpdatedAt DEFAULT (SYSUTCDATETIME())
    );
END;
GO

MERGE ops.Configuration AS target
USING (VALUES
    (N'BackupDirectory', N'$(BackupDirectory)', CONVERT(bit, 0)),
    (N'AuditDirectory', N'$(AuditDirectory)', CONVERT(bit, 0)),
    (N'CertificateDirectory', N'$(CertificateDirectory)', CONVERT(bit, 0)),
    (N'PathSeparator', N'$(PathSeparator)', CONVERT(bit, 0)),
    (N'RecoveryPointObjectiveMinutes', N'5', CONVERT(bit, 0)),
    (N'BackupRetentionDays', N'35', CONVERT(bit, 0))
) AS source (ConfigKey, ConfigValue, IsSensitive)
ON target.ConfigKey = source.ConfigKey
WHEN MATCHED THEN
    UPDATE SET ConfigValue = source.ConfigValue,
               IsSensitive = source.IsSensitive,
               UpdatedAt = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (ConfigKey, ConfigValue, IsSensitive)
    VALUES (source.ConfigKey, source.ConfigValue, source.IsSensitive);
GO
