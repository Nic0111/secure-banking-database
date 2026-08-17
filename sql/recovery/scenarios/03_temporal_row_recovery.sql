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
SET XACT_ABORT ON;
GO

IF IS_SRVROLEMEMBER(N'sysadmin') <> 1
    THROW 52220, 'Run the temporal recovery scenario as sa or another sysadmin.', 1;
IF NOT EXISTS
   (
       SELECT 1 FROM sys.tables
       WHERE object_id = OBJECT_ID(N'core.Customer') AND temporal_type = 2
   )
    THROW 52221, 'core.Customer is not configured as a system-versioned temporal table.', 1;
IF NOT EXISTS (SELECT 1 FROM core.Customer WHERE CustomerID = 'C00012')
    THROW 52222, 'Golden customer C00012 is missing.', 1;

DECLARE @CorrelationID uniqueidentifier = NEWID();
DECLARE @BeforeChange datetime2(3) = SYSUTCDATETIME();
DECLARE @AccidentalName nvarchar(100) =
    N'ACCIDENTAL RECOVERY DRILL ' + LEFT(CONVERT(nvarchar(36), @CorrelationID), 8);
DECLARE @OriginalName nvarchar(100), @OriginalEmail varchar(254), @OriginalStatus varchar(12),
        @OriginalICC varbinary(512), @OriginalPhoneC varbinary(512), @OriginalAddressC varbinary(1024);
DECLARE @HistoricalName nvarchar(100), @HistoricalEmail varchar(254), @HistoricalStatus varchar(12),
        @HistoricalICC varbinary(512), @HistoricalPhoneC varbinary(512), @HistoricalAddressC varbinary(1024);
DECLARE @AccidentApplied bit = 0;

SELECT @OriginalName = CustomerName, @OriginalEmail = Email, @OriginalStatus = Status,
       @OriginalICC = ICNumberCipher, @OriginalPhoneC = PhoneCipher, @OriginalAddressC = AddressCipher
FROM core.Customer WHERE CustomerID = 'C00012';

BEGIN TRY
    EXEC sys.sp_set_session_context @key = N'CorrelationID', @value = @CorrelationID;
    WAITFOR DELAY '00:00:01';

    UPDATE core.Customer
    SET CustomerName = @AccidentalName,
        Email = 'accidental.recovery@example.invalid',
        Status = 'SUSPENDED'
    WHERE CustomerID = 'C00012';
    SET @AccidentApplied = 1;

    SELECT N'Controlled accidental value' AS Evidence,
           CustomerID, CustomerName, Email, Status, ValidFrom, ValidTo
    FROM core.Customer WHERE CustomerID = 'C00012';

    SELECT @HistoricalName = CustomerName,
           @HistoricalEmail = Email,
           @HistoricalStatus = Status,
           @HistoricalICC = ICNumberCipher,
           @HistoricalPhoneC = PhoneCipher,
           @HistoricalAddressC = AddressCipher
    FROM core.Customer FOR SYSTEM_TIME AS OF @BeforeChange
    WHERE CustomerID = 'C00012';

    IF @HistoricalName IS NULL
        THROW 52223, 'No pre-change temporal version was found for C00012.', 1;

    SELECT N'Pre-change temporal version selected for recovery' AS Evidence,
           CustomerID, CustomerName, Email, Status, ValidFrom, ValidTo
    FROM core.Customer FOR SYSTEM_TIME AS OF @BeforeChange
    WHERE CustomerID = 'C00012';

    UPDATE core.Customer
    SET CustomerName = @HistoricalName,
        Email = @HistoricalEmail,
        Status = @HistoricalStatus,
        ICNumberCipher = @HistoricalICC,
        PhoneCipher = @HistoricalPhoneC,
        AddressCipher = @HistoricalAddressC
    WHERE CustomerID = 'C00012';

    IF NOT EXISTS
       (
           SELECT 1 FROM core.Customer
           WHERE CustomerID = 'C00012'
             AND CustomerName = @OriginalName AND Email = @OriginalEmail AND Status = @OriginalStatus
             AND ICNumberCipher = @OriginalICC AND PhoneCipher = @OriginalPhoneC
             AND AddressCipher = @OriginalAddressC
       )
        THROW 52224, 'Temporal recovery did not restore every mutable customer column.', 1;

    EXEC sys.sp_set_session_context @key = N'CorrelationID', @value = NULL;

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
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;

    -- Safety fallback: if the controlled accident committed but temporal recovery
    -- failed, restore the values captured before the drill and retain its audit trail.
    IF @AccidentApplied = 1
    BEGIN
        BEGIN TRY
            EXEC sys.sp_set_session_context @key = N'CorrelationID', @value = @CorrelationID;
            UPDATE core.Customer
            SET CustomerName = @OriginalName,
                Email = @OriginalEmail,
                Status = @OriginalStatus,
                ICNumberCipher = @OriginalICC,
                PhoneCipher = @OriginalPhoneC,
                AddressCipher = @OriginalAddressC
            WHERE CustomerID = 'C00012';
        END TRY
        BEGIN CATCH
            -- Preserve the original failure; validation will expose any remaining damage.
            PRINT N'WARNING: safety restoration also failed; inspect C00012 immediately.';
        END CATCH;
    END;
    EXEC sys.sp_set_session_context @key = N'CorrelationID', @value = NULL;
    THROW;
END CATCH;
GO
