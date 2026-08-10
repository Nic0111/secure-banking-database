USE [$(DatabaseName)];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
BEGIN
    DECLARE @CreateMasterKey nvarchar(max) =
        N'CREATE MASTER KEY ENCRYPTION BY PASSWORD = N''' +
        REPLACE(N'$(MasterKeyPassword)', N'''', N'''''') + N''';';
    EXEC sys.sp_executesql @CreateMasterKey;
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'SmartBank_Column_Certificate')
    CREATE CERTIFICATE SmartBank_Column_Certificate
        WITH SUBJECT = N'SmartBank column-level encryption certificate',
             EXPIRY_DATE = '20361231';
GO

IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'SmartBank_Column_Key')
    CREATE SYMMETRIC KEY SmartBank_Column_Key
        WITH ALGORITHM = AES_256
        ENCRYPTION BY CERTIFICATE SmartBank_Column_Certificate;
GO

DECLARE @CertificateDirectory nvarchar(4000) = N'$(CertificateDirectory)';
DECLARE @Separator nchar(1) = N'$(PathSeparator)';
DECLARE @Password nvarchar(4000) = N'$(CertificateBackupPassword)';
DECLARE @MasterKeyPath nvarchar(4000) = @CertificateDirectory + @Separator + N'SmartBank_DatabaseMasterKey.key';
DECLARE @CertificatePath nvarchar(4000) = @CertificateDirectory + @Separator + N'SmartBank_Column_Certificate.cer';
DECLARE @PrivateKeyPath nvarchar(4000) = @CertificateDirectory + @Separator + N'SmartBank_Column_Certificate.pvk';
DECLARE @FileExists int = 0;
DECLARE @Sql nvarchar(max);

EXEC master.dbo.xp_fileexist @MasterKeyPath, @FileExists OUTPUT;
IF @FileExists = 0
BEGIN
    SET @Sql = N'BACKUP MASTER KEY TO FILE = N''' + REPLACE(@MasterKeyPath, N'''', N'''''') +
               N''' ENCRYPTION BY PASSWORD = N''' + REPLACE(@Password, N'''', N'''''') + N''';';
    EXEC sys.sp_executesql @Sql;
END;

SET @FileExists = 0;
EXEC master.dbo.xp_fileexist @CertificatePath, @FileExists OUTPUT;
IF @FileExists = 0
BEGIN
    SET @Sql = N'BACKUP CERTIFICATE SmartBank_Column_Certificate TO FILE = N''' +
               REPLACE(@CertificatePath, N'''', N'''''') +
               N''' WITH PRIVATE KEY (FILE = N''' + REPLACE(@PrivateKeyPath, N'''', N'''''') +
               N''', ENCRYPTION BY PASSWORD = N''' + REPLACE(@Password, N'''', N'''''') + N''');';
    EXEC sys.sp_executesql @Sql;
END;
GO

