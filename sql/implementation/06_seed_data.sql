USE [$(DatabaseName)];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- Seed the branch directory.
IF NOT EXISTS (SELECT 1 FROM core.Branch)
BEGIN
    INSERT core.Branch (BranchID, BranchName, City)
    VALUES ('B0001', N'Kuala Lumpur Central', N'Kuala Lumpur'),
           ('B0002', N'Petaling Jaya Digital', N'Petaling Jaya'),
           ('B0003', N'Shah Alam Service Centre', N'Shah Alam'),
           ('B0004', N'Cyberjaya Operations', N'Cyberjaya');
END;
GO

-- Seed staff and employment records.
IF NOT EXISTS (SELECT 1 FROM core.Staff)
BEGIN
    OPEN SYMMETRIC KEY SmartBank_Column_Key DECRYPTION BY CERTIFICATE SmartBank_Column_Certificate;

    INSERT core.Staff (StaffID, StaffName, Phone)
    VALUES ('S00001', N'Daniel Wong', '012-3101001'),
           ('S00002', N'Siti Aminah', '012-3101002'),
           ('S00003', N'Aisha Rahman', '012-3101003'),
           ('S00004', N'Farid Iskandar', '012-3101004'),
           ('S00005', N'Priya Nair', '012-3101005'),
           ('S00006', N'Lim Jia Wei', '012-3101006'),
           ('S00007', N'Nur Iman', '012-3101007');

    INSERT core.StaffEmployment (StaffID, Position, BranchID, SalaryCipher)
    VALUES
      ('S00001', 'BANK_MANAGER', 'B0001', EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), '11500.00')),
      ('S00002', 'BANK_MANAGER', 'B0002', EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), '10900.00')),
      ('S00003', 'DBA', 'B0001', EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), '9200.00')),
      ('S00004', 'BANK_OFFICER', 'B0001', EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), '5200.00')),
      ('S00005', 'BANK_OFFICER', 'B0002', EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), '5400.00')),
      ('S00006', 'BANK_OFFICER', 'B0003', EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), '5100.00')),
      ('S00007', 'BANK_OFFICER', 'B0004', EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), '5600.00'));

    CLOSE SYMMETRIC KEY SmartBank_Column_Key;
END;
GO

-- Seed customer records.
IF NOT EXISTS (SELECT 1 FROM core.Customer)
BEGIN
    OPEN SYMMETRIC KEY SmartBank_Column_Key DECRYPTION BY CERTIFICATE SmartBank_Column_Certificate;

    INSERT core.Customer
    (CustomerID, CustomerName, Email, ICNumberCipher, PhoneCipher, AddressCipher)
    VALUES
    ('C00001', N'Amelia Tan', 'amelia.tan@example.test',
       EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), '900101-14-1001'),
       EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), '012-4202001'),
       EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), N'12 Jalan Ampang, Kuala Lumpur')),
    ('C00002', N'Hafiz Zainal', 'hafiz.zainal@example.test',
       EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), '910202-10-2002'),
       EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), '012-4202002'),
       EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), N'8 Jalan Universiti, Petaling Jaya')),
    ('C00003', N'Siti Aisyah', 'siti.aisyah@example.test',
       EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), '920303-08-3003'),
       EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), '012-4202003'),
       EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), N'27 Persiaran Kayangan, Shah Alam')),
    ('C00004', N'Kumar Raj', 'kumar.raj@example.test',
       EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), '930404-10-4004'),
       EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), '012-4202004'),
       EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), N'5 Jalan PJU 1A, Petaling Jaya')),
    ('C00005', N'Mei Ling', 'mei.ling@example.test',
       EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), '940505-14-5005'),
       EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), '012-4202005'),
       EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), N'32 Jalan Sultan Ismail, Kuala Lumpur')),
    ('C00006', N'Arjun Menon', 'arjun.menon@example.test',
       EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), '950606-10-6006'),
       EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), '012-4202006'),
       EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), N'16 Jalan Teknokrat, Cyberjaya')),
    ('C00007', N'Nurul Huda', 'nurul.huda@example.test',
       EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), '960707-08-7007'),
       EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), '012-4202007'),
       EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), N'41 Jalan Tun Razak, Kuala Lumpur')),
    ('C00008', N'Jason Lee', 'jason.lee@example.test',
       EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), '970808-10-8008'),
       EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), '012-4202008'),
       EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), N'9 Persiaran Tropicana, Petaling Jaya')),
    ('C00009', N'Lavanya Devi', 'lavanya.devi@example.test',
       EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), '980909-10-9009'),
       EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), '012-4202009'),
       EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), N'18 Jalan Tengku Ampuan, Shah Alam')),
    ('C00010', N'Adam Firdaus', 'adam.firdaus@example.test',
       EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), '991010-14-1010'),
       EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), '012-4202010'),
       EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), N'23 Jalan Damansara, Kuala Lumpur')),
    ('C00011', N'Chong Wei Han', 'chong.weihan@example.test',
       EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), '001111-10-1111'),
       EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), '012-4202011'),
       EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), N'7 Jalan SS 2, Petaling Jaya')),
    ('C00012', N'Zara Ibrahim', 'zara.ibrahim@example.test',
       EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), '011212-08-1212'),
       EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), '012-4202012'),
       EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), N'55 Persiaran Multimedia, Cyberjaya'));

    CLOSE SYMMETRIC KEY SmartBank_Column_Key;
