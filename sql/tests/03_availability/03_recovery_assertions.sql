-- Connect as: sa. Run after completing the point-in-time recovery drill.
USE [SmartBankDB];
GO

-- Verify that a recovery marker and a log backup covering it exist.
IF NOT EXISTS (SELECT 1 FROM ops.RecoveryMarker)
    THROW 51320, 'FAIL: no point-in-time recovery marker has been captured.', 1;

IF NOT EXISTS
(
    SELECT 1
    FROM ops.RecoveryMarker AS marker
    INNER JOIN msdb.dbo.backupset AS backupset
        ON backupset.database_name = DB_NAME()
       AND backupset.type = 'L'
       AND backupset.backup_finish_date >= marker.MarkerTimeServer
)
    THROW 51321, 'FAIL: no log backup covers the recovery marker.', 1;

SELECT TOP (1) MarkerID, MarkerTimeUtc, MarkerTimeServer, MarkerLabel, CreatedAt
FROM ops.RecoveryMarker
ORDER BY CreatedAt DESC;

SELECT name, state_desc
FROM sys.databases
WHERE name IN (N'SmartBankDB_RestoreDemo', N'SmartBankDB_PITR');
GO
