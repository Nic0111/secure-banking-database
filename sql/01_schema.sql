USE [$(DatabaseName)];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID(N'core.Branch', N'U') IS NULL
BEGIN
    CREATE TABLE core.Branch
    (
        BranchID char(5) NOT NULL CONSTRAINT PK_Branch PRIMARY KEY,
        BranchName nvarchar(100) NOT NULL CONSTRAINT UQ_Branch_BranchName UNIQUE,
        City nvarchar(60) NOT NULL,
        IsActive bit NOT NULL CONSTRAINT DF_Branch_IsActive DEFAULT (1),
        CreatedAt datetime2(3) NOT NULL CONSTRAINT DF_Branch_CreatedAt DEFAULT (SYSUTCDATETIME())
    );
END;
GO

IF OBJECT_ID(N'core.Staff', N'U') IS NULL
BEGIN
    CREATE TABLE core.Staff
    (
        StaffID char(6) NOT NULL CONSTRAINT PK_Staff PRIMARY KEY,
        StaffName nvarchar(100) NOT NULL,
        Phone varchar(20) NOT NULL,
        IsActive bit NOT NULL CONSTRAINT DF_Staff_IsActive DEFAULT (1),
        ValidFrom datetime2(3) GENERATED ALWAYS AS ROW START NOT NULL,
        ValidTo datetime2(3) GENERATED ALWAYS AS ROW END NOT NULL,
        PERIOD FOR SYSTEM_TIME (ValidFrom, ValidTo),
        CONSTRAINT CK_Staff_ID CHECK (StaffID LIKE 'S[0-9][0-9][0-9][0-9][0-9]'),
        CONSTRAINT CK_Staff_Phone CHECK (LEN(Phone) BETWEEN 9 AND 20)
    )
    WITH (SYSTEM_VERSIONING = ON
        (HISTORY_TABLE = history.StaffHistory, DATA_CONSISTENCY_CHECK = ON));
END;
GO

IF OBJECT_ID(N'core.StaffEmployment', N'U') IS NULL
BEGIN
    CREATE TABLE core.StaffEmployment
    (
        StaffID char(6) NOT NULL CONSTRAINT PK_StaffEmployment PRIMARY KEY,
        Position varchar(20) NOT NULL,
        BranchID char(5) NOT NULL,
        SalaryCipher varbinary(512) NOT NULL,
        SalaryLastChangedAt datetime2(3) NOT NULL CONSTRAINT DF_StaffEmployment_SalaryChanged DEFAULT (SYSUTCDATETIME()),
        ValidFrom datetime2(3) GENERATED ALWAYS AS ROW START NOT NULL,
        ValidTo datetime2(3) GENERATED ALWAYS AS ROW END NOT NULL,
        PERIOD FOR SYSTEM_TIME (ValidFrom, ValidTo),
        CONSTRAINT FK_StaffEmployment_Staff FOREIGN KEY (StaffID) REFERENCES core.Staff (StaffID),
        CONSTRAINT FK_StaffEmployment_Branch FOREIGN KEY (BranchID) REFERENCES core.Branch (BranchID),
        CONSTRAINT CK_StaffEmployment_Position CHECK (Position IN ('DBA', 'BANK_MANAGER', 'BANK_OFFICER'))
    )
    WITH (SYSTEM_VERSIONING = ON
        (HISTORY_TABLE = history.StaffEmploymentHistory, DATA_CONSISTENCY_CHECK = ON));
END;
GO

