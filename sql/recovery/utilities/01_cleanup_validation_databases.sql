:on error exit
/*
RECOVERY MODULE:
Utility - Cleanup validation databases

PURPOSE:
Remove only explicitly named recovery validation databases after a deliberate
confirmation. Backup media, certificates, markers and audit evidence are retained.

RUN AS:
sa or another sysadmin in SQLCMD mode.

PRECONDITIONS:
Review both target names and supply ConfirmCleanup exactly as documented in README.

DATABASE CHANGES:
Drops the supplied PITR and encrypted-restore validation databases if they exist.

PASS CONDITION:
Both approved validation targets are absent and no protected database is targeted.
*/
USE [master];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF IS_SRVROLEMEMBER(N'sysadmin') <> 1
    THROW 52600, 'Run cleanup as sa or another sysadmin.', 1;

DECLARE @Confirmation nvarchar(100) = N'$(ConfirmCleanup)';
DECLARE @PitrDatabase sysname = N'$(PitrDatabaseName)';
DECLARE @RestoreValidationDatabase sysname = N'$(RestoreValidationDatabaseName)';

IF @Confirmation <> N'DROP_RECOVERY_VALIDATION_DATABASES'
    THROW 52601, 'Cleanup confirmation is missing or incorrect; no database was dropped.', 1;
IF NULLIF(@PitrDatabase, N'') IS NULL OR NULLIF(@RestoreValidationDatabase, N'') IS NULL
    THROW 52602, 'Both validation database names must be supplied.', 1;
IF @PitrDatabase = @RestoreValidationDatabase
    THROW 52603, 'PITR and encrypted-restore validation database names must be different.', 1;

DECLARE @Targets table (DatabaseName sysname PRIMARY KEY);
INSERT @Targets VALUES (@PitrDatabase), (@RestoreValidationDatabase);

IF EXISTS
(
    SELECT 1 FROM @Targets
    WHERE DatabaseName IN (N'SmartBankDB', N'SmartBankAnalyticsDB', N'master', N'model', N'msdb', N'tempdb')
       OR DatabaseName NOT LIKE N'SmartBankDB[_]%'
)
    THROW 52604, 'Cleanup accepts only separate validation names beginning with SmartBankDB_.', 1;

SELECT target.DatabaseName,
       COALESCE(databaseInfo.state_desc, N'NOT PRESENT') AS CurrentState,
       IIF(databaseInfo.database_id IS NULL, N'NO ACTION', N'WILL DROP') AS PlannedAction
FROM @Targets AS target
LEFT JOIN sys.databases AS databaseInfo ON databaseInfo.name = target.DatabaseName
ORDER BY target.DatabaseName;

DECLARE @DatabaseName sysname, @State nvarchar(60), @Sql nvarchar(max);
DECLARE cleanup_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT target.DatabaseName, databaseInfo.state_desc
    FROM @Targets AS target
    INNER JOIN sys.databases AS databaseInfo ON databaseInfo.name = target.DatabaseName
    ORDER BY target.DatabaseName;
OPEN cleanup_cursor;
FETCH NEXT FROM cleanup_cursor INTO @DatabaseName, @State;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @Sql = CASE WHEN @State = N'RESTORING' THEN N'' ELSE
                   N'ALTER DATABASE ' + QUOTENAME(@DatabaseName) +
                   N' SET SINGLE_USER WITH ROLLBACK IMMEDIATE;' END +
               N'DROP DATABASE ' + QUOTENAME(@DatabaseName) + N';';
    EXEC sys.sp_executesql @Sql;
    FETCH NEXT FROM cleanup_cursor INTO @DatabaseName, @State;
END;
CLOSE cleanup_cursor;
DEALLOCATE cleanup_cursor;

IF EXISTS
(
    SELECT 1 FROM @Targets AS target
    INNER JOIN sys.databases AS databaseInfo ON databaseInfo.name = target.DatabaseName
)
    THROW 52605, 'One or more approved validation databases still exists after cleanup.', 1;

SELECT N'PASS' AS CleanupResult,
       @PitrDatabase AS RemovedPitrTarget,
       @RestoreValidationDatabase AS RemovedEncryptedRestoreTarget,
       N'Backup media, certificates, markers and audit evidence were retained.' AS RetainedEvidence;
GO
