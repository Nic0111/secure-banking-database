-- Explicit cleanup only. Review target names before execution.
USE [master];
GO

IF DB_ID(N'SmartBankDB_PITR') IS NOT NULL
BEGIN
    IF DATABASEPROPERTYEX(N'SmartBankDB_PITR', N'Status') <> N'RESTORING'
        ALTER DATABASE SmartBankDB_PITR SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE SmartBankDB_PITR;
END;

IF DB_ID(N'SmartBankDB_RestoreDemo') IS NOT NULL
BEGIN
    IF DATABASEPROPERTYEX(N'SmartBankDB_RestoreDemo', N'Status') <> N'RESTORING'
        ALTER DATABASE SmartBankDB_RestoreDemo SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE SmartBankDB_RestoreDemo;
END;
GO
