:on error exit
/*
RECOVERY MODULE:
Validation - Cross-instance encrypted full restore

PURPOSE:
Prove that the restored encrypted backup is usable, internally consistent and able
to decrypt protected columns without displaying sensitive values.

RUN AS:
sa or another sysadmin on the target instance, in SQLCMD mode.

PRECONDITIONS:
operations/01_restore_encrypted_full.sql completed for TargetDatabaseName.

DATABASE CHANGES:
None. DBCC CHECKDB and all other statements are read-only.

PASS CONDITION:
The target is ONLINE with TDE, key protection and non-empty data; CHECKDB succeeds;
column decryption works; ledger hashes and every account balance reconcile.
*/
USE [master];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF IS_SRVROLEMEMBER(N'sysadmin') <> 1
    THROW 52400, 'Run encrypted-restore validation as sa or another sysadmin.', 1;

DECLARE @TargetDatabase sysname = N'$(TargetDatabaseName)';
IF NULLIF(@TargetDatabase, N'') IS NULL OR @TargetDatabase NOT LIKE N'SmartBankDB[_]%'
    THROW 52401, 'TargetDatabaseName must be a validation name beginning with SmartBankDB_.', 1;
IF @TargetDatabase IN (N'SmartBankDB', N'SmartBankAnalyticsDB', N'master', N'model', N'msdb', N'tempdb')
    THROW 52402, 'A source, analytics or system database cannot be used as the validation target.', 1;
IF DB_ID(@TargetDatabase) IS NULL
    THROW 52403, 'The restored validation database does not exist.', 1;
IF (SELECT state_desc FROM sys.databases WHERE name = @TargetDatabase) <> N'ONLINE'
    THROW 52404, 'The restored validation database is not ONLINE.', 1;

DECLARE @EncryptionState int, @EncryptionAlgorithm nvarchar(32), @EncryptionKeyLength int;
SELECT @EncryptionState = encryption_state,
       @EncryptionAlgorithm = key_algorithm,
       @EncryptionKeyLength = key_length
FROM sys.dm_database_encryption_keys
WHERE database_id = DB_ID(@TargetDatabase);
IF ISNULL(@EncryptionState, -1) <> 3 OR ISNULL(@EncryptionAlgorithm, N'') <> N'AES'
   OR ISNULL(@EncryptionKeyLength, -1) <> 256
    THROW 52405, 'The restored database is not fully TDE-encrypted with AES-256.', 1;

DECLARE @Sql nvarchar(max);
CREATE TABLE #MasterKeyProtection (ProtectedByServiceMasterKey bit NOT NULL);
SET @Sql = N'USE ' + QUOTENAME(@TargetDatabase) + N';
             SELECT CONVERT(bit, CASE WHEN EXISTS
             (
                 SELECT 1
                 FROM sys.key_encryptions AS keyEncryption
                 INNER JOIN sys.symmetric_keys AS symmetricKey
                     ON symmetricKey.symmetric_key_id = keyEncryption.key_id
                 WHERE symmetricKey.name = N''##MS_DatabaseMasterKey##''
                   AND keyEncryption.crypt_type = ''ESKM''
             ) THEN 1 ELSE 0 END);';
