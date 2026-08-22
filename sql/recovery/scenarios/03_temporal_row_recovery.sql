/*
RECOVERY MODULE:
Scenario - Temporal row recovery

PURPOSE:
Recover customer C00012 from its immediately previous temporal version after a
lecturer makes a manual update.

RUN AS:
sa or another sysadmin on the primary instance.
*/
USE [SmartBankDB];
GO
SET NOCOUNT ON;
GO

-- Step 1: Run this first in the recovery SSMS window.
DROP TABLE IF EXISTS #TemporalRecoveryPoint;
CREATE TABLE #TemporalRecoveryPoint
(
    BeforeChange datetime2(3) NOT NULL
);
INSERT #TemporalRecoveryPoint (BeforeChange)
VALUES (SYSUTCDATETIME());

SELECT CustomerID, CustomerName, Email, Status, ValidFrom, ValidTo,
       (SELECT BeforeChange FROM #TemporalRecoveryPoint) AS RecoveryPointUtc
FROM core.Customer
WHERE CustomerID = 'C00012';

-- Stop here. Keep this SSMS window open and update C00012 manually in another window.
-- Change only CustomerName, Email or Status.
-- Example: UPDATE core.Customer SET CustomerName = N'TEMPORAL DEMO CHANGE' WHERE CustomerID = 'C00012';

-- Step 2: Run everything below after the manual update.
DECLARE @CorrelationID uniqueidentifier = NEWID();
DECLARE @BeforeChange datetime2(3) = (SELECT BeforeChange FROM #TemporalRecoveryPoint);
DECLARE @PreviousName nvarchar(100), @PreviousEmail varchar(254), @PreviousStatus varchar(12),
        @PreviousICC varbinary(512), @PreviousPhoneC varbinary(512), @PreviousAddressC varbinary(1024);

-- Show the changed live row before recovering it.
SELECT N'Live row after manual change' AS Evidence,
       CustomerID, CustomerName, Email, Status, ValidFrom, ValidTo
FROM core.Customer
WHERE CustomerID = 'C00012';

-- Read the version that existed at the saved recovery point.
SELECT
       @PreviousName = CustomerName,
       @PreviousEmail = Email,
       @PreviousStatus = Status,
       @PreviousICC = ICNumberCipher,
       @PreviousPhoneC = PhoneCipher,
       @PreviousAddressC = AddressCipher
FROM core.Customer FOR SYSTEM_TIME AS OF @BeforeChange
WHERE CustomerID = 'C00012';

-- Show the temporal version that will be restored.
SELECT N'Previous temporal version' AS Evidence,
       CustomerID, CustomerName, Email, Status, ValidFrom, ValidTo
FROM core.Customer FOR SYSTEM_TIME AS OF @BeforeChange
WHERE CustomerID = 'C00012';

-- Restore every mutable customer value from that earlier version.
EXEC sys.sp_set_session_context @key = N'CorrelationID', @value = @CorrelationID;
UPDATE core.Customer
SET CustomerName = @PreviousName,
    Email = @PreviousEmail,
    Status = @PreviousStatus,
    ICNumberCipher = @PreviousICC,
    PhoneCipher = @PreviousPhoneC,
    AddressCipher = @PreviousAddressC
WHERE CustomerID = 'C00012';
EXEC sys.sp_set_session_context @key = N'CorrelationID', @value = NULL;

-- Show the repaired row and its recovery audit record.
SELECT N'PASS' AS ScenarioResult,
       @CorrelationID AS CorrelationID,
       CustomerID, CustomerName, Email, Status
FROM core.Customer
WHERE CustomerID = 'C00012';

SELECT AuditID, EventTime, ActionType, ActorLogin, CorrelationID, OldValues, NewValues
FROM audit.DmlAudit
WHERE SchemaName = N'core' AND TableName = N'Customer'
  AND CorrelationID = @CorrelationID
ORDER BY EventTime, AuditID;
GO
