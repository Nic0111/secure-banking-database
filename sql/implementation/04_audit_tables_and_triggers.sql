USE [$(DatabaseName)];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- Create storage for data-change audit records.
IF OBJECT_ID(N'audit.DmlAudit', N'U') IS NULL
BEGIN
    CREATE TABLE audit.DmlAudit
    (
        AuditID bigint IDENTITY(1, 1) NOT NULL CONSTRAINT PK_DmlAudit PRIMARY KEY,
        EventTime datetime2(3) NOT NULL CONSTRAINT DF_DmlAudit_EventTime DEFAULT (SYSUTCDATETIME()),
        ActionType varchar(6) NOT NULL,
        SchemaName sysname NOT NULL,
        TableName sysname NOT NULL,
        AffectedRowCount int NOT NULL,
        ActorLogin sysname NOT NULL,
        DatabaseUser sysname NOT NULL,
        ApplicationName nvarchar(128) NULL,
        HostName nvarchar(128) NULL,
        ClientAddress varchar(48) NULL,
        SessionID smallint NOT NULL,
        TransactionID bigint NULL,
        CorrelationID uniqueidentifier NULL,
        OldValues nvarchar(max) NULL,
        NewValues nvarchar(max) NULL,
        CONSTRAINT CK_DmlAudit_ActionType CHECK (ActionType IN ('INSERT', 'UPDATE', 'DELETE')),
        CONSTRAINT CK_DmlAudit_OldValuesJson CHECK (OldValues IS NULL OR ISJSON(OldValues) = 1),
        CONSTRAINT CK_DmlAudit_NewValuesJson CHECK (NewValues IS NULL OR ISJSON(NewValues) = 1)
    );

    CREATE INDEX IX_DmlAudit_EventTime ON audit.DmlAudit (EventTime DESC, AuditID DESC);
    CREATE INDEX IX_DmlAudit_Actor ON audit.DmlAudit (ActorLogin, EventTime DESC);
    CREATE INDEX IX_DmlAudit_Object ON audit.DmlAudit (SchemaName, TableName, EventTime DESC);
END;
GO

IF OBJECT_ID(N'audit.ApplicationEvent', N'U') IS NULL
BEGIN
    CREATE TABLE audit.ApplicationEvent
    (
        EventID bigint IDENTITY(1, 1) NOT NULL CONSTRAINT PK_ApplicationEvent PRIMARY KEY,
        EventTime datetime2(3) NOT NULL CONSTRAINT DF_ApplicationEvent_EventTime DEFAULT (SYSUTCDATETIME()),
        EventType varchar(40) NOT NULL,
        OperationName sysname NOT NULL,
        Succeeded bit NOT NULL,
        ActorLogin sysname NOT NULL,
        TargetType varchar(30) NULL,
        TargetID nvarchar(128) NULL,
        CorrelationID uniqueidentifier NULL,
        ErrorNumber int NULL,
        SafeDetails nvarchar(1000) NULL,
        ApplicationName nvarchar(128) NULL,
        HostName nvarchar(128) NULL,
        ClientAddress varchar(48) NULL,
        SessionID smallint NOT NULL
    );

    CREATE INDEX IX_ApplicationEvent_Time ON audit.ApplicationEvent (EventTime DESC, EventID DESC);
    CREATE INDEX IX_ApplicationEvent_Failures ON audit.ApplicationEvent (Succeeded, EventTime DESC)
        INCLUDE (ActorLogin, OperationName, ErrorNumber);
END;
GO

-- Record application-level events.
CREATE OR ALTER PROCEDURE audit.usp_LogApplicationEvent
    @EventType varchar(40),
    @OperationName sysname,
    @Succeeded bit,
    @TargetType varchar(30) = NULL,
    @TargetID nvarchar(128) = NULL,
    @CorrelationID uniqueidentifier = NULL,
    @ErrorNumber int = NULL,
    @SafeDetails nvarchar(1000) = NULL
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;

    INSERT audit.ApplicationEvent
    (
        EventType, OperationName, Succeeded, ActorLogin, TargetType, TargetID,
        CorrelationID, ErrorNumber, SafeDetails, ApplicationName, HostName,
        ClientAddress, SessionID
    )
    VALUES
    (
        @EventType, @OperationName, @Succeeded, ORIGINAL_LOGIN(), @TargetType, @TargetID,
        @CorrelationID, @ErrorNumber, @SafeDetails, APP_NAME(), HOST_NAME(),
        CONVERT(varchar(48), CONNECTIONPROPERTY('client_net_address')), @@SPID
    );
END;
GO

-- Prevent audit records from being changed or removed.
CREATE OR ALTER TRIGGER audit.trg_DmlAudit_Immutable
ON audit.DmlAudit
INSTEAD OF UPDATE, DELETE
AS
    THROW 50100, 'DML audit records are immutable.', 1;
