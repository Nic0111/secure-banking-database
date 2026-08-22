:on error exit
/*
RECOVERY MODULE:
Operation - Cross-instance encrypted full restore

PURPOSE:
Import the private certificate material required by TDE and explicit backup
encryption, verify the selected media, and restore it to a separate database.

RUN AS:
sa or another sysadmin on the target SQL Server instance, in SQLCMD mode.

PRECONDITIONS:
Supply every SQLCMD variable documented in sql/recovery/README.md. The backup and
certificate files must be readable by the target SQL Server service account.

DATABASE CHANGES:
May create the master database master key and import two private certificates.
Creates only the supplied validation database; never overwrites an existing one.

PASS CONDITION:
RESTORE VERIFYONLY succeeds, the target database is ONLINE, its database master
key is re-protected by the target service master key, and TDE remains enabled.
*/
USE [master];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

:setvar TargetDatabaseName "SmartBankDB_RestoreDemo"
:setvar SourceFullBackupFile "C:\Program Files\Microsoft SQL Server\MSSQL17.DBS_DEMO\MSSQL\Backup\SmartBankRestore\SmartBankDB_FULL_20260823_010000.bak"
:setvar TargetDataFile "C:\Program Files\Microsoft SQL Server\MSSQL17.DBS_DEMO\MSSQL\DATA\SmartBankDB_RestoreDemo.mdf"
:setvar TargetLogFile "C:\Program Files\Microsoft SQL Server\MSSQL17.DBS_DEMO\MSSQL\DATA\SmartBankDB_RestoreDemo_log.ldf"
:setvar TargetCertificateDirectory "C:\Program Files\Microsoft SQL Server\MSSQL17.DBS_DEMO\MSSQL\Backup\SmartBankRestore\Keys"
:setvar PathSeparator "\"
:setvar TargetMasterKeyPassword "SBank!MasterKey_2026#LocalOnly"
:setvar CertificateBackupPassword "SBank!Certificate_2026#LocalOnly"
:setvar RestoredDatabaseMasterKeyPassword "SBank!MasterKey_2026#LocalOnly"

DECLARE @TargetDatabase sysname = N'$(TargetDatabaseName)';
DECLARE @BackupFile nvarchar(4000) = N'$(SourceFullBackupFile)';
DECLARE @TargetDataFile nvarchar(4000) = N'$(TargetDataFile)';
DECLARE @TargetLogFile nvarchar(4000) = N'$(TargetLogFile)';
DECLARE @CertificateDirectory nvarchar(4000) = N'$(TargetCertificateDirectory)';
DECLARE @Separator nvarchar(2) = N'$(PathSeparator)';
DECLARE @TargetMasterKeyPassword nvarchar(4000) = N'$(TargetMasterKeyPassword)';
DECLARE @CertificateBackupPassword nvarchar(4000) = N'$(CertificateBackupPassword)';
DECLARE @RestoredDatabaseMasterKeyPassword nvarchar(4000) = N'$(RestoredDatabaseMasterKeyPassword)';
DECLARE @StartedAtUtc datetime2(3) = SYSUTCDATETIME();

IF NULLIF(@TargetDatabase, N'') IS NULL OR @TargetDatabase NOT LIKE N'SmartBankDB[_]%'
    THROW 52001, 'TargetDatabaseName must be a separate name beginning with SmartBankDB_.', 1;
IF @TargetDatabase IN (N'SmartBankDB', N'SmartBankAnalyticsDB', N'master', N'model', N'msdb', N'tempdb')
    THROW 52002, 'The source, analytics and system databases are protected restore targets.', 1;
IF DB_ID(@TargetDatabase) IS NOT NULL
    THROW 52003, 'The target database already exists. Use a unique name or the explicit cleanup utility.', 1;
IF NULLIF(@BackupFile, N'') IS NULL OR NULLIF(@TargetDataFile, N'') IS NULL
   OR NULLIF(@TargetLogFile, N'') IS NULL OR NULLIF(@CertificateDirectory, N'') IS NULL
   OR NULLIF(@TargetMasterKeyPassword, N'') IS NULL OR NULLIF(@CertificateBackupPassword, N'') IS NULL
   OR NULLIF(@RestoredDatabaseMasterKeyPassword, N'') IS NULL
    THROW 52004, 'All paths and recovery secrets must be supplied through SQLCMD variables.', 1;

DECLARE @TdeCertificateFile nvarchar(4000) = @CertificateDirectory + @Separator + N'SmartBank_TDE_Certificate.cer';
DECLARE @TdePrivateKeyFile nvarchar(4000) = @CertificateDirectory + @Separator + N'SmartBank_TDE_Certificate.pvk';
DECLARE @BackupCertificateFile nvarchar(4000) = @CertificateDirectory + @Separator + N'SmartBank_Backup_Certificate.cer';
DECLARE @BackupPrivateKeyFile nvarchar(4000) = @CertificateDirectory + @Separator + N'SmartBank_Backup_Certificate.pvk';
DECLARE @Exists int;