IF OBJECT_ID(N'core.Customer', N'U') IS NULL
BEGIN
    CREATE TABLE core.Customer
    (
        CustomerID char(6) NOT NULL CONSTRAINT PK_Customer PRIMARY KEY,
        CustomerName nvarchar(100) MASKED WITH (FUNCTION = 'partial(1,"XXXX",1)') NOT NULL,
        Email varchar(254) MASKED WITH (FUNCTION = 'email()') NOT NULL,
        ICNumberCipher varbinary(512) NOT NULL,
        PhoneCipher varbinary(512) NOT NULL,
        AddressCipher varbinary(1024) NOT NULL,
        Status varchar(12) NOT NULL CONSTRAINT DF_Customer_Status DEFAULT ('ACTIVE'),
        CreatedAt datetime2(3) NOT NULL CONSTRAINT DF_Customer_CreatedAt DEFAULT (SYSUTCDATETIME()),
        ValidFrom datetime2(3) GENERATED ALWAYS AS ROW START NOT NULL,
        ValidTo datetime2(3) GENERATED ALWAYS AS ROW END NOT NULL,
        PERIOD FOR SYSTEM_TIME (ValidFrom, ValidTo),
        CONSTRAINT UQ_Customer_Email UNIQUE (Email),
        CONSTRAINT CK_Customer_ID CHECK (CustomerID LIKE 'C[0-9][0-9][0-9][0-9][0-9]'),
        CONSTRAINT CK_Customer_Status CHECK (Status IN ('ACTIVE', 'SUSPENDED', 'CLOSED'))
    )
    WITH (SYSTEM_VERSIONING = ON
        (HISTORY_TABLE = history.CustomerHistory, DATA_CONSISTENCY_CHECK = ON));
END;
GO

IF OBJECT_ID(N'core.Account', N'U') IS NULL
BEGIN
    CREATE TABLE core.Account
    (
        AccountID varchar(10) NOT NULL CONSTRAINT PK_Account PRIMARY KEY,
        CustomerID char(6) NOT NULL,
        AccountType varchar(20) NOT NULL,
        Balance decimal(19, 2) NOT NULL CONSTRAINT DF_Account_Balance DEFAULT (0),
        Status varchar(12) NOT NULL CONSTRAINT DF_Account_Status DEFAULT ('ACTIVE'),
        OpenedAt datetime2(3) NOT NULL CONSTRAINT DF_Account_OpenedAt DEFAULT (SYSUTCDATETIME()),
        RowVersion rowversion NOT NULL,
        ValidFrom datetime2(3) GENERATED ALWAYS AS ROW START NOT NULL,
        ValidTo datetime2(3) GENERATED ALWAYS AS ROW END NOT NULL,
        PERIOD FOR SYSTEM_TIME (ValidFrom, ValidTo),
        CONSTRAINT FK_Account_Customer FOREIGN KEY (CustomerID) REFERENCES core.Customer (CustomerID),
        CONSTRAINT CK_Account_Type CHECK (AccountType IN ('SAVINGS', 'CURRENT', 'FIXED_DEPOSIT')),
        CONSTRAINT CK_Account_Balance CHECK (Balance >= 0),
        CONSTRAINT CK_Account_Status CHECK (Status IN ('ACTIVE', 'FROZEN', 'CLOSED'))
    )
    WITH (SYSTEM_VERSIONING = ON
        (HISTORY_TABLE = history.AccountHistory, DATA_CONSISTENCY_CHECK = ON));

    CREATE INDEX IX_Account_CustomerID ON core.Account (CustomerID, Status) INCLUDE (AccountType, Balance);
END;
GO