INSERT #MasterKeyProtection EXEC sys.sp_executesql @Sql;
IF NOT EXISTS (SELECT 1 FROM #MasterKeyProtection WHERE ProtectedByServiceMasterKey = 1)
    THROW 52406, 'The restored database master key is not protected by the target service master key.', 1;

CREATE TABLE #RowCounts (Entity nvarchar(40) NOT NULL, [RowCount] bigint NOT NULL);
SET @Sql = N'USE ' + QUOTENAME(@TargetDatabase) + N';
             SELECT N''Staff'', COUNT_BIG(*) FROM core.Staff
             UNION ALL SELECT N''Customers'', COUNT_BIG(*) FROM core.Customer
             UNION ALL SELECT N''Accounts'', COUNT_BIG(*) FROM core.Account
             UNION ALL SELECT N''Transactions'', COUNT_BIG(*) FROM core.TransactionRecord;';
INSERT #RowCounts EXEC sys.sp_executesql @Sql;
IF EXISTS (SELECT 1 FROM #RowCounts WHERE [RowCount] = 0) OR (SELECT COUNT(*) FROM #RowCounts) <> 4
    THROW 52407, 'The restored core dataset is incomplete or empty.', 1;

CREATE TABLE #DecryptionProof (CustomerRows bigint NOT NULL, DecryptableRows bigint NOT NULL);
SET @Sql = N'USE ' + QUOTENAME(@TargetDatabase) + N';
             SELECT COUNT_BIG(*) AS CustomerRows,
                    SUM(CONVERT(bigint, CASE
                        WHEN DecryptByKeyAutoCert(CERT_ID(N''SmartBank_Column_Certificate''), NULL, ICNumberCipher) IS NOT NULL
                         AND DecryptByKeyAutoCert(CERT_ID(N''SmartBank_Column_Certificate''), NULL, PhoneCipher) IS NOT NULL
                         AND DecryptByKeyAutoCert(CERT_ID(N''SmartBank_Column_Certificate''), NULL, AddressCipher) IS NOT NULL
                        THEN 1 ELSE 0 END)) AS DecryptableRows
             FROM core.Customer;';
INSERT #DecryptionProof EXEC sys.sp_executesql @Sql;
IF EXISTS (SELECT 1 FROM #DecryptionProof WHERE CustomerRows = 0 OR DecryptableRows <> CustomerRows)
    THROW 52408, 'One or more encrypted customer values could not be decrypted after restore.', 1;

CREATE TABLE #LedgerValidation
(
    RowsChecked int NOT NULL, InvalidRows int NOT NULL, ChainIsValid bit NOT NULL,
    LastComputedHash varbinary(64) NULL, StoredChainHead varbinary(64) NULL
);
SET @Sql = N'USE ' + QUOTENAME(@TargetDatabase) + N'; EXEC api.usp_VerifyLedgerChain;';
INSERT #LedgerValidation EXEC sys.sp_executesql @Sql;
IF NOT EXISTS (SELECT 1 FROM #LedgerValidation WHERE RowsChecked > 0 AND InvalidRows = 0 AND ChainIsValid = 1)
    THROW 52409, 'The restored transaction hash chain is invalid.', 1;

CREATE TABLE #BalanceValidation
(
    AccountID varchar(10) NOT NULL, StoredBalance decimal(19, 2) NOT NULL,
    CalculatedBalance decimal(38, 2) NOT NULL, Difference decimal(38, 2) NOT NULL,
    IsReconciled bit NOT NULL
);
SET @Sql = N'USE ' + QUOTENAME(@TargetDatabase) + N'; EXEC api.usp_VerifyAccountBalances;';
INSERT #BalanceValidation EXEC sys.sp_executesql @Sql;
IF NOT EXISTS (SELECT 1 FROM #BalanceValidation)
   OR EXISTS (SELECT 1 FROM #BalanceValidation WHERE IsReconciled = 0 OR Difference <> 0)
    THROW 52410, 'One or more restored account balances do not reconcile with the ledger.', 1;

SET @Sql = N'DBCC CHECKDB (' + QUOTENAME(@TargetDatabase, N'''') + N') WITH NO_INFOMSGS, DATA_PURITY;';
EXEC sys.sp_executesql @Sql;

SELECT N'PASS' AS ValidationResult,
       @TargetDatabase AS RestoredDatabase,
       databaseInfo.state_desc AS DatabaseState,
       @EncryptionState AS TdeState,
       @EncryptionAlgorithm AS TdeAlgorithm,
       @EncryptionKeyLength AS TdeKeyLength,
       (SELECT ProtectedByServiceMasterKey FROM #MasterKeyProtection) AS MasterKeyAutoOpenReady,
       decryption.CustomerRows,
       decryption.DecryptableRows,
       ledger.RowsChecked AS LedgerRowsChecked,
       ledger.InvalidRows AS InvalidLedgerRows,
       (SELECT COUNT(*) FROM #BalanceValidation) AS AccountsReconciled,
       restoreHistory.restore_date AS LatestRestoreServerTime,
       restoreHistory.user_name AS RestoredBy
FROM sys.databases AS databaseInfo
CROSS JOIN #DecryptionProof AS decryption
CROSS JOIN #LedgerValidation AS ledger
OUTER APPLY
(
    SELECT TOP (1) restore_date, user_name
    FROM msdb.dbo.restorehistory
    WHERE destination_database_name = @TargetDatabase
    ORDER BY restore_date DESC, restore_history_id DESC
) AS restoreHistory
WHERE databaseInfo.name = @TargetDatabase;

SELECT Entity, [RowCount] FROM #RowCounts ORDER BY Entity;
GO
