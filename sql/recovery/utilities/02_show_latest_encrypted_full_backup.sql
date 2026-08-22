-- Run as: sa on the source SQL Server instance.
USE [SmartBankDB];
GO

-- Show the latest verified encrypted full backup to copy for cross-instance recovery.
SELECT TOP (1) BackupFile, FinishedAt
FROM ops.BackupRun
WHERE BackupType = 'F'
  AND Succeeded = 1
  AND Verified = 1
ORDER BY BackupRunID DESC;
GO