GO

CREATE OR ALTER TRIGGER audit.trg_ApplicationEvent_Immutable
ON audit.ApplicationEvent
INSTEAD OF UPDATE, DELETE
AS
    THROW 50101, 'Application audit records are immutable.', 1;
GO

-- Audit changes to core banking records.
CREATE OR ALTER TRIGGER core.trg_Staff_DmlAudit
ON core.Staff
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Action varchar(6) = CASE WHEN EXISTS (SELECT 1 FROM inserted) AND EXISTS (SELECT 1 FROM deleted) THEN 'UPDATE'
                                     WHEN EXISTS (SELECT 1 FROM inserted) THEN 'INSERT' ELSE 'DELETE' END;
    INSERT audit.DmlAudit
    (ActionType, SchemaName, TableName, AffectedRowCount, ActorLogin, DatabaseUser, ApplicationName, HostName,
     ClientAddress, SessionID, TransactionID, CorrelationID, OldValues, NewValues)
    SELECT @Action, N'core', N'Staff', CASE WHEN @Action = 'DELETE' THEN (SELECT COUNT(*) FROM deleted) ELSE (SELECT COUNT(*) FROM inserted) END,
           ORIGINAL_LOGIN(), USER_NAME(), APP_NAME(), HOST_NAME(), CONVERT(varchar(48), CONNECTIONPROPERTY('client_net_address')),
           @@SPID, CURRENT_TRANSACTION_ID(), TRY_CONVERT(uniqueidentifier, SESSION_CONTEXT(N'CorrelationID')),
           CASE WHEN EXISTS (SELECT 1 FROM deleted) THEN (SELECT StaffID, StaffName, Phone, IsActive FROM deleted FOR JSON PATH, INCLUDE_NULL_VALUES) END,
           CASE WHEN EXISTS (SELECT 1 FROM inserted) THEN (SELECT StaffID, StaffName, Phone, IsActive FROM inserted FOR JSON PATH, INCLUDE_NULL_VALUES) END;
END;
GO

CREATE OR ALTER TRIGGER core.trg_StaffEmployment_DmlAudit
ON core.StaffEmployment
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Action varchar(6) = CASE WHEN EXISTS (SELECT 1 FROM inserted) AND EXISTS (SELECT 1 FROM deleted) THEN 'UPDATE'
                                     WHEN EXISTS (SELECT 1 FROM inserted) THEN 'INSERT' ELSE 'DELETE' END;
    INSERT audit.DmlAudit
    (ActionType, SchemaName, TableName, AffectedRowCount, ActorLogin, DatabaseUser, ApplicationName, HostName,
     ClientAddress, SessionID, TransactionID, CorrelationID, OldValues, NewValues)
    SELECT @Action, N'core', N'StaffEmployment', CASE WHEN @Action = 'DELETE' THEN (SELECT COUNT(*) FROM deleted) ELSE (SELECT COUNT(*) FROM inserted) END,
           ORIGINAL_LOGIN(), USER_NAME(), APP_NAME(), HOST_NAME(), CONVERT(varchar(48), CONNECTIONPROPERTY('client_net_address')),
           @@SPID, CURRENT_TRANSACTION_ID(), TRY_CONVERT(uniqueidentifier, SESSION_CONTEXT(N'CorrelationID')),
           CASE WHEN EXISTS (SELECT 1 FROM deleted) THEN (SELECT StaffID, Position, BranchID, SalaryLastChangedAt FROM deleted FOR JSON PATH, INCLUDE_NULL_VALUES) END,
           CASE WHEN EXISTS (SELECT 1 FROM inserted) THEN (SELECT StaffID, Position, BranchID, SalaryLastChangedAt FROM inserted FOR JSON PATH, INCLUDE_NULL_VALUES) END;
END;
GO

CREATE OR ALTER TRIGGER core.trg_Customer_DmlAudit
ON core.Customer
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Action varchar(6) = CASE WHEN EXISTS (SELECT 1 FROM inserted) AND EXISTS (SELECT 1 FROM deleted) THEN 'UPDATE'
                                     WHEN EXISTS (SELECT 1 FROM inserted) THEN 'INSERT' ELSE 'DELETE' END;
    INSERT audit.DmlAudit
    (ActionType, SchemaName, TableName, AffectedRowCount, ActorLogin, DatabaseUser, ApplicationName, HostName,
     ClientAddress, SessionID, TransactionID, CorrelationID, OldValues, NewValues)
    SELECT @Action, N'core', N'Customer', CASE WHEN @Action = 'DELETE' THEN (SELECT COUNT(*) FROM deleted) ELSE (SELECT COUNT(*) FROM inserted) END,
           ORIGINAL_LOGIN(), USER_NAME(), APP_NAME(), HOST_NAME(), CONVERT(varchar(48), CONNECTIONPROPERTY('client_net_address')),
           @@SPID, CURRENT_TRANSACTION_ID(), TRY_CONVERT(uniqueidentifier, SESSION_CONTEXT(N'CorrelationID')),
           CASE WHEN EXISTS (SELECT 1 FROM deleted) THEN (SELECT CustomerID, CustomerName, Email, Status FROM deleted FOR JSON PATH, INCLUDE_NULL_VALUES) END,
           CASE WHEN EXISTS (SELECT 1 FROM inserted) THEN (SELECT CustomerID, CustomerName, Email, Status FROM inserted FOR JSON PATH, INCLUDE_NULL_VALUES) END;