IF OBJECT_ID(N'core.TransactionRecord', N'U') IS NULL
BEGIN
    CREATE TABLE core.TransactionRecord
    (
        TransID bigint IDENTITY(1, 1) NOT NULL CONSTRAINT PK_TransactionRecord PRIMARY KEY,
        CorrelationID uniqueidentifier NOT NULL,
        CustomerID char(6) NOT NULL,
        AccountID varchar(10) NOT NULL,
        CounterpartyAccountID varchar(10) NULL,
        TransDate datetime2(3) NOT NULL CONSTRAINT DF_TransactionRecord_TransDate DEFAULT (SYSUTCDATETIME()),
        Amount decimal(19, 2) NOT NULL,
        Direction varchar(6) NOT NULL,
        TransactionType varchar(10) NOT NULL,
        BalanceAfter decimal(19, 2) NOT NULL,
        ActorLogin sysname NOT NULL,
        Channel varchar(12) NOT NULL CONSTRAINT DF_TransactionRecord_Channel DEFAULT ('DATABASE'),
        PreviousHash varbinary(64) NULL,
        RecordHash varbinary(64) NOT NULL,
        CONSTRAINT FK_TransactionRecord_Customer FOREIGN KEY (CustomerID) REFERENCES core.Customer (CustomerID),
        CONSTRAINT FK_TransactionRecord_Account FOREIGN KEY (AccountID) REFERENCES core.Account (AccountID),
        CONSTRAINT FK_TransactionRecord_Counterparty FOREIGN KEY (CounterpartyAccountID) REFERENCES core.Account (AccountID),
        CONSTRAINT UQ_TransactionRecord_RecordHash UNIQUE (RecordHash),
        CONSTRAINT CK_TransactionRecord_Amount CHECK (Amount > 0),
        CONSTRAINT CK_TransactionRecord_Balance CHECK (BalanceAfter >= 0),
        CONSTRAINT CK_TransactionRecord_Direction CHECK (Direction IN ('CREDIT', 'DEBIT')),
        CONSTRAINT CK_TransactionRecord_Type CHECK (TransactionType IN ('DEPOSIT', 'WITHDRAWAL', 'TRANSFER')),
        CONSTRAINT CK_TransactionRecord_Channel CHECK (Channel IN ('DATABASE', 'ONLINE', 'ATM', 'MOBILE', 'SYSTEM')),
        CONSTRAINT CK_TransactionRecord_Semantics CHECK
        (
            (TransactionType = 'DEPOSIT' AND Direction = 'CREDIT' AND CounterpartyAccountID IS NULL)
            OR (TransactionType = 'WITHDRAWAL' AND Direction = 'DEBIT' AND CounterpartyAccountID IS NULL)
            OR (TransactionType = 'TRANSFER' AND CounterpartyAccountID IS NOT NULL AND CounterpartyAccountID <> AccountID)
        )
    );

    CREATE INDEX IX_TransactionRecord_CustomerDate
        ON core.TransactionRecord (CustomerID, TransDate DESC) INCLUDE (AccountID, Amount, Direction, TransactionType);
    CREATE INDEX IX_TransactionRecord_AccountDate
        ON core.TransactionRecord (AccountID, TransDate DESC) INCLUDE (Amount, Direction, TransactionType, BalanceAfter);
    CREATE INDEX IX_TransactionRecord_CorrelationID
        ON core.TransactionRecord (CorrelationID, TransID);
END;
GO

IF OBJECT_ID(N'sec.PrincipalMap', N'U') IS NULL
BEGIN
    CREATE TABLE sec.PrincipalMap
    (
        LoginName sysname NOT NULL CONSTRAINT PK_PrincipalMap PRIMARY KEY,
        DatabaseUserName sysname NOT NULL CONSTRAINT UQ_PrincipalMap_DatabaseUser UNIQUE,
        UserType varchar(12) NOT NULL,
        StaffID char(6) NULL,
        CustomerID char(6) NULL,
        IsActive bit NOT NULL CONSTRAINT DF_PrincipalMap_IsActive DEFAULT (1),
        EffectiveFrom datetime2(3) NOT NULL CONSTRAINT DF_PrincipalMap_EffectiveFrom DEFAULT (SYSUTCDATETIME()),
        EffectiveTo datetime2(3) NULL,
        CONSTRAINT FK_PrincipalMap_Staff FOREIGN KEY (StaffID) REFERENCES core.Staff (StaffID),
        CONSTRAINT FK_PrincipalMap_Customer FOREIGN KEY (CustomerID) REFERENCES core.Customer (CustomerID),
        CONSTRAINT CK_PrincipalMap_UserType CHECK (UserType IN ('DBA', 'MANAGER', 'OFFICER', 'CUSTOMER', 'AUDITOR')),
        CONSTRAINT CK_PrincipalMap_Identity CHECK
        (
            (UserType IN ('DBA', 'MANAGER', 'OFFICER') AND StaffID IS NOT NULL AND CustomerID IS NULL)
            OR (UserType = 'CUSTOMER' AND StaffID IS NULL AND CustomerID IS NOT NULL)
            OR (UserType = 'AUDITOR' AND StaffID IS NULL AND CustomerID IS NULL)
        ),
        CONSTRAINT CK_PrincipalMap_EffectiveDates CHECK (EffectiveTo IS NULL OR EffectiveTo > EffectiveFrom)
    );
