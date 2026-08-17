/*
RECOVERY MODULE:
Validation - Point-in-time restore

PURPOSE:
Prove that SmartBankDB_PITR exactly matches the marker captured before the accident,
while the live source still exposes the controlled difference and its audit trail.

RUN AS:
sa or another sysadmin on the primary instance.

PRECONDITIONS:
operations/02_restore_point_in_time.sql completed successfully.

DATABASE CHANGES:
None. DBCC CHECKDB and all other statements are read-only.

PASS CONDITION:
No row/value differs between marker JSON and the recovered database; source damage
is demonstrable; CHECKDB, TDE, ledger-chain and balance checks all pass.
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

DECLARE @MarkerID uniqueidentifier, @MarkerTimeUtc datetime2(3),
        @MarkerTimeServer datetime2(3), @ExpectedRowsJson nvarchar(max);
SELECT TOP (1)
       @MarkerID = MarkerID,
       @MarkerTimeUtc = MarkerTimeUtc,
       @MarkerTimeServer = MarkerTimeServer,
       @ExpectedRowsJson = ExpectedRecoveryRows
FROM SmartBankDB.ops.RecoveryMarker
WHERE MarkerLabel LIKE N'PITR:%'
ORDER BY CreatedAt DESC;
IF @MarkerID IS NULL
    THROW 52423, 'The source database contains no PITR marker.', 1;

CREATE TABLE #ExpectedRows
(
    RecoveryID int NOT NULL PRIMARY KEY,
    EvidenceText nvarchar(200) NOT NULL,
    CreatedAt datetime2(3) NOT NULL
);
INSERT #ExpectedRows (RecoveryID, EvidenceText, CreatedAt)
SELECT RecoveryID, EvidenceText, CreatedAt
FROM OPENJSON(@ExpectedRowsJson)
WITH
(
    RecoveryID int '$.RecoveryID',
    EvidenceText nvarchar(200) '$.EvidenceText',
    CreatedAt datetime2(3) '$.CreatedAt'
);
IF NOT EXISTS (SELECT 1 FROM #ExpectedRows)
    THROW 52424, 'The marker contains no expected recovery rows.', 1;

CREATE TABLE #RecoveredRows
(
    RecoveryID int NOT NULL PRIMARY KEY,
    EvidenceText nvarchar(200) NOT NULL,
    CreatedAt datetime2(3) NOT NULL
);
INSERT #RecoveredRows (RecoveryID, EvidenceText, CreatedAt)
EXEC sys.sp_executesql
    N'SELECT RecoveryID, EvidenceText, CreatedAt
      FROM SmartBankDB_PITR.demo.RecoveryTarget ORDER BY RecoveryID;';

IF EXISTS
   (
       SELECT RecoveryID, EvidenceText, CreatedAt FROM #ExpectedRows
       EXCEPT
       SELECT RecoveryID, EvidenceText, CreatedAt FROM #RecoveredRows
   )
   OR EXISTS
   (
       SELECT RecoveryID, EvidenceText, CreatedAt FROM #RecoveredRows
       EXCEPT
       SELECT RecoveryID, EvidenceText, CreatedAt FROM #ExpectedRows
   )
    THROW 52425, 'SmartBankDB_PITR does not exactly match the saved marker JSON.', 1;

CREATE TABLE #SourceDifference
(
    DifferenceType varchar(20) NOT NULL,
    RecoveryID int NOT NULL,
    EvidenceText nvarchar(200) NOT NULL,
    CreatedAt datetime2(3) NOT NULL
);
INSERT #SourceDifference
SELECT N'MISSING_OR_CHANGED', RecoveryID, EvidenceText, CreatedAt
FROM
(
    SELECT RecoveryID, EvidenceText, CreatedAt FROM #ExpectedRows
    EXCEPT
    SELECT RecoveryID, EvidenceText, CreatedAt FROM SmartBankDB.demo.RecoveryTarget
) AS sourceMissing;
INSERT #SourceDifference
SELECT N'EXTRA_OR_CHANGED', RecoveryID, EvidenceText, CreatedAt
FROM
(
    SELECT RecoveryID, EvidenceText, CreatedAt FROM SmartBankDB.demo.RecoveryTarget
    EXCEPT
    SELECT RecoveryID, EvidenceText, CreatedAt FROM #ExpectedRows
) AS sourceExtra;
IF NOT EXISTS (SELECT 1 FROM #SourceDifference)
    THROW 52426, 'The recovered rows are correct, but no source accident remains to demonstrate the contrast.', 1;

IF NOT EXISTS
   (
       SELECT 1 FROM SmartBankDB.audit.DmlAudit
       WHERE SchemaName = N'demo' AND TableName = N'RecoveryTarget'
         AND ActionType IN ('DELETE', 'UPDATE') AND EventTime >= @MarkerTimeUtc
   )
    THROW 52427, 'No DML audit evidence accompanies the controlled source accident.', 1;

DECLARE @EncryptionState int, @EncryptionAlgorithm nvarchar(32), @EncryptionKeyLength int;
SELECT @EncryptionState = encryption_state,
       @EncryptionAlgorithm = key_algorithm,
       @EncryptionKeyLength = key_length
FROM sys.dm_database_encryption_keys
WHERE database_id = DB_ID(N'SmartBankDB_PITR');
IF ISNULL(@EncryptionState, -1) <> 3 OR ISNULL(@EncryptionAlgorithm, N'') <> N'AES'
   OR ISNULL(@EncryptionKeyLength, -1) <> 256
    THROW 52428, 'SmartBankDB_PITR is not fully TDE-encrypted with AES-256.', 1;

CREATE TABLE #LedgerValidation
(
    RowsChecked int NOT NULL, InvalidRows int NOT NULL, ChainIsValid bit NOT NULL,
    LastComputedHash varbinary(64) NULL, StoredChainHead varbinary(64) NULL
);
INSERT #LedgerValidation
EXEC sys.sp_executesql N'USE [SmartBankDB_PITR]; EXEC api.usp_VerifyLedgerChain;';
IF NOT EXISTS (SELECT 1 FROM #LedgerValidation WHERE RowsChecked > 0 AND InvalidRows = 0 AND ChainIsValid = 1)
    THROW 52429, 'The recovered transaction hash chain is invalid.', 1;

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

DBCC CHECKDB (N'SmartBankDB_PITR') WITH NO_INFOMSGS, DATA_PURITY;

SELECT N'PASS' AS ValidationResult,
       @MarkerID AS MarkerID,
       @MarkerTimeUtc AS MarkerTimeUtc,
       @MarkerTimeServer AS MarkerTimeServer,
       (SELECT COUNT(*) FROM #ExpectedRows) AS ExpectedRows,
       (SELECT COUNT(*) FROM #RecoveredRows) AS RecoveredRows,
       (SELECT COUNT(*) FROM #SourceDifference) AS LiveSourceDifferenceRows,
       @EncryptionState AS TdeState,
       @EncryptionAlgorithm AS TdeAlgorithm,
       @EncryptionKeyLength AS TdeKeyLength,
       (SELECT RowsChecked FROM #LedgerValidation) AS LedgerRowsChecked,
       (SELECT COUNT(*) FROM #BalanceValidation) AS AccountsReconciled;

SELECT N'Recovered rows at marker' AS Evidence, *
FROM #RecoveredRows ORDER BY RecoveryID;
SELECT N'Live source difference retained for comparison' AS Evidence, *
FROM #SourceDifference ORDER BY RecoveryID, DifferenceType;
SELECT TOP (20) N'Audited source accident' AS Evidence,
       AuditID, EventTime, ActionType, ActorLogin, AffectedRowCount,
       CorrelationID, OldValues, NewValues
FROM SmartBankDB.audit.DmlAudit
WHERE SchemaName = N'demo' AND TableName = N'RecoveryTarget'
  AND ActionType IN ('DELETE', 'UPDATE') AND EventTime >= @MarkerTimeUtc
ORDER BY EventTime DESC, AuditID DESC;
GO