END;
GO

CREATE OR ALTER TRIGGER core.trg_Account_DmlAudit
ON core.Account
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Action varchar(6) = CASE WHEN EXISTS (SELECT 1 FROM inserted) AND EXISTS (SELECT 1 FROM deleted) THEN 'UPDATE'
                                     WHEN EXISTS (SELECT 1 FROM inserted) THEN 'INSERT' ELSE 'DELETE' END;
    INSERT audit.DmlAudit
    (ActionType, SchemaName, TableName, AffectedRowCount, ActorLogin, DatabaseUser, ApplicationName, HostName,
     ClientAddress, SessionID, TransactionID, CorrelationID, OldValues, NewValues)
    SELECT @Action, N'core', N'Account', CASE WHEN @Action = 'DELETE' THEN (SELECT COUNT(*) FROM deleted) ELSE (SELECT COUNT(*) FROM inserted) END,
           ORIGINAL_LOGIN(), USER_NAME(), APP_NAME(), HOST_NAME(), CONVERT(varchar(48), CONNECTIONPROPERTY('client_net_address')),
           @@SPID, CURRENT_TRANSACTION_ID(), TRY_CONVERT(uniqueidentifier, SESSION_CONTEXT(N'CorrelationID')),
           CASE WHEN EXISTS (SELECT 1 FROM deleted) THEN (SELECT AccountID, CustomerID, AccountType, Balance, Status FROM deleted FOR JSON PATH, INCLUDE_NULL_VALUES) END,
           CASE WHEN EXISTS (SELECT 1 FROM inserted) THEN (SELECT AccountID, CustomerID, AccountType, Balance, Status FROM inserted FOR JSON PATH, INCLUDE_NULL_VALUES) END;
END;
GO

CREATE OR ALTER TRIGGER core.trg_TransactionRecord_DmlAudit
ON core.TransactionRecord
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT audit.DmlAudit
    (ActionType, SchemaName, TableName, AffectedRowCount, ActorLogin, DatabaseUser, ApplicationName, HostName,
     ClientAddress, SessionID, TransactionID, CorrelationID, NewValues)
    SELECT 'INSERT', N'core', N'TransactionRecord', COUNT(*), ORIGINAL_LOGIN(), USER_NAME(), APP_NAME(), HOST_NAME(),
           CONVERT(varchar(48), CONNECTIONPROPERTY('client_net_address')), @@SPID, CURRENT_TRANSACTION_ID(),
           CASE WHEN COUNT(DISTINCT CorrelationID) = 1 THEN MIN(CorrelationID) END,
           (SELECT TransID, CorrelationID, CustomerID, AccountID, CounterpartyAccountID, TransDate,
                   Amount, Direction, TransactionType, BalanceAfter, ActorLogin, Channel
            FROM inserted FOR JSON PATH, INCLUDE_NULL_VALUES)
    FROM inserted;
END;
GO

-- Keep transaction records append-only.
CREATE OR ALTER TRIGGER core.trg_TransactionRecord_Immutable
ON core.TransactionRecord
INSTEAD OF UPDATE, DELETE
AS
    THROW 50102, 'Transaction records are append-only. Corrections must use a compensating transaction.', 1;
GO

