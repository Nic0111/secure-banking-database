:on error exit
-- Supply every value with sqlcmd -v. In-script defaults would override -v values.

USE [master];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF DB_ID(N'$(TargetDatabaseName)') IS NOT NULL
    THROW 52000, 'TargetDatabaseName already exists. Use a unique name or explicitly remove the old demonstration database.', 1;
IF N'$(SourceFullBackupFile)' LIKE N'CHANGE_ME%' OR N'$(TargetDataFile)' LIKE N'CHANGE_ME%'
   OR N'$(TargetLogFile)' LIKE N'CHANGE_ME%' OR N'$(TargetCertificateDirectory)' LIKE N'CHANGE_ME%'
   OR N'$(TargetMasterKeyPassword)' LIKE N'CHANGE_ME%'
   OR N'$(CertificateBackupPassword)' LIKE N'CHANGE_ME%'
   OR N'$(RestoredDatabaseMasterKeyPassword)' LIKE N'CHANGE_ME%'
    THROW 52001, 'Supply the target instance file and certificate paths through SQLCMD variables.', 1;
GO

IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
BEGIN
    DECLARE @CreateTargetMasterKey nvarchar(max) = N'CREATE MASTER KEY ENCRYPTION BY PASSWORD = N''' +
        REPLACE(N'$(TargetMasterKeyPassword)', N'''', N'''''') + N''';';
    EXEC sys.sp_executesql @CreateTargetMasterKey;
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'SmartBank_TDE_Certificate')
BEGIN
    DECLARE @ImportTdeCertificate nvarchar(max) =
        N'CREATE CERTIFICATE SmartBank_TDE_Certificate FROM FILE = N''' +
        REPLACE(N'$(TargetCertificateDirectory)$(PathSeparator)SmartBank_TDE_Certificate.cer', N'''', N'''''') +
        N''' WITH PRIVATE KEY (FILE = N''' +
        REPLACE(N'$(TargetCertificateDirectory)$(PathSeparator)SmartBank_TDE_Certificate.pvk', N'''', N'''''') +
        N''', DECRYPTION BY PASSWORD = N''' + REPLACE(N'$(CertificateBackupPassword)', N'''', N'''''') + N''');';
    EXEC sys.sp_executesql @ImportTdeCertificate;
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'SmartBank_Backup_Certificate')
BEGIN
    DECLARE @ImportBackupCertificate nvarchar(max) =
        N'CREATE CERTIFICATE SmartBank_Backup_Certificate FROM FILE = N''' +
        REPLACE(N'$(TargetCertificateDirectory)$(PathSeparator)SmartBank_Backup_Certificate.cer', N'''', N'''''') +
        N''' WITH PRIVATE KEY (FILE = N''' +
        REPLACE(N'$(TargetCertificateDirectory)$(PathSeparator)SmartBank_Backup_Certificate.pvk', N'''', N'''''') +
        N''', DECRYPTION BY PASSWORD = N''' + REPLACE(N'$(CertificateBackupPassword)', N'''', N'''''') + N''');';
    EXEC sys.sp_executesql @ImportBackupCertificate;
END;
GO

RESTORE VERIFYONLY FROM DISK = N'$(SourceFullBackupFile)' WITH CHECKSUM;
RESTORE FILELISTONLY FROM DISK = N'$(SourceFullBackupFile)';
GO

RESTORE DATABASE [$(TargetDatabaseName)]
FROM DISK = N'$(SourceFullBackupFile)'
WITH MOVE N'SmartBankDB' TO N'$(TargetDataFile)',
     MOVE N'SmartBankDB_log' TO N'$(TargetLogFile)',
     RECOVERY, STATS = 10;
GO

USE [$(TargetDatabaseName)];
GO
DECLARE @OpenRestoredMasterKey nvarchar(max) = N'OPEN MASTER KEY DECRYPTION BY PASSWORD = N''' +
    REPLACE(N'$(RestoredDatabaseMasterKeyPassword)', N'''', N'''''') + N''';
    ALTER MASTER KEY ADD ENCRYPTION BY SERVICE MASTER KEY;';
EXEC sys.sp_executesql @OpenRestoredMasterKey;
CLOSE MASTER KEY;
GO

SELECT N'Encrypted cross-instance restore succeeded' AS Result,
       (SELECT COUNT(*) FROM core.Staff) AS StaffRows,
       (SELECT COUNT(*) FROM core.Customer) AS CustomerRows,
       (SELECT COUNT(*) FROM core.Account) AS AccountRows,
       (SELECT COUNT(*) FROM core.TransactionRecord) AS TransactionRows;

SELECT DB_NAME(database_id) AS DatabaseName, encryption_state_desc,
       key_algorithm, key_length
FROM sys.dm_database_encryption_keys
WHERE database_id = DB_ID();

SELECT TOP (2) CustomerID, CustomerName,
       CONVERT(varchar(20), DecryptByKeyAutoCert(CERT_ID(N'SmartBank_Column_Certificate'), NULL, ICNumberCipher)) AS ICNumber,
       CONVERT(varchar(20), DecryptByKeyAutoCert(CERT_ID(N'SmartBank_Column_Certificate'), NULL, PhoneCipher)) AS Phone,
       CONVERT(nvarchar(200), DecryptByKeyAutoCert(CERT_ID(N'SmartBank_Column_Certificate'), NULL, AddressCipher)) AS Address
FROM core.Customer ORDER BY CustomerID;

EXEC api.usp_VerifyLedgerChain;
EXEC api.usp_VerifyAccountBalances;
DBCC CHECKDB (N'$(TargetDatabaseName)') WITH NO_INFOMSGS;
GO