SET @Exists = 0;
EXEC master.dbo.xp_fileexist @BackupFile, @Exists OUTPUT;
IF @Exists <> 1 THROW 52005, 'The SQL Server service account cannot read SourceFullBackupFile.', 1;
SET @Exists = 0;
EXEC master.dbo.xp_fileexist @TdeCertificateFile, @Exists OUTPUT;
IF @Exists <> 1 THROW 52006, 'SmartBank_TDE_Certificate.cer is missing or unreadable.', 1;
SET @Exists = 0;
EXEC master.dbo.xp_fileexist @TdePrivateKeyFile, @Exists OUTPUT;
IF @Exists <> 1 THROW 52007, 'SmartBank_TDE_Certificate.pvk is missing or unreadable.', 1;
SET @Exists = 0;
EXEC master.dbo.xp_fileexist @BackupCertificateFile, @Exists OUTPUT;
IF @Exists <> 1 THROW 52008, 'SmartBank_Backup_Certificate.cer is missing or unreadable.', 1;
SET @Exists = 0;
EXEC master.dbo.xp_fileexist @BackupPrivateKeyFile, @Exists OUTPUT;
IF @Exists <> 1 THROW 52009, 'SmartBank_Backup_Certificate.pvk is missing or unreadable.', 1;

DECLARE @Sql nvarchar(max);
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
BEGIN
    SET @Sql = N'CREATE MASTER KEY ENCRYPTION BY PASSWORD = N''' +
               REPLACE(@TargetMasterKeyPassword, N'''', N'''''') + N''';';
    EXEC sys.sp_executesql @Sql;
END;

IF NOT EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'SmartBank_TDE_Certificate')
BEGIN
    SET @Sql = N'CREATE CERTIFICATE SmartBank_TDE_Certificate FROM FILE = N''' +
               REPLACE(@TdeCertificateFile, N'''', N'''''') +
               N''' WITH PRIVATE KEY (FILE = N''' + REPLACE(@TdePrivateKeyFile, N'''', N'''''') +
               N''', DECRYPTION BY PASSWORD = N''' + REPLACE(@CertificateBackupPassword, N'''', N'''''') + N''');';
    EXEC sys.sp_executesql @Sql;
END;
IF EXISTS
(
    SELECT 1 FROM sys.certificates
    WHERE name = N'SmartBank_TDE_Certificate' AND pvt_key_encryption_type_desc = N'NO_PRIVATE_KEY'
)
    THROW 52010, 'SmartBank_TDE_Certificate exists without its private key.', 1;

IF NOT EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'SmartBank_Backup_Certificate')
BEGIN
    SET @Sql = N'CREATE CERTIFICATE SmartBank_Backup_Certificate FROM FILE = N''' +
               REPLACE(@BackupCertificateFile, N'''', N'''''') +
               N''' WITH PRIVATE KEY (FILE = N''' + REPLACE(@BackupPrivateKeyFile, N'''', N'''''') +
               N''', DECRYPTION BY PASSWORD = N''' + REPLACE(@CertificateBackupPassword, N'''', N'''''') + N''');';
    EXEC sys.sp_executesql @Sql;
END;
IF EXISTS
(
    SELECT 1 FROM sys.certificates
    WHERE name = N'SmartBank_Backup_Certificate' AND pvt_key_encryption_type_desc = N'NO_PRIVATE_KEY'
)
    THROW 52011, 'SmartBank_Backup_Certificate exists without its private key.', 1;

RESTORE VERIFYONLY FROM DISK = @BackupFile WITH CHECKSUM;
RESTORE FILELISTONLY FROM DISK = @BackupFile;

-- The source implementation creates one data file and one log file with these
-- stable logical names. MOVE redirects them without using WITH REPLACE.
SET @Sql = N'RESTORE DATABASE ' + QUOTENAME(@TargetDatabase) + N'
             FROM DISK = @BackupFile
             WITH MOVE N''SmartBankDB'' TO @TargetDataFile,
                  MOVE N''SmartBankDB_log'' TO @TargetLogFile,
                  CHECKSUM, RECOVERY, STATS = 10;';
EXEC sys.sp_executesql @Sql,
     N'@BackupFile nvarchar(4000), @TargetDataFile nvarchar(4000), @TargetLogFile nvarchar(4000)',
     @BackupFile, @TargetDataFile, @TargetLogFile;

SET @Sql = N'USE ' + QUOTENAME(@TargetDatabase) + N';
             OPEN MASTER KEY DECRYPTION BY PASSWORD = N''' +
             REPLACE(@RestoredDatabaseMasterKeyPassword, N'''', N'''''') + N''';
             ALTER MASTER KEY ADD ENCRYPTION BY SERVICE MASTER KEY;
             CLOSE MASTER KEY;';
EXEC sys.sp_executesql @Sql;

IF (SELECT state_desc FROM sys.databases WHERE name = @TargetDatabase) <> N'ONLINE'
    THROW 52012, 'The restored validation database is not ONLINE.', 1;
IF NOT EXISTS
(
    SELECT 1 FROM sys.dm_database_encryption_keys
    WHERE database_id = DB_ID(@TargetDatabase)
      AND encryption_state = 3 AND key_algorithm = N'AES' AND key_length = 256
)
    THROW 52013, 'The restored validation database is not fully TDE-encrypted with AES-256.', 1;

SELECT N'PASS' AS OperationResult,
       @TargetDatabase AS RestoredDatabase,
       @BackupFile AS BackupFile,
       @StartedAtUtc AS StartedAtUtc,
       SYSUTCDATETIME() AS FinishedAtUtc,
       DATEDIFF(SECOND, @StartedAtUtc, SYSUTCDATETIME()) AS RestoreDurationSeconds,
       databaseInfo.state_desc AS DatabaseState,
       encryption.encryption_state,
       encryption.encryption_state_desc,
       encryption.key_algorithm,
       encryption.key_length
FROM sys.databases AS databaseInfo
LEFT JOIN sys.dm_database_encryption_keys AS encryption
    ON encryption.database_id = databaseInfo.database_id
WHERE databaseInfo.name = @TargetDatabase;
GO
