/*
RECOVERY MODULE:
Validation - Temporal row recovery

PURPOSE:
Use the correlated DML audit records and temporal history to prove that the latest
controlled customer accident was reversed without a whole-database restore.

RUN AS:
sa or another sysadmin after scenarios/03_temporal_row_recovery.sql.

PRECONDITIONS:
The temporal recovery scenario completed and retained its audit/history evidence.

DATABASE CHANGES:
None. This script is read-only.

PASS CONDITION:
The accident and repair share one correlation ID, current business values match the
pre-accident audit image, and the accidental version remains in temporal history.
*/
USE [SmartBankDB];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF IS_SRVROLEMEMBER(N'sysadmin') <> 1
    THROW 52440, 'Run temporal-recovery validation as sa or another sysadmin.', 1;
IF NOT EXISTS
   (
       SELECT 1 FROM sys.tables
       WHERE object_id = OBJECT_ID(N'core.Customer') AND temporal_type = 2
   )
    THROW 52441, 'core.Customer is not a system-versioned temporal table.', 1;

DECLARE @CorrelationID uniqueidentifier;
SELECT TOP (1) @CorrelationID = CorrelationID
FROM audit.DmlAudit
WHERE SchemaName = N'core' AND TableName = N'Customer' AND ActionType = 'UPDATE'
  AND CorrelationID IS NOT NULL
  AND JSON_VALUE(NewValues, '$[0].CustomerID') = 'C00012'
  AND JSON_VALUE(NewValues, '$[0].CustomerName') LIKE N'ACCIDENTAL RECOVERY DRILL %'
ORDER BY EventTime DESC, AuditID DESC;
IF @CorrelationID IS NULL
    THROW 52442, 'No correlated temporal-recovery drill was found.', 1;

DECLARE @AccidentAuditID bigint, @RecoveryAuditID bigint,
        @OriginalName nvarchar(100), @OriginalEmail varchar(254), @OriginalStatus varchar(12),
        @AccidentalName nvarchar(100), @CurrentName nvarchar(100),
        @CurrentEmail varchar(254), @CurrentStatus varchar(12);

SELECT TOP (1)
       @AccidentAuditID = AuditID,
       @OriginalName = JSON_VALUE(OldValues, '$[0].CustomerName'),
       @OriginalEmail = JSON_VALUE(OldValues, '$[0].Email'),
       @OriginalStatus = JSON_VALUE(OldValues, '$[0].Status'),
       @AccidentalName = JSON_VALUE(NewValues, '$[0].CustomerName')
FROM audit.DmlAudit
WHERE SchemaName = N'core' AND TableName = N'Customer' AND ActionType = 'UPDATE'
  AND CorrelationID = @CorrelationID
  AND JSON_VALUE(NewValues, '$[0].CustomerName') LIKE N'ACCIDENTAL RECOVERY DRILL %'
ORDER BY EventTime, AuditID;

SELECT TOP (1) @RecoveryAuditID = AuditID
FROM audit.DmlAudit
WHERE SchemaName = N'core' AND TableName = N'Customer' AND ActionType = 'UPDATE'
  AND CorrelationID = @CorrelationID AND AuditID > @AccidentAuditID
  AND JSON_VALUE(NewValues, '$[0].CustomerName') = @OriginalName
  AND JSON_VALUE(NewValues, '$[0].Email') = @OriginalEmail
  AND JSON_VALUE(NewValues, '$[0].Status') = @OriginalStatus
ORDER BY EventTime DESC, AuditID DESC;

SELECT @CurrentName = CustomerName, @CurrentEmail = Email, @CurrentStatus = Status
FROM core.Customer WHERE CustomerID = 'C00012';

IF @AccidentAuditID IS NULL OR @RecoveryAuditID IS NULL
    THROW 52443, 'The correlated audit trail does not contain both accident and recovery updates.', 1;
IF @CurrentName <> @OriginalName OR @CurrentEmail <> @OriginalEmail OR @CurrentStatus <> @OriginalStatus
    THROW 52444, 'The current customer business values do not match the pre-accident audit image.', 1;
IF NOT EXISTS
   (
       SELECT 1 FROM core.Customer FOR SYSTEM_TIME ALL
       WHERE CustomerID = 'C00012' AND CustomerName = @AccidentalName
   )
    THROW 52445, 'The accidental customer version is missing from temporal history.', 1;

SELECT N'PASS' AS ValidationResult,
       @CorrelationID AS CorrelationID,
       @AccidentAuditID AS AccidentAuditID,
       @RecoveryAuditID AS RecoveryAuditID,
       'C00012' AS CustomerID,
       @CurrentName AS RestoredCustomerName,
       @CurrentStatus AS RestoredStatus,
       @AccidentalName AS RetainedHistoricalAccident;

SELECT AuditID, EventTime, ActionType, ActorLogin, CorrelationID, OldValues, NewValues
FROM audit.DmlAudit
WHERE CorrelationID = @CorrelationID
ORDER BY EventTime, AuditID;

SELECT CustomerID, CustomerName, Email, Status, ValidFrom, ValidTo
FROM core.Customer FOR SYSTEM_TIME ALL
WHERE CustomerID = 'C00012'
  AND (CustomerName = @AccidentalName OR CustomerName = @OriginalName)
ORDER BY ValidFrom DESC;
GO
