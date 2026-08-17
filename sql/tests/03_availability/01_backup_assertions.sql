-- Connect as: sa.
USE [SmartBankDB];
GO

-- Verify that at least one encrypted, checksummed full backup is available.
IF NOT EXISTS
(
    SELECT 1
    FROM msdb.dbo.backupset
    WHERE database_name = DB_NAME()
      AND type = 'D'
      AND is_copy_only = 0
      AND key_algorithm = 'AES_256'
      AND has_backup_checksums = 1
)
    THROW 51300, 'FAIL: no encrypted, checksummed full backup is available.', 1;

-- Verify this reset deployment recorded a successful, verified full backup.
IF NOT EXISTS
(
    SELECT 1
    FROM ops.BackupRun
    WHERE BackupType = 'F'
      AND Succeeded = 1
      AND Verified = 1
      AND ErrorNumber IS NULL
)
    THROW 51301, 'FAIL: this deployment has no successful, verified full backup record.', 1;

EXEC ops.usp_BackupHealth @Days = 3;
GO
