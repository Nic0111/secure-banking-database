USE [master];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- Create the server-side folders used by the deployment.
IF NOT EXISTS
(
    SELECT 1 FROM sys.dm_os_file_exists(N'$(BackupDirectory)')
    WHERE file_is_a_directory = 1
)
    EXEC master.dbo.xp_create_subdir N'$(BackupDirectory)';

IF NOT EXISTS
(
    SELECT 1 FROM sys.dm_os_file_exists(N'$(AuditDirectory)')
    WHERE file_is_a_directory = 1
)
    EXEC master.dbo.xp_create_subdir N'$(AuditDirectory)';

IF NOT EXISTS
(
    SELECT 1 FROM sys.dm_os_file_exists(N'$(CertificateDirectory)')
    WHERE file_is_a_directory = 1
)
    EXEC master.dbo.xp_create_subdir N'$(CertificateDirectory)';
GO

-- Create the server master key and backup certificates.
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

-- Export the server certificates once for recovery.
DECLARE @CertificatePath nvarchar(4000) = N'$(CertificateDirectory)$(PathSeparator)SmartBank_TDE_Certificate.cer';
DECLARE @PrivateKeyPath nvarchar(4000) = N'$(CertificateDirectory)$(PathSeparator)SmartBank_TDE_Certificate.pvk';
DECLARE @FileExists int;
DECLARE @BackupCertificateSql nvarchar(max);

SET @FileExists = 0;
EXEC master.dbo.xp_fileexist @CertificatePath, @FileExists OUTPUT;
IF @FileExists = 0
BEGIN
    SET @BackupCertificateSql =
        N'BACKUP CERTIFICATE SmartBank_TDE_Certificate TO FILE = N''' + REPLACE(@CertificatePath, N'''', N'''''') +
        N''' WITH PRIVATE KEY (FILE = N''' + REPLACE(@PrivateKeyPath, N'''', N'''''') +
        N''', ENCRYPTION BY PASSWORD = N''' + REPLACE(N'$(CertificateBackupPassword)', N'''', N'''''') + N''');';
    EXEC sys.sp_executesql @BackupCertificateSql;
END;

SET @CertificatePath = N'$(CertificateDirectory)$(PathSeparator)SmartBank_Backup_Certificate.cer';
SET @PrivateKeyPath = N'$(CertificateDirectory)$(PathSeparator)SmartBank_Backup_Certificate.pvk';
SET @FileExists = 0;
EXEC master.dbo.xp_fileexist @CertificatePath, @FileExists OUTPUT;
IF @FileExists = 0
BEGIN
    SET @BackupCertificateSql =
        N'BACKUP CERTIFICATE SmartBank_Backup_Certificate TO FILE = N''' + REPLACE(@CertificatePath, N'''', N'''''') +
        N''' WITH PRIVATE KEY (FILE = N''' + REPLACE(@PrivateKeyPath, N'''', N'''''') +
        N''', ENCRYPTION BY PASSWORD = N''' + REPLACE(N'$(CertificateBackupPassword)', N'''', N'''''') + N''');';
    EXEC sys.sp_executesql @BackupCertificateSql;
END;
GO

-- Create and configure the main database.
IF DB_ID(N'$(DatabaseName)') IS NULL
    CREATE DATABASE [$(DatabaseName)];
GO

ALTER DATABASE [$(DatabaseName)] SET RECOVERY FULL;
ALTER DATABASE [$(DatabaseName)] SET PAGE_VERIFY CHECKSUM;
ALTER DATABASE [$(DatabaseName)] SET AUTO_CLOSE OFF;
ALTER DATABASE [$(DatabaseName)] SET AUTO_SHRINK OFF;
GO

USE [$(DatabaseName)];
GO
-- Enable transparent data encryption.
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

-- Create the application schemas.
IF SCHEMA_ID(N'core') IS NULL EXEC(N'CREATE SCHEMA core AUTHORIZATION dbo;');
IF SCHEMA_ID(N'history') IS NULL EXEC(N'CREATE SCHEMA history AUTHORIZATION dbo;');
IF SCHEMA_ID(N'sec') IS NULL EXEC(N'CREATE SCHEMA sec AUTHORIZATION dbo;');
IF SCHEMA_ID(N'api') IS NULL EXEC(N'CREATE SCHEMA api AUTHORIZATION dbo;');
IF SCHEMA_ID(N'audit') IS NULL EXEC(N'CREATE SCHEMA audit AUTHORIZATION dbo;');
IF SCHEMA_ID(N'ops') IS NULL EXEC(N'CREATE SCHEMA ops AUTHORIZATION dbo;');
IF SCHEMA_ID(N'demo') IS NULL EXEC(N'CREATE SCHEMA demo AUTHORIZATION dbo;');
GO

-- Store the deployment settings used by later scripts.
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