END;
GO

-- Seed customer accounts.
IF NOT EXISTS (SELECT 1 FROM core.Account)
BEGIN
    INSERT core.Account (AccountID, CustomerID, AccountType)
    VALUES ('A000000001', 'C00001', 'SAVINGS'),
           ('A000000002', 'C00001', 'CURRENT'),
           ('A000000003', 'C00002', 'SAVINGS'),
           ('A000000004', 'C00002', 'CURRENT'),
           ('A000000005', 'C00003', 'SAVINGS'),
           ('A000000006', 'C00003', 'FIXED_DEPOSIT'),
           ('A000000007', 'C00004', 'SAVINGS'),
           ('A000000008', 'C00004', 'CURRENT'),
           ('A000000009', 'C00005', 'SAVINGS'),
           ('A000000010', 'C00005', 'FIXED_DEPOSIT'),
           ('A000000011', 'C00006', 'SAVINGS'),
           ('A000000012', 'C00006', 'CURRENT'),
           ('A000000013', 'C00007', 'SAVINGS'),
           ('A000000014', 'C00008', 'SAVINGS'),
           ('A000000015', 'C00009', 'SAVINGS'),
           ('A000000016', 'C00010', 'SAVINGS'),
           ('A000000017', 'C00011', 'CURRENT'),
           ('A000000018', 'C00012', 'SAVINGS');
END;
GO

-- Map the demonstration logins to their identities.
MERGE sec.PrincipalMap AS target
USING (VALUES
    (CONVERT(sysname, N'sb_dba_aisha'), CONVERT(sysname, N'sb_dba_aisha'), 'DBA', 'S00003', CONVERT(char(6), NULL)),
    (CONVERT(sysname, N'sb_manager_daniel'), CONVERT(sysname, N'sb_manager_daniel'), 'MANAGER', 'S00001', CONVERT(char(6), NULL)),
    (CONVERT(sysname, N'sb_manager_siti'), CONVERT(sysname, N'sb_manager_siti'), 'MANAGER', 'S00002', CONVERT(char(6), NULL)),
    (CONVERT(sysname, N'sb_officer_farid'), CONVERT(sysname, N'sb_officer_farid'), 'OFFICER', 'S00004', CONVERT(char(6), NULL)),
    (CONVERT(sysname, N'sb_officer_priya'), CONVERT(sysname, N'sb_officer_priya'), 'OFFICER', 'S00005', CONVERT(char(6), NULL)),
    (CONVERT(sysname, N'sb_customer_amelia'), CONVERT(sysname, N'sb_customer_amelia'), 'CUSTOMER', CONVERT(char(6), NULL), 'C00001'),
    (CONVERT(sysname, N'sb_customer_hafiz'), CONVERT(sysname, N'sb_customer_hafiz'), 'CUSTOMER', CONVERT(char(6), NULL), 'C00002'),
    (CONVERT(sysname, N'sb_auditor_noor'), CONVERT(sysname, N'sb_auditor_noor'), 'AUDITOR', CONVERT(char(6), NULL), CONVERT(char(6), NULL))
) AS source (LoginName, DatabaseUserName, UserType, StaffID, CustomerID)
ON target.LoginName = source.LoginName
WHEN MATCHED THEN UPDATE SET DatabaseUserName = source.DatabaseUserName, UserType = source.UserType,
                             StaffID = source.StaffID, CustomerID = source.CustomerID, IsActive = 1, EffectiveTo = NULL
