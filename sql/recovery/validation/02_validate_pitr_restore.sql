/*
RECOVERY MODULE:
Validation - Point-in-time restore

PURPOSE:
Prove that the database-wide point-in-time copy is online, protected and internally
consistent, while showing the audited change that happened after the marker.

RUN AS:
sa or another sysadmin on the primary instance.

PRECONDITIONS:
operations/02_restore_point_in_time.sql completed successfully.

DATABASE CHANGES:
None. DBCC CHECKDB and all other statements are read-only.

PASS CONDITION:
An audited post-marker change is visible; CHECKDB, TDE, ledger-chain and balance
checks all pass on the recovered copy.
*/
USE [master];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF IS_SRVROLEMEMBER(N'sysadmin') <> 1
    THROW 52420, 'Run PITR validation as sa or another sysadmin.', 1;
IF DB_ID(N'SmartBankDB') IS NULL OR DB_ID(N'SmartBankDB_PITR') IS NULL
    THROW 52421, 'Both SmartBankDB and SmartBankDB_PITR must exist.', 1;
IF (SELECT state_desc FROM sys.databases WHERE name = N'SmartBankDB_PITR') <> N'ONLINE'
    THROW 52422, 'SmartBankDB_PITR is not ONLINE.', 1;

-- Find the recovery point used by the restore.
DECLARE @MarkerID uniqueidentifier, @MarkerTimeUtc datetime2(3),
        @MarkerTimeServer datetime2(3);
SELECT TOP (1)
       @MarkerID = MarkerID,
       @MarkerTimeUtc = MarkerTimeUtc,
       @MarkerTimeServer = MarkerTimeServer
FROM SmartBankDB.ops.RecoveryMarker
WHERE MarkerLabel LIKE N'PITR:%'
ORDER BY CreatedAt DESC;
IF @MarkerID IS NULL
    THROW 52423, 'The source database contains no PITR marker.', 1;

-- Confirm the accident was captured by the DML audit trail after the marker.
IF NOT EXISTS
   (
       SELECT 1 FROM SmartBankDB.audit.DmlAudit
       WHERE ActionType IN ('DELETE', 'UPDATE')
         AND EventTime > @MarkerTimeUtc
   )
    THROW 52424, 'No audited DELETE or UPDATE exists after the marker.', 1;

-- Check that the restored database remains TDE-encrypted.
DECLARE @EncryptionState int, @EncryptionAlgorithm nvarchar(32), @EncryptionKeyLength int;
SELECT @EncryptionState = encryption_state,
       @EncryptionAlgorithm = key_algorithm,
       @EncryptionKeyLength = key_length
FROM sys.dm_database_encryption_keys
WHERE database_id = DB_ID(N'SmartBankDB_PITR');
IF ISNULL(@EncryptionState, -1) <> 3 OR ISNULL(@EncryptionAlgorithm, N'') <> N'AES'
   OR ISNULL(@EncryptionKeyLength, -1) <> 256
    THROW 52428, 'SmartBankDB_PITR is not fully TDE-encrypted with AES-256.', 1;

-- Verify the recovered transaction hash chain.
CREATE TABLE #LedgerValidation
(
    RowsChecked int NOT NULL, InvalidRows int NOT NULL, ChainIsValid bit NOT NULL,
    LastComputedHash varbinary(64) NULL, StoredChainHead varbinary(64) NULL
);
INSERT #LedgerValidation
EXEC sys.sp_executesql N'USE [SmartBankDB_PITR]; EXEC api.usp_VerifyLedgerChain;';
IF NOT EXISTS (SELECT 1 FROM #LedgerValidation WHERE RowsChecked > 0 AND InvalidRows = 0 AND ChainIsValid = 1)
    THROW 52429, 'The recovered transaction hash chain is invalid.', 1;

-- Verify that recovered account balances still reconcile with the ledger.
CREATE TABLE #BalanceValidation
(
    AccountID varchar(10) NOT NULL, StoredBalance decimal(19, 2) NOT NULL,
    CalculatedBalance decimal(38, 2) NOT NULL, Difference decimal(38, 2) NOT NULL,
    IsReconciled bit NOT NULL
);
INSERT #BalanceValidation
EXEC sys.sp_executesql N'USE [SmartBankDB_PITR]; EXEC api.usp_VerifyAccountBalances;';
IF NOT EXISTS (SELECT 1 FROM #BalanceValidation)
   OR EXISTS (SELECT 1 FROM #BalanceValidation WHERE IsReconciled = 0 OR Difference <> 0)
    THROW 52430, 'A recovered account balance does not reconcile with its ledger.', 1;

-- Check the physical and logical consistency of the recovered database.
DBCC CHECKDB (N'SmartBankDB_PITR') WITH NO_INFOMSGS, DATA_PURITY;

-- Summarise the database-wide recovery checks.
SELECT N'PASS' AS ValidationResult,
       @MarkerID AS MarkerID,
       @MarkerTimeUtc AS MarkerTimeUtc,
       @MarkerTimeServer AS MarkerTimeServer,
       (SELECT COUNT(*) FROM SmartBankDB.audit.DmlAudit
        WHERE ActionType IN ('DELETE', 'UPDATE') AND EventTime > @MarkerTimeUtc) AS AuditedSourceChanges,
       @EncryptionState AS TdeState,
       @EncryptionAlgorithm AS TdeAlgorithm,
       @EncryptionKeyLength AS TdeKeyLength,
       (SELECT RowsChecked FROM #LedgerValidation) AS LedgerRowsChecked,
       (SELECT COUNT(*) FROM #BalanceValidation) AS AccountsReconciled;

-- Show the audited source changes that are absent from the point-in-time copy.
SELECT TOP (20) N'Audited source accident' AS Evidence,
       AuditID, EventTime, SchemaName, TableName, ActionType, ActorLogin, AffectedRowCount,
       CorrelationID, OldValues, NewValues
FROM SmartBankDB.audit.DmlAudit
WHERE ActionType IN ('DELETE', 'UPDATE')
  AND EventTime > @MarkerTimeUtc
ORDER BY EventTime DESC, AuditID DESC;
GO
