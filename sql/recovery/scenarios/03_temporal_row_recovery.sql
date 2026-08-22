/*
RECOVERY MODULE:
Scenario - Temporal row recovery

PURPOSE:
Make one controlled accidental customer update and recover the complete row from
its pre-change temporal version without restoring the whole database.

RUN AS:
sa or another sysadmin on the primary instance.

PRECONDITIONS:
core.Customer must be a system-versioned temporal table and customer C00012 must
exist in the golden dataset.

DATABASE CHANGES:
Temporarily changes C00012, then restores every mutable column. Both updates remain
in temporal history and audit evidence under one correlation ID.

PASS CONDITION:
The current row exactly matches its pre-change values and the accidental version
is retained in temporal/audit history.
*/
USE [SmartBankDB];
GO
SET NOCOUNT ON;
GO

DECLARE @CorrelationID uniqueidentifier = NEWID();
DECLARE @BeforeChange datetime2(3) = SYSUTCDATETIME();
DECLARE @AccidentalName nvarchar(100) =
    N'ACCIDENTAL RECOVERY DRILL ' + LEFT(CONVERT(nvarchar(36), @CorrelationID), 8);
DECLARE @HistoricalName nvarchar(100), @HistoricalEmail varchar(254), @HistoricalStatus varchar(12),
        @HistoricalICC varbinary(512), @HistoricalPhoneC varbinary(512), @HistoricalAddressC varbinary(1024);

-- Give both audit records one correlation ID.
EXEC sys.sp_set_session_context @key = N'CorrelationID', @value = @CorrelationID;
WAITFOR DELAY '00:00:01';

-- Make the controlled accidental change.
UPDATE core.Customer
SET CustomerName = @AccidentalName,
    Email = 'accidental.recovery@example.invalid',
    Status = 'SUSPENDED'
WHERE CustomerID = 'C00012';

SELECT N'Controlled accidental value' AS Evidence,
       CustomerID, CustomerName, Email, Status, ValidFrom, ValidTo
FROM core.Customer WHERE CustomerID = 'C00012';

-- Read the version that existed before the accidental change.
SELECT @HistoricalName = CustomerName,
       @HistoricalEmail = Email,
       @HistoricalStatus = Status,
       @HistoricalICC = ICNumberCipher,
       @HistoricalPhoneC = PhoneCipher,
       @HistoricalAddressC = AddressCipher
FROM core.Customer FOR SYSTEM_TIME AS OF @BeforeChange
WHERE CustomerID = 'C00012';

SELECT N'Pre-change temporal version selected for recovery' AS Evidence,
       CustomerID, CustomerName, Email, Status, ValidFrom, ValidTo
FROM core.Customer FOR SYSTEM_TIME AS OF @BeforeChange
WHERE CustomerID = 'C00012';

-- Restore every mutable customer value from the earlier version.
UPDATE core.Customer
SET CustomerName = @HistoricalName,
    Email = @HistoricalEmail,
    Status = @HistoricalStatus,
    ICNumberCipher = @HistoricalICC,
    PhoneCipher = @HistoricalPhoneC,
    AddressCipher = @HistoricalAddressC
WHERE CustomerID = 'C00012';

EXEC sys.sp_set_session_context @key = N'CorrelationID', @value = NULL;

-- Show the restored row and the matching audit history.
SELECT N'PASS' AS ScenarioResult,
       @CorrelationID AS CorrelationID,
       @BeforeChange AS PreChangeTimeUtc,
       CustomerID, CustomerName, Email, Status
FROM core.Customer WHERE CustomerID = 'C00012';

SELECT AuditID, EventTime, ActionType, ActorLogin, CorrelationID, OldValues, NewValues
FROM audit.DmlAudit
WHERE SchemaName = N'core' AND TableName = N'Customer'
  AND CorrelationID = @CorrelationID
ORDER BY EventTime, AuditID;
GO