END;
GO

IF OBJECT_ID(N'sec.TransactionCredential', N'U') IS NULL
BEGIN
    CREATE TABLE sec.TransactionCredential
    (
        LoginName sysname NOT NULL CONSTRAINT PK_TransactionCredential PRIMARY KEY,
        Salt varbinary(32) NOT NULL,
        PinHash varbinary(64) NOT NULL,
        FailedAttempts tinyint NOT NULL CONSTRAINT DF_TransactionCredential_FailedAttempts DEFAULT (0),
        LockedUntil datetime2(3) NULL,
        LastChangedAt datetime2(3) NOT NULL CONSTRAINT DF_TransactionCredential_LastChanged DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_TransactionCredential_PrincipalMap FOREIGN KEY (LoginName) REFERENCES sec.PrincipalMap (LoginName),
        CONSTRAINT CK_TransactionCredential_FailedAttempts CHECK (FailedAttempts BETWEEN 0 AND 5)
    );
END;
GO

IF OBJECT_ID(N'ops.LedgerChain', N'U') IS NULL
BEGIN
    CREATE TABLE ops.LedgerChain
    (
        ChainID tinyint NOT NULL CONSTRAINT PK_LedgerChain PRIMARY KEY,
        LastTransID bigint NULL,
        LastHash varbinary(64) NULL,
        UpdatedAt datetime2(3) NOT NULL CONSTRAINT DF_LedgerChain_UpdatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT CK_LedgerChain_Singleton CHECK (ChainID = 1)
    );
    INSERT ops.LedgerChain (ChainID) VALUES (1);
END;
GO

IF OBJECT_ID(N'demo.RecoveryTarget', N'U') IS NULL
BEGIN
    CREATE TABLE demo.RecoveryTarget
    (
        RecoveryID int NOT NULL CONSTRAINT PK_RecoveryTarget PRIMARY KEY,
        EvidenceText nvarchar(200) NOT NULL,
        CreatedAt datetime2(3) NOT NULL CONSTRAINT DF_RecoveryTarget_CreatedAt DEFAULT (SYSUTCDATETIME())
    );
END;
GO

ADD SENSITIVITY CLASSIFICATION TO core.StaffEmployment.SalaryCipher
    WITH (LABEL = 'Highly Confidential', INFORMATION_TYPE = 'Financial', RANK = CRITICAL);
ADD SENSITIVITY CLASSIFICATION TO core.Customer.CustomerName
    WITH (LABEL = 'Confidential', INFORMATION_TYPE = 'Name', RANK = HIGH);
ADD SENSITIVITY CLASSIFICATION TO core.Customer.Email
    WITH (LABEL = 'Confidential', INFORMATION_TYPE = 'Contact Info', RANK = HIGH);
ADD SENSITIVITY CLASSIFICATION TO core.Customer.ICNumberCipher
    WITH (LABEL = 'Highly Confidential', INFORMATION_TYPE = 'National ID', RANK = CRITICAL);
ADD SENSITIVITY CLASSIFICATION TO core.Customer.PhoneCipher
    WITH (LABEL = 'Confidential', INFORMATION_TYPE = 'Contact Info', RANK = HIGH);
ADD SENSITIVITY CLASSIFICATION TO core.Customer.AddressCipher
    WITH (LABEL = 'Confidential', INFORMATION_TYPE = 'Contact Info', RANK = HIGH);
ADD SENSITIVITY CLASSIFICATION TO core.Account.Balance
    WITH (LABEL = 'Highly Confidential', INFORMATION_TYPE = 'Financial', RANK = CRITICAL);
GO
