USE [SmartBankDB];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID(N'ops.RecoveryMarker', N'U') IS NULL
    THROW 52010, 'ops.RecoveryMarker is missing. Redeploy sql/09_backup_automation.sql first.', 1;

-- Capture a scheduled-chain log backup before the marker, then persist the exact recovery target.
EXEC ops.usp_RunBackup @BackupType = 'L';

DECLARE @MarkerID uniqueidentifier = NEWID();
DECLARE @MarkerTimeUtc datetime2(3) = SYSUTCDATETIME();
DECLARE @MarkerTimeServer datetime2(3) = SYSDATETIME();
DECLARE @ExpectedRows nvarchar(max) =
    (SELECT RecoveryID, EvidenceText, CreatedAt FROM demo.RecoveryTarget ORDER BY RecoveryID FOR JSON PATH, INCLUDE_NULL_VALUES);

INSERT ops.RecoveryMarker (MarkerID, MarkerTimeUtc, MarkerTimeServer, MarkerLabel, ExpectedRecoveryRows, CreatedBy)
VALUES (@MarkerID, @MarkerTimeUtc, @MarkerTimeServer, N'Before lecturer deletion', @ExpectedRows, ORIGINAL_LOGIN());

SELECT @MarkerID AS MarkerID, @MarkerTimeUtc AS MarkerUtc, @MarkerTimeServer AS StopAtServerTime,
       (SELECT COUNT(*) FROM demo.RecoveryTarget) AS ExpectedRowCount,
       @ExpectedRows AS ExpectedRowsJson;
SELECT * FROM demo.RecoveryTarget ORDER BY RecoveryID;
GO