WHEN NOT MATCHED THEN INSERT (LoginName, DatabaseUserName, UserType, StaffID, CustomerID)
VALUES (source.LoginName, source.DatabaseUserName, source.UserType, source.StaffID, source.CustomerID);
GO

-- Seed the demonstration transaction PINs.
IF NOT EXISTS (SELECT 1 FROM sec.TransactionCredential)
BEGIN
    DECLARE @Pin varchar(12) = '$(DemoTransactionPin)';
    DECLARE @Salt1 varbinary(32) = CRYPT_GEN_RANDOM(32);
    DECLARE @Salt2 varbinary(32) = CRYPT_GEN_RANDOM(32);

    INSERT sec.TransactionCredential (LoginName, Salt, PinHash)
    VALUES (N'sb_customer_amelia', @Salt1, HASHBYTES('SHA2_512', @Salt1 + CONVERT(varbinary(32), @Pin))),
           (N'sb_customer_hafiz', @Salt2, HASHBYTES('SHA2_512', @Salt2 + CONVERT(varbinary(32), @Pin)));
END;
GO

-- Seed a small transaction history and hash chain.
IF NOT EXISTS (SELECT 1 FROM core.TransactionRecord)
BEGIN
    DECLARE @SeedAccounts table
    (
        SequenceNo int IDENTITY(1, 1) PRIMARY KEY,
        AccountID varchar(10) NOT NULL,
        CustomerID char(6) NOT NULL
    );
    INSERT @SeedAccounts (AccountID, CustomerID)
        SELECT AccountID, CustomerID FROM core.Account ORDER BY AccountID;

    DECLARE @SequenceNo int, @AccountID varchar(10), @CustomerID char(6), @Amount decimal(19, 2),
            @Balance decimal(19, 2), @CorrelationID uniqueidentifier, @TransDate datetime2(3);
    DECLARE seed_account_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT SequenceNo, AccountID, CustomerID FROM @SeedAccounts ORDER BY SequenceNo;

    OPEN seed_account_cursor;
    FETCH NEXT FROM seed_account_cursor INTO @SequenceNo, @AccountID, @CustomerID;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @Amount = 1250 + (@SequenceNo * 275);
        SET @CorrelationID = NEWID();
        SET @TransDate = DATEADD(DAY, -40 + @SequenceNo, SYSUTCDATETIME());
        BEGIN TRANSACTION;
        UPDATE core.Account SET Balance = @Amount WHERE AccountID = @AccountID;
        SET @Balance = @Amount;
        EXEC core.usp_AppendLedgerEntry @CorrelationID, @CustomerID, @AccountID, NULL, @TransDate,
             @Amount, 'CREDIT', 'DEPOSIT', @Balance, N'seed_deployment', 'SYSTEM';
        COMMIT TRANSACTION;
        FETCH NEXT FROM seed_account_cursor INTO @SequenceNo, @AccountID, @CustomerID;
    END;
    CLOSE seed_account_cursor;
    DEALLOCATE seed_account_cursor;

    DECLARE withdrawal_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT TOP (10) SequenceNo, AccountID, CustomerID FROM @SeedAccounts ORDER BY SequenceNo;
    OPEN withdrawal_cursor;
    FETCH NEXT FROM withdrawal_cursor INTO @SequenceNo, @AccountID, @CustomerID;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @Amount = 40 + (@SequenceNo * 10);
        SET @CorrelationID = NEWID();
        SET @TransDate = DATEADD(DAY, -15 + @SequenceNo, SYSUTCDATETIME());
        BEGIN TRANSACTION;
        UPDATE core.Account SET Balance = Balance - @Amount WHERE AccountID = @AccountID;
        SELECT @Balance = Balance FROM core.Account WHERE AccountID = @AccountID;
        EXEC core.usp_AppendLedgerEntry @CorrelationID, @CustomerID, @AccountID, NULL, @TransDate,
             @Amount, 'DEBIT', 'WITHDRAWAL', @Balance, N'seed_deployment', 'SYSTEM';
        COMMIT TRANSACTION;
        FETCH NEXT FROM withdrawal_cursor INTO @SequenceNo, @AccountID, @CustomerID;
    END;
    CLOSE withdrawal_cursor;
    DEALLOCATE withdrawal_cursor;

    DECLARE @Transfers table
    (
        SequenceNo int IDENTITY(1, 1) PRIMARY KEY,
        SourceAccountID varchar(10), DestinationAccountID varchar(10), Amount decimal(19, 2)
    );
    INSERT @Transfers (SourceAccountID, DestinationAccountID, Amount)
    VALUES ('A000000001', 'A000000003', 125.00),
           ('A000000004', 'A000000005', 210.00),
           ('A000000007', 'A000000009', 180.00),
           ('A000000010', 'A000000011', 325.00),
           ('A000000013', 'A000000014', 95.00),
           ('A000000015', 'A000000016', 150.00),
           ('A000000017', 'A000000018', 275.00),
           ('A000000002', 'A000000012', 220.00);

    DECLARE @SourceAccountID varchar(10), @DestinationAccountID varchar(10),
            @SourceCustomerID char(6), @DestinationCustomerID char(6),
            @SourceBalance decimal(19, 2), @DestinationBalance decimal(19, 2);
    DECLARE transfer_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT SequenceNo, SourceAccountID, DestinationAccountID, Amount FROM @Transfers ORDER BY SequenceNo;
    OPEN transfer_cursor;
    FETCH NEXT FROM transfer_cursor INTO @SequenceNo, @SourceAccountID, @DestinationAccountID, @Amount;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SELECT @SourceCustomerID = CustomerID FROM core.Account WHERE AccountID = @SourceAccountID;
        SELECT @DestinationCustomerID = CustomerID FROM core.Account WHERE AccountID = @DestinationAccountID;
        SET @CorrelationID = NEWID();
        SET @TransDate = DATEADD(DAY, -8 + @SequenceNo, SYSUTCDATETIME());
        BEGIN TRANSACTION;
        UPDATE core.Account SET Balance = Balance - @Amount WHERE AccountID = @SourceAccountID;
        UPDATE core.Account SET Balance = Balance + @Amount WHERE AccountID = @DestinationAccountID;
        SELECT @SourceBalance = Balance FROM core.Account WHERE AccountID = @SourceAccountID;
        SELECT @DestinationBalance = Balance FROM core.Account WHERE AccountID = @DestinationAccountID;
        EXEC core.usp_AppendLedgerEntry @CorrelationID, @SourceCustomerID, @SourceAccountID, @DestinationAccountID,
             @TransDate, @Amount, 'DEBIT', 'TRANSFER', @SourceBalance, N'seed_deployment', 'SYSTEM';
        EXEC core.usp_AppendLedgerEntry @CorrelationID, @DestinationCustomerID, @DestinationAccountID, @SourceAccountID,
             @TransDate, @Amount, 'CREDIT', 'TRANSFER', @DestinationBalance, N'seed_deployment', 'SYSTEM';
        COMMIT TRANSACTION;
        FETCH NEXT FROM transfer_cursor INTO @SequenceNo, @SourceAccountID, @DestinationAccountID, @Amount;
    END;
    CLOSE transfer_cursor;
    DEALLOCATE transfer_cursor;
END;
GO

-- Seed a recovery record for the restore demonstration.
IF NOT EXISTS (SELECT 1 FROM demo.RecoveryTarget)
BEGIN
    INSERT demo.RecoveryTarget (RecoveryID, EvidenceText)
    VALUES (1, N'PITR evidence row 01 - preserve before lecturer deletion'),
           (2, N'PITR evidence row 02 - preserve before lecturer deletion'),
           (3, N'PITR evidence row 03 - preserve before lecturer deletion'),
           (4, N'PITR evidence row 04 - preserve before lecturer deletion'),
           (5, N'PITR evidence row 05 - preserve before lecturer deletion'),
           (6, N'PITR evidence row 06 - preserve before lecturer deletion'),
           (7, N'PITR evidence row 07 - preserve before lecturer deletion'),
           (8, N'PITR evidence row 08 - preserve before lecturer deletion'),
           (9, N'PITR evidence row 09 - preserve before lecturer deletion'),
           (10, N'PITR evidence row 10 - preserve before lecturer deletion');
END;
GO