-- Audit identity, PIN, and recovery-target changes.
CREATE OR ALTER TRIGGER sec.trg_PrincipalMap_DmlAudit
ON sec.PrincipalMap
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Action varchar(6) = CASE WHEN EXISTS (SELECT 1 FROM inserted) AND EXISTS (SELECT 1 FROM deleted) THEN 'UPDATE'
                                     WHEN EXISTS (SELECT 1 FROM inserted) THEN 'INSERT' ELSE 'DELETE' END;
    INSERT audit.DmlAudit
    (ActionType, SchemaName, TableName, AffectedRowCount, ActorLogin, DatabaseUser, ApplicationName, HostName,
     ClientAddress, SessionID, TransactionID, OldValues, NewValues)
    SELECT @Action, N'sec', N'PrincipalMap', CASE WHEN @Action = 'DELETE' THEN (SELECT COUNT(*) FROM deleted) ELSE (SELECT COUNT(*) FROM inserted) END,
           ORIGINAL_LOGIN(), USER_NAME(), APP_NAME(), HOST_NAME(), CONVERT(varchar(48), CONNECTIONPROPERTY('client_net_address')),
           @@SPID, CURRENT_TRANSACTION_ID(),
           CASE WHEN EXISTS (SELECT 1 FROM deleted) THEN (SELECT LoginName, DatabaseUserName, UserType, StaffID, CustomerID, IsActive, EffectiveFrom, EffectiveTo FROM deleted FOR JSON PATH, INCLUDE_NULL_VALUES) END,
           CASE WHEN EXISTS (SELECT 1 FROM inserted) THEN (SELECT LoginName, DatabaseUserName, UserType, StaffID, CustomerID, IsActive, EffectiveFrom, EffectiveTo FROM inserted FOR JSON PATH, INCLUDE_NULL_VALUES) END;
END;
GO

CREATE OR ALTER TRIGGER sec.trg_TransactionCredential_DmlAudit
ON sec.TransactionCredential
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Action varchar(6) = CASE WHEN EXISTS (SELECT 1 FROM inserted) AND EXISTS (SELECT 1 FROM deleted) THEN 'UPDATE'
                                     WHEN EXISTS (SELECT 1 FROM inserted) THEN 'INSERT' ELSE 'DELETE' END;
    INSERT audit.DmlAudit
    (ActionType, SchemaName, TableName, AffectedRowCount, ActorLogin, DatabaseUser, ApplicationName, HostName,
     ClientAddress, SessionID, TransactionID, OldValues, NewValues)
    SELECT @Action, N'sec', N'TransactionCredential', CASE WHEN @Action = 'DELETE' THEN (SELECT COUNT(*) FROM deleted) ELSE (SELECT COUNT(*) FROM inserted) END,
           ORIGINAL_LOGIN(), USER_NAME(), APP_NAME(), HOST_NAME(), CONVERT(varchar(48), CONNECTIONPROPERTY('client_net_address')),
           @@SPID, CURRENT_TRANSACTION_ID(),
           CASE WHEN EXISTS (SELECT 1 FROM deleted) THEN (SELECT LoginName, FailedAttempts, LockedUntil, LastChangedAt FROM deleted FOR JSON PATH, INCLUDE_NULL_VALUES) END,
           CASE WHEN EXISTS (SELECT 1 FROM inserted) THEN (SELECT LoginName, FailedAttempts, LockedUntil, LastChangedAt FROM inserted FOR JSON PATH, INCLUDE_NULL_VALUES) END;
END;
GO

CREATE OR ALTER TRIGGER demo.trg_RecoveryTarget_DmlAudit
ON demo.RecoveryTarget
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Action varchar(6) = CASE WHEN EXISTS (SELECT 1 FROM inserted) AND EXISTS (SELECT 1 FROM deleted) THEN 'UPDATE'
                                     WHEN EXISTS (SELECT 1 FROM inserted) THEN 'INSERT' ELSE 'DELETE' END;
    INSERT audit.DmlAudit
    (ActionType, SchemaName, TableName, AffectedRowCount, ActorLogin, DatabaseUser, ApplicationName, HostName,
     ClientAddress, SessionID, TransactionID, OldValues, NewValues)
    SELECT @Action, N'demo', N'RecoveryTarget', CASE WHEN @Action = 'DELETE' THEN (SELECT COUNT(*) FROM deleted) ELSE (SELECT COUNT(*) FROM inserted) END,
           ORIGINAL_LOGIN(), USER_NAME(), APP_NAME(), HOST_NAME(), CONVERT(varchar(48), CONNECTIONPROPERTY('client_net_address')),
           @@SPID, CURRENT_TRANSACTION_ID(),
           CASE WHEN EXISTS (SELECT 1 FROM deleted) THEN (SELECT RecoveryID, EvidenceText, CreatedAt FROM deleted FOR JSON PATH, INCLUDE_NULL_VALUES) END,
           CASE WHEN EXISTS (SELECT 1 FROM inserted) THEN (SELECT RecoveryID, EvidenceText, CreatedAt FROM inserted FOR JSON PATH, INCLUDE_NULL_VALUES) END;
END;
GO

-- Expose a readable audit view.
CREATE OR ALTER VIEW audit.vw_DmlAudit
AS
    SELECT AuditID, EventTime, ActionType, SchemaName, TableName, AffectedRowCount,
           ActorLogin, DatabaseUser, ApplicationName, HostName, ClientAddress,
           SessionID, TransactionID, CorrelationID, OldValues, NewValues
    FROM audit.DmlAudit;
GO
