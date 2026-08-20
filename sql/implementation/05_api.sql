USE [$(DatabaseName)];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- Append a transaction and extend the tamper-evident hash chain.
CREATE OR ALTER PROCEDURE core.usp_AppendLedgerEntry
    @CorrelationID uniqueidentifier,
    @CustomerID char(6),
    @AccountID varchar(10),
    @CounterpartyAccountID varchar(10) = NULL,
    @TransDate datetime2(3),
    @Amount decimal(19, 2),
    @Direction varchar(6),
    @TransactionType varchar(10),
    @BalanceAfter decimal(19, 2),
    @ActorLogin sysname,
    @Channel varchar(12)
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @@TRANCOUNT = 0
        THROW 50200, 'Ledger entries must be appended inside an active transaction.', 1;

    DECLARE @PreviousHash varbinary(64);
    DECLARE @RecordHash varbinary(64);
    DECLARE @Payload nvarchar(4000);
    DECLARE @TransID bigint;

    SELECT @PreviousHash = LastHash
    FROM ops.LedgerChain WITH (UPDLOCK, HOLDLOCK)
    WHERE ChainID = 1;

    SET @Payload = CONCAT
    (
        CONVERT(char(36), @CorrelationID), N'|', @CustomerID, N'|', @AccountID, N'|',
        COALESCE(@CounterpartyAccountID, N''), N'|', CONVERT(varchar(33), @TransDate, 126), N'|',
        CONVERT(varchar(40), @Amount), N'|', @Direction, N'|', @TransactionType, N'|',
        CONVERT(varchar(40), @BalanceAfter), N'|', @ActorLogin, N'|', @Channel, N'|',
        COALESCE(CONVERT(varchar(128), @PreviousHash, 2), N'GENESIS')
    );
    SET @RecordHash = HASHBYTES('SHA2_512', CONVERT(varbinary(max), @Payload));

    INSERT core.TransactionRecord
    (
        CorrelationID, CustomerID, AccountID, CounterpartyAccountID, TransDate,
        Amount, Direction, TransactionType, BalanceAfter, ActorLogin, Channel,
        PreviousHash, RecordHash
    )
    VALUES
    (
        @CorrelationID, @CustomerID, @AccountID, @CounterpartyAccountID, @TransDate,
        @Amount, @Direction, @TransactionType, @BalanceAfter, @ActorLogin, @Channel,
        @PreviousHash, @RecordHash
    );

    SET @TransID = CONVERT(bigint, SCOPE_IDENTITY());
    UPDATE ops.LedgerChain
    SET LastTransID = @TransID,
        LastHash = @RecordHash,
        UpdatedAt = SYSUTCDATETIME()
    WHERE ChainID = 1;
END;
GO

-- Provide read-only directory and account views.
CREATE OR ALTER VIEW api.vw_StaffDirectory
AS
    SELECT StaffID, StaffName, Phone
    FROM core.Staff
    WHERE IsActive = 1;
GO

CREATE OR ALTER VIEW api.vw_CustomerAccountSummary
AS
    SELECT account.AccountID,
           account.CustomerID,
           customer.CustomerName,
           customer.Email,
           account.AccountType,
           account.Balance,
           account.Status,
           account.OpenedAt
    FROM core.Account AS account
    INNER JOIN core.Customer AS customer ON customer.CustomerID = account.CustomerID;
GO

CREATE OR ALTER VIEW api.vw_MyAccounts
AS
    SELECT AccountID, CustomerID, AccountType, Balance, Status, OpenedAt
    FROM core.Account;
GO

CREATE OR ALTER VIEW api.vw_MyTransactions
AS
    SELECT TransID, CorrelationID, CustomerID, AccountID, CounterpartyAccountID,
           TransDate, Amount, Direction, TransactionType, BalanceAfter, Channel
    FROM core.TransactionRecord;
GO

-- Return the current user's staff or customer profile.
CREATE OR ALTER PROCEDURE api.usp_GetMyStaffProfile
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @StaffID char(6);

    SELECT @StaffID = StaffID
    FROM sec.PrincipalMap
    WHERE LoginName = ORIGINAL_LOGIN()
      AND UserType IN ('DBA', 'MANAGER', 'OFFICER')
      AND IsActive = 1
      AND (EffectiveTo IS NULL OR EffectiveTo > SYSUTCDATETIME());

    IF @StaffID IS NULL
        THROW 50201, 'No active staff identity is mapped to this login.', 1;

    SELECT staff.StaffID, staff.StaffName, employment.Position, branch.BranchName,
           staff.Phone,
           TRY_CONVERT(decimal(19, 2), CONVERT(varchar(50),
               DecryptByKeyAutoCert(CERT_ID(N'SmartBank_Column_Certificate'), NULL, employment.SalaryCipher))) AS Salary,
           staff.IsActive
    FROM core.Staff AS staff
    INNER JOIN core.StaffEmployment AS employment ON employment.StaffID = staff.StaffID
    INNER JOIN core.Branch AS branch ON branch.BranchID = employment.BranchID
    WHERE staff.StaffID = @StaffID;
END;
GO

-- Let managers view the staff they supervise.
CREATE OR ALTER PROCEDURE api.usp_ManagerGetStaffProfiles
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ManagerStaffID char(6);

    SELECT @ManagerStaffID = StaffID
    FROM sec.PrincipalMap
    WHERE LoginName = ORIGINAL_LOGIN() AND UserType = 'MANAGER' AND IsActive = 1;

    IF @ManagerStaffID IS NULL
        THROW 50202, 'Only an active bank manager may view staff employment profiles.', 1;

    SELECT staff.StaffID, staff.StaffName, employment.Position, branch.BranchName,
           staff.Phone,
           TRY_CONVERT(decimal(19, 2), CONVERT(varchar(50),
               DecryptByKeyAutoCert(CERT_ID(N'SmartBank_Column_Certificate'), NULL, employment.SalaryCipher))) AS Salary,
           staff.IsActive
    FROM core.Staff AS staff
    INNER JOIN core.StaffEmployment AS employment ON employment.StaffID = staff.StaffID
    INNER JOIN core.Branch AS branch ON branch.BranchID = employment.BranchID
    WHERE employment.Position = 'BANK_OFFICER'
    ORDER BY employment.Position, staff.StaffID;
END;
GO

CREATE OR ALTER PROCEDURE api.usp_GetMyCustomerProfile
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @CustomerID char(6);

    SELECT @CustomerID = CustomerID
    FROM sec.PrincipalMap
    WHERE LoginName = ORIGINAL_LOGIN()
      AND UserType = 'CUSTOMER'
      AND IsActive = 1
      AND (EffectiveTo IS NULL OR EffectiveTo > SYSUTCDATETIME());

    IF @CustomerID IS NULL
        THROW 50203, 'No active customer identity is mapped to this login.', 1;

    SELECT CustomerID,
           CustomerName,
           Email,
           CONVERT(varchar(20), DecryptByKeyAutoCert(CERT_ID(N'SmartBank_Column_Certificate'), NULL, ICNumberCipher)) AS ICNumber,
           CONVERT(varchar(20), DecryptByKeyAutoCert(CERT_ID(N'SmartBank_Column_Certificate'), NULL, PhoneCipher)) AS Phone,
           CONVERT(nvarchar(200), DecryptByKeyAutoCert(CERT_ID(N'SmartBank_Column_Certificate'), NULL, AddressCipher)) AS Address,
           Status,
           CreatedAt
    FROM core.Customer
    WHERE CustomerID = @CustomerID;
END;
GO

-- Let staff update their own contact details.
CREATE OR ALTER PROCEDURE api.usp_UpdateOwnStaffProfile
    @StaffName nvarchar(100),
    @Phone varchar(20)
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @StaffID char(6);
    DECLARE @CorrelationID uniqueidentifier = NEWID();

    BEGIN TRY
        SELECT @StaffID = StaffID
        FROM sec.PrincipalMap
        WHERE LoginName = ORIGINAL_LOGIN()
          AND UserType IN ('DBA', 'MANAGER', 'OFFICER')
          AND IsActive = 1;

        IF @StaffID IS NULL THROW 50204, 'Only active staff may update their own profile.', 1;
        IF NULLIF(LTRIM(RTRIM(@StaffName)), N'') IS NULL THROW 50205, 'Staff name is required.', 1;
        IF LEN(@Phone) NOT BETWEEN 9 AND 20 THROW 50206, 'Phone length must be between 9 and 20 characters.', 1;

        EXEC sys.sp_set_session_context @key = N'CorrelationID', @value = @CorrelationID;
        BEGIN TRANSACTION;
        UPDATE core.Staff SET StaffName = @StaffName, Phone = @Phone WHERE StaffID = @StaffID;
        COMMIT TRANSACTION;
        EXEC sys.sp_set_session_context @key = N'CorrelationID', @value = NULL;

        EXEC audit.usp_LogApplicationEvent 'PROFILE_CHANGE', N'api.usp_UpdateOwnStaffProfile', 1,
             'STAFF', @StaffID, @CorrelationID, NULL, N'Staff updated own name/phone; salary and position were not exposed.';
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        EXEC sys.sp_set_session_context @key = N'CorrelationID', @value = NULL;
        DECLARE @ErrorNumber int = ERROR_NUMBER(), @ErrorMessage nvarchar(1000) = LEFT(ERROR_MESSAGE(), 1000);
        EXEC audit.usp_LogApplicationEvent 'PROFILE_CHANGE', N'api.usp_UpdateOwnStaffProfile', 0,
             'STAFF', @StaffID, @CorrelationID, @ErrorNumber, @ErrorMessage;
        THROW;
    END CATCH;
END;
GO

-- Let managers add, update, and deactivate officers.
CREATE OR ALTER PROCEDURE api.usp_ManagerAddOfficer
    @StaffID char(6),
    @StaffName nvarchar(100),
    @Phone varchar(20),
    @BranchID char(5),
    @Salary decimal(19, 2)
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @CorrelationID uniqueidentifier = NEWID();
    DECLARE @Cipher varbinary(512);

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM sec.PrincipalMap WHERE LoginName = ORIGINAL_LOGIN() AND UserType = 'MANAGER' AND IsActive = 1)
            THROW 50207, 'Only an active bank manager may add an officer record.', 1;
        IF @Salary <= 0 THROW 50208, 'Salary must be positive.', 1;
        IF NOT EXISTS (SELECT 1 FROM core.Branch WHERE BranchID = @BranchID AND IsActive = 1)
            THROW 50209, 'Branch does not exist or is inactive.', 1;

        OPEN SYMMETRIC KEY SmartBank_Column_Key DECRYPTION BY CERTIFICATE SmartBank_Column_Certificate;
        SET @Cipher = EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), CONVERT(varchar(50), @Salary));
        CLOSE SYMMETRIC KEY SmartBank_Column_Key;
        IF @Cipher IS NULL THROW 50210, 'Salary encryption failed.', 1;

        EXEC sys.sp_set_session_context @key = N'CorrelationID', @value = @CorrelationID;
        BEGIN TRANSACTION;
        INSERT core.Staff (StaffID, StaffName, Phone) VALUES (@StaffID, @StaffName, @Phone);
        INSERT core.StaffEmployment (StaffID, Position, BranchID, SalaryCipher)
        VALUES (@StaffID, 'BANK_OFFICER', @BranchID, @Cipher);
        COMMIT TRANSACTION;
        EXEC sys.sp_set_session_context @key = N'CorrelationID', @value = NULL;

        EXEC audit.usp_LogApplicationEvent 'STAFF_MANAGEMENT', N'api.usp_ManagerAddOfficer', 1,
             'STAFF', @StaffID, @CorrelationID, NULL, N'Bank officer employment record created.';
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        EXEC sys.sp_set_session_context @key = N'CorrelationID', @value = NULL;
        DECLARE @ErrorNumber int = ERROR_NUMBER(), @ErrorMessage nvarchar(1000) = LEFT(ERROR_MESSAGE(), 1000);
        EXEC audit.usp_LogApplicationEvent 'STAFF_MANAGEMENT', N'api.usp_ManagerAddOfficer', 0,
             'STAFF', @StaffID, @CorrelationID, @ErrorNumber, @ErrorMessage;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE api.usp_ManagerUpdateOfficer
    @StaffID char(6),
    @StaffName nvarchar(100),
    @Phone varchar(20),
    @BranchID char(5),
    @Salary decimal(19, 2) = NULL
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @CorrelationID uniqueidentifier = NEWID();
    DECLARE @Cipher varbinary(512);

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM sec.PrincipalMap WHERE LoginName = ORIGINAL_LOGIN() AND UserType = 'MANAGER' AND IsActive = 1)
            THROW 50211, 'Only an active bank manager may update officer records.', 1;
        IF NOT EXISTS (SELECT 1 FROM core.StaffEmployment WHERE StaffID = @StaffID AND Position = 'BANK_OFFICER')
            THROW 50212, 'The target is not a bank officer.', 1;
        IF NOT EXISTS (SELECT 1 FROM core.Branch WHERE BranchID = @BranchID AND IsActive = 1)
            THROW 50213, 'Branch does not exist or is inactive.', 1;
        IF @Salary IS NOT NULL AND @Salary <= 0 THROW 50214, 'Salary must be positive.', 1;

        IF @Salary IS NOT NULL
        BEGIN
            OPEN SYMMETRIC KEY SmartBank_Column_Key DECRYPTION BY CERTIFICATE SmartBank_Column_Certificate;
            SET @Cipher = EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), CONVERT(varchar(50), @Salary));
            CLOSE SYMMETRIC KEY SmartBank_Column_Key;
        END;

        EXEC sys.sp_set_session_context @key = N'CorrelationID', @value = @CorrelationID;
        BEGIN TRANSACTION;
        UPDATE core.Staff SET StaffName = @StaffName, Phone = @Phone WHERE StaffID = @StaffID;
        UPDATE core.StaffEmployment
        SET BranchID = @BranchID,
            SalaryCipher = COALESCE(@Cipher, SalaryCipher),
            SalaryLastChangedAt = CASE WHEN @Salary IS NULL THEN SalaryLastChangedAt ELSE SYSUTCDATETIME() END
        WHERE StaffID = @StaffID AND Position = 'BANK_OFFICER';
        COMMIT TRANSACTION;
        EXEC sys.sp_set_session_context @key = N'CorrelationID', @value = NULL;

        EXEC audit.usp_LogApplicationEvent 'STAFF_MANAGEMENT', N'api.usp_ManagerUpdateOfficer', 1,
             'STAFF', @StaffID, @CorrelationID, NULL, N'Bank officer record updated through controlled procedure.';
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        EXEC sys.sp_set_session_context @key = N'CorrelationID', @value = NULL;
        DECLARE @ErrorNumber int = ERROR_NUMBER(), @ErrorMessage nvarchar(1000) = LEFT(ERROR_MESSAGE(), 1000);
        EXEC audit.usp_LogApplicationEvent 'STAFF_MANAGEMENT', N'api.usp_ManagerUpdateOfficer', 0,
             'STAFF', @StaffID, @CorrelationID, @ErrorNumber, @ErrorMessage;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE api.usp_ManagerDeactivateOfficer
    @StaffID char(6)
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @CorrelationID uniqueidentifier = NEWID();

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM sec.PrincipalMap WHERE LoginName = ORIGINAL_LOGIN() AND UserType = 'MANAGER' AND IsActive = 1)
            THROW 50215, 'Only an active bank manager may deactivate an officer.', 1;
        IF NOT EXISTS (SELECT 1 FROM core.StaffEmployment WHERE StaffID = @StaffID AND Position = 'BANK_OFFICER')
            THROW 50216, 'The target is not a bank officer.', 1;

        EXEC sys.sp_set_session_context @key = N'CorrelationID', @value = @CorrelationID;
        BEGIN TRANSACTION;
        UPDATE core.Staff SET IsActive = 0 WHERE StaffID = @StaffID;
        UPDATE sec.PrincipalMap
        SET IsActive = 0, EffectiveTo = SYSUTCDATETIME()
        WHERE StaffID = @StaffID AND UserType = 'OFFICER' AND IsActive = 1;
        COMMIT TRANSACTION;
        EXEC sys.sp_set_session_context @key = N'CorrelationID', @value = NULL;

        EXEC audit.usp_LogApplicationEvent 'STAFF_MANAGEMENT', N'api.usp_ManagerDeactivateOfficer', 1,
             'STAFF', @StaffID, @CorrelationID, NULL, N'Officer record and mapped database access were deactivated.';
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        EXEC sys.sp_set_session_context @key = N'CorrelationID', @value = NULL;
        DECLARE @ErrorNumber int = ERROR_NUMBER(), @ErrorMessage nvarchar(1000) = LEFT(ERROR_MESSAGE(), 1000);
        EXEC audit.usp_LogApplicationEvent 'STAFF_MANAGEMENT', N'api.usp_ManagerDeactivateOfficer', 0,
             'STAFF', @StaffID, @CorrelationID, @ErrorNumber, @ErrorMessage;
        THROW;
    END CATCH;
END;
GO

-- Let officers create customers and manage accounts.
CREATE OR ALTER PROCEDURE api.usp_OfficerCreateCustomer
    @CustomerID char(6),
    @CustomerName nvarchar(100),
    @Email varchar(254),
    @ICNumber varchar(20),
    @Phone varchar(20),
    @Address nvarchar(200)
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @CorrelationID uniqueidentifier = NEWID();
    DECLARE @ICC varbinary(512), @PhoneC varbinary(512), @AddressC varbinary(1024);

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM sec.PrincipalMap WHERE LoginName = ORIGINAL_LOGIN() AND UserType = 'OFFICER' AND IsActive = 1)
            THROW 50217, 'Only an active bank officer may create a customer.', 1;
        IF NULLIF(LTRIM(RTRIM(@CustomerName)), N'') IS NULL OR NULLIF(LTRIM(RTRIM(@ICNumber)), '') IS NULL
            THROW 50218, 'Customer name and national ID are required.', 1;

        OPEN SYMMETRIC KEY SmartBank_Column_Key DECRYPTION BY CERTIFICATE SmartBank_Column_Certificate;
        SET @ICC = EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), @ICNumber);
        SET @PhoneC = EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), @Phone);
        SET @AddressC = EncryptByKey(Key_GUID(N'SmartBank_Column_Key'), @Address);
        CLOSE SYMMETRIC KEY SmartBank_Column_Key;
        IF @ICC IS NULL OR @PhoneC IS NULL OR @AddressC IS NULL THROW 50219, 'Customer encryption failed.', 1;

        EXEC sys.sp_set_session_context @key = N'CorrelationID', @value = @CorrelationID;
        BEGIN TRANSACTION;
        INSERT core.Customer
        (CustomerID, CustomerName, Email, ICNumberCipher, PhoneCipher, AddressCipher)
        VALUES (@CustomerID, @CustomerName, @Email, @ICC, @PhoneC, @AddressC);
        COMMIT TRANSACTION;
        EXEC sys.sp_set_session_context @key = N'CorrelationID', @value = NULL;

        EXEC audit.usp_LogApplicationEvent 'CUSTOMER_MANAGEMENT', N'api.usp_OfficerCreateCustomer', 1,
             'CUSTOMER', @CustomerID, @CorrelationID, NULL, N'Encrypted customer record created.';
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        EXEC sys.sp_set_session_context @key = N'CorrelationID', @value = NULL;
        DECLARE @ErrorNumber int = ERROR_NUMBER(), @ErrorMessage nvarchar(1000) = LEFT(ERROR_MESSAGE(), 1000);
        EXEC audit.usp_LogApplicationEvent 'CUSTOMER_MANAGEMENT', N'api.usp_OfficerCreateCustomer', 0,
             'CUSTOMER', @CustomerID, @CorrelationID, @ErrorNumber, @ErrorMessage;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE api.usp_OfficerOpenAccount
    @AccountID varchar(10),
    @CustomerID char(6),
    @AccountType varchar(20)
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @CorrelationID uniqueidentifier = NEWID();

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM sec.PrincipalMap WHERE LoginName = ORIGINAL_LOGIN() AND UserType = 'OFFICER' AND IsActive = 1)
            THROW 50220, 'Only an active bank officer may open an account.', 1;
        IF NOT EXISTS (SELECT 1 FROM core.Customer WHERE CustomerID = @CustomerID AND Status = 'ACTIVE')
            THROW 50221, 'Customer does not exist or is inactive.', 1;
        IF @AccountType NOT IN ('SAVINGS', 'CURRENT', 'FIXED_DEPOSIT')
            THROW 50222, 'Invalid account type.', 1;

        EXEC sys.sp_set_session_context @key = N'CorrelationID', @value = @CorrelationID;
        BEGIN TRANSACTION;
        INSERT core.Account (AccountID, CustomerID, AccountType) VALUES (@AccountID, @CustomerID, @AccountType);
        COMMIT TRANSACTION;
        EXEC sys.sp_set_session_context @key = N'CorrelationID', @value = NULL;

        EXEC audit.usp_LogApplicationEvent 'ACCOUNT_MANAGEMENT', N'api.usp_OfficerOpenAccount', 1,
             'ACCOUNT', @AccountID, @CorrelationID, NULL, N'Zero-balance customer account opened.';
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        EXEC sys.sp_set_session_context @key = N'CorrelationID', @value = NULL;
        DECLARE @ErrorNumber int = ERROR_NUMBER(), @ErrorMessage nvarchar(1000) = LEFT(ERROR_MESSAGE(), 1000);
        EXEC audit.usp_LogApplicationEvent 'ACCOUNT_MANAGEMENT', N'api.usp_OfficerOpenAccount', 0,
             'ACCOUNT', @AccountID, @CorrelationID, @ErrorNumber, @ErrorMessage;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE api.usp_OfficerSetAccountStatus
    @AccountID varchar(10),
    @Status varchar(12)
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @CorrelationID uniqueidentifier = NEWID();
    DECLARE @Balance decimal(19, 2);

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM sec.PrincipalMap WHERE LoginName = ORIGINAL_LOGIN() AND UserType = 'OFFICER' AND IsActive = 1)
            THROW 50223, 'Only an active bank officer may change account status.', 1;
        IF @Status NOT IN ('ACTIVE', 'FROZEN', 'CLOSED') THROW 50224, 'Invalid account status.', 1;
        SELECT @Balance = Balance FROM core.Account WHERE AccountID = @AccountID;
        IF @Balance IS NULL THROW 50225, 'Account not found.', 1;
        IF @Status = 'CLOSED' AND @Balance <> 0 THROW 50226, 'An account must have zero balance before closure.', 1;

        EXEC sys.sp_set_session_context @key = N'CorrelationID', @value = @CorrelationID;
        BEGIN TRANSACTION;
        UPDATE core.Account SET Status = @Status WHERE AccountID = @AccountID;
        COMMIT TRANSACTION;
        EXEC sys.sp_set_session_context @key = N'CorrelationID', @value = NULL;

        EXEC audit.usp_LogApplicationEvent 'ACCOUNT_MANAGEMENT', N'api.usp_OfficerSetAccountStatus', 1,
             'ACCOUNT', @AccountID, @CorrelationID, NULL, N'Account status changed through controlled procedure.';
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        EXEC sys.sp_set_session_context @key = N'CorrelationID', @value = NULL;
        DECLARE @ErrorNumber int = ERROR_NUMBER(), @ErrorMessage nvarchar(1000) = LEFT(ERROR_MESSAGE(), 1000);
        EXEC audit.usp_LogApplicationEvent 'ACCOUNT_MANAGEMENT', N'api.usp_OfficerSetAccountStatus', 0,
             'ACCOUNT', @AccountID, @CorrelationID, @ErrorNumber, @ErrorMessage;
        THROW;
    END CATCH;
END;
GO

-- Let customers set their transaction PIN.
CREATE OR ALTER PROCEDURE api.usp_SetTransactionPin
    @CurrentPin varchar(12) = NULL,
    @NewPin varchar(12)
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @LoginName sysname = ORIGINAL_LOGIN();
    DECLARE @CorrelationID uniqueidentifier = NEWID();
    DECLARE @Salt varbinary(32), @StoredHash varbinary(64), @NewSalt varbinary(32), @NewHash varbinary(64);

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM sec.PrincipalMap WHERE LoginName = @LoginName AND UserType = 'CUSTOMER' AND IsActive = 1)
            THROW 50227, 'Only an active customer may set a transaction PIN.', 1;
        IF LEN(@NewPin) <> 6 OR @NewPin LIKE '%[^0-9]%' THROW 50228, 'Transaction PIN must contain exactly six digits.', 1;

        SELECT @Salt = Salt, @StoredHash = PinHash FROM sec.TransactionCredential WHERE LoginName = @LoginName;
        IF @StoredHash IS NOT NULL
           AND (@CurrentPin IS NULL OR HASHBYTES('SHA2_512', @Salt + CONVERT(varbinary(32), @CurrentPin)) <> @StoredHash)
            THROW 50229, 'Current transaction PIN is invalid.', 1;

        SET @NewSalt = CRYPT_GEN_RANDOM(32);
        SET @NewHash = HASHBYTES('SHA2_512', @NewSalt + CONVERT(varbinary(32), @NewPin));

        EXEC sys.sp_set_session_context @key = N'CorrelationID', @value = @CorrelationID;
        BEGIN TRANSACTION;
        MERGE sec.TransactionCredential AS target
        USING (SELECT @LoginName AS LoginName) AS source
        ON target.LoginName = source.LoginName
        WHEN MATCHED THEN UPDATE SET Salt = @NewSalt, PinHash = @NewHash, FailedAttempts = 0,
                                     LockedUntil = NULL, LastChangedAt = SYSUTCDATETIME()
        WHEN NOT MATCHED THEN INSERT (LoginName, Salt, PinHash) VALUES (@LoginName, @NewSalt, @NewHash);
        COMMIT TRANSACTION;
        EXEC sys.sp_set_session_context @key = N'CorrelationID', @value = NULL;

        EXEC audit.usp_LogApplicationEvent 'CREDENTIAL_CHANGE', N'api.usp_SetTransactionPin', 1,
             'LOGIN', @LoginName, @CorrelationID, NULL, N'Salted SHA2-512 transaction PIN hash replaced.';
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        EXEC sys.sp_set_session_context @key = N'CorrelationID', @value = NULL;
        DECLARE @ErrorNumber int = ERROR_NUMBER(), @ErrorMessage nvarchar(1000) = LEFT(ERROR_MESSAGE(), 1000);
        EXEC audit.usp_LogApplicationEvent 'CREDENTIAL_CHANGE', N'api.usp_SetTransactionPin', 0,
             'LOGIN', @LoginName, @CorrelationID, @ErrorNumber, @ErrorMessage;
        THROW;
    END CATCH;
END;
GO

-- Process customer deposits, withdrawals, and transfers.
CREATE OR ALTER PROCEDURE api.usp_PerformTransaction
    @TransactionType varchar(10),
    @SourceAccountID varchar(10),
    @DestinationAccountID varchar(10) = NULL,
    @Amount decimal(19, 2),
    @TransactionPin varchar(12),
    @Channel varchar(12) = 'ONLINE'
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @LoginName sysname = ORIGINAL_LOGIN();
    DECLARE @CustomerID char(6);
    DECLARE @DestinationCustomerID char(6);
    DECLARE @CorrelationID uniqueidentifier = NEWID();
    DECLARE @Salt varbinary(32), @StoredHash varbinary(64), @LockedUntil datetime2(3);
    DECLARE @CredentialFound bit = 0, @PinValid bit = 0;
    DECLARE @SourceBalance decimal(19, 2), @DestinationBalance decimal(19, 2);
    DECLARE @NewSourceBalance decimal(19, 2), @NewDestinationBalance decimal(19, 2);
    DECLARE @Now datetime2(3) = SYSUTCDATETIME();
    DECLARE @LockResult int, @FirstLock varchar(10), @SecondLock varchar(10);
    DECLARE @FirstLockResource nvarchar(255), @SecondLockResource nvarchar(255);

    BEGIN TRY
        SELECT @CustomerID = CustomerID
        FROM sec.PrincipalMap
        WHERE LoginName = @LoginName AND UserType = 'CUSTOMER' AND IsActive = 1
          AND (EffectiveTo IS NULL OR EffectiveTo > SYSUTCDATETIME());

        IF @CustomerID IS NULL THROW 50230, 'Only an active customer may perform transactions.', 1;
        IF @TransactionType NOT IN ('DEPOSIT', 'WITHDRAWAL', 'TRANSFER') THROW 50231, 'Invalid transaction type.', 1;
        IF @Amount <= 0 OR @Amount > 1000000 THROW 50232, 'Amount must be greater than zero and no more than 1,000,000.', 1;
        IF @Channel NOT IN ('ONLINE', 'ATM', 'MOBILE') THROW 50233, 'Invalid customer transaction channel.', 1;
        IF @TransactionType = 'TRANSFER' AND (@DestinationAccountID IS NULL OR @DestinationAccountID = @SourceAccountID)
            THROW 50234, 'A transfer requires a different destination account.', 1;
        IF @TransactionType <> 'TRANSFER' AND @DestinationAccountID IS NOT NULL
            THROW 50235, 'Destination account is only valid for transfers.', 1;

        BEGIN TRANSACTION;
        SELECT @Salt = Salt, @StoredHash = PinHash, @LockedUntil = LockedUntil, @CredentialFound = 1
        FROM sec.TransactionCredential WITH (UPDLOCK, HOLDLOCK)
        WHERE LoginName = @LoginName;

        IF @CredentialFound = 1 AND (@LockedUntil IS NULL OR @LockedUntil <= @Now)
           AND HASHBYTES('SHA2_512', @Salt + CONVERT(varbinary(32), @TransactionPin)) = @StoredHash
        BEGIN
            SET @PinValid = 1;
            UPDATE sec.TransactionCredential SET FailedAttempts = 0, LockedUntil = NULL WHERE LoginName = @LoginName;
        END
        ELSE IF @CredentialFound = 1 AND (@LockedUntil IS NULL OR @LockedUntil <= @Now)
        BEGIN
            UPDATE sec.TransactionCredential
            SET FailedAttempts = CASE WHEN FailedAttempts >= 4 THEN 5 ELSE FailedAttempts + 1 END,
                LockedUntil = CASE WHEN FailedAttempts >= 4 THEN DATEADD(MINUTE, 15, @Now) ELSE NULL END
            WHERE LoginName = @LoginName;
        END;
        COMMIT TRANSACTION;

        IF @CredentialFound = 0 THROW 50236, 'Transaction PIN has not been enrolled.', 1;
        IF @PinValid = 0 AND @LockedUntil > @Now THROW 50237, 'Transaction PIN is temporarily locked.', 1;
        IF @PinValid = 0 THROW 50238, 'Invalid transaction PIN.', 1;

        EXEC sys.sp_set_session_context @key = N'CorrelationID', @value = @CorrelationID;
        BEGIN TRANSACTION;

        SET @FirstLock = @SourceAccountID;
        SET @SecondLock = @DestinationAccountID;
        IF @SecondLock IS NOT NULL AND @SecondLock < @FirstLock
            SELECT @FirstLock = @DestinationAccountID, @SecondLock = @SourceAccountID;

        SET @FirstLockResource = N'SmartBankAccount:' + @FirstLock;
        SET @SecondLockResource = CASE WHEN @SecondLock IS NULL THEN NULL ELSE N'SmartBankAccount:' + @SecondLock END;

        EXEC @LockResult = sys.sp_getapplock
            @Resource = @FirstLockResource,
            @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 5000;
        IF @LockResult < 0 THROW 50239, 'Could not acquire the source account lock.', 1;

        IF @SecondLock IS NOT NULL
        BEGIN
            EXEC @LockResult = sys.sp_getapplock
                @Resource = @SecondLockResource,
                @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 5000;
            IF @LockResult < 0 THROW 50240, 'Could not acquire the destination account lock.', 1;
        END;

        SELECT @SourceBalance = Balance
        FROM core.Account WITH (UPDLOCK, HOLDLOCK)
        WHERE AccountID = @SourceAccountID AND CustomerID = @CustomerID AND Status = 'ACTIVE';
        IF @SourceBalance IS NULL THROW 50241, 'Source account is not active or does not belong to the customer.', 1;

        SET @Now = SYSUTCDATETIME();
        IF @TransactionType = 'DEPOSIT'
        BEGIN
            SET @NewSourceBalance = @SourceBalance + @Amount;
            UPDATE core.Account SET Balance = @NewSourceBalance WHERE AccountID = @SourceAccountID;
            EXEC core.usp_AppendLedgerEntry @CorrelationID, @CustomerID, @SourceAccountID, NULL, @Now,
                 @Amount, 'CREDIT', 'DEPOSIT', @NewSourceBalance, @LoginName, @Channel;
        END
        ELSE IF @TransactionType = 'WITHDRAWAL'
        BEGIN
            IF @SourceBalance < @Amount THROW 50242, 'Insufficient funds.', 1;
            SET @NewSourceBalance = @SourceBalance - @Amount;
            UPDATE core.Account SET Balance = @NewSourceBalance WHERE AccountID = @SourceAccountID;
            EXEC core.usp_AppendLedgerEntry @CorrelationID, @CustomerID, @SourceAccountID, NULL, @Now,
                 @Amount, 'DEBIT', 'WITHDRAWAL', @NewSourceBalance, @LoginName, @Channel;
        END
        ELSE
        BEGIN
            SELECT @DestinationBalance = Balance, @DestinationCustomerID = CustomerID
            FROM core.Account WITH (UPDLOCK, HOLDLOCK)
            WHERE AccountID = @DestinationAccountID AND Status = 'ACTIVE';
            IF @DestinationBalance IS NULL THROW 50243, 'Destination account is not active or does not exist.', 1;
            IF @SourceBalance < @Amount THROW 50244, 'Insufficient funds.', 1;

            SET @NewSourceBalance = @SourceBalance - @Amount;
            SET @NewDestinationBalance = @DestinationBalance + @Amount;
            UPDATE core.Account SET Balance = @NewSourceBalance WHERE AccountID = @SourceAccountID;
            UPDATE core.Account SET Balance = @NewDestinationBalance WHERE AccountID = @DestinationAccountID;

            EXEC core.usp_AppendLedgerEntry @CorrelationID, @CustomerID, @SourceAccountID, @DestinationAccountID, @Now,
                 @Amount, 'DEBIT', 'TRANSFER', @NewSourceBalance, @LoginName, @Channel;
            EXEC core.usp_AppendLedgerEntry @CorrelationID, @DestinationCustomerID, @DestinationAccountID, @SourceAccountID, @Now,
                 @Amount, 'CREDIT', 'TRANSFER', @NewDestinationBalance, @LoginName, @Channel;
        END;

        COMMIT TRANSACTION;
        EXEC sys.sp_set_session_context @key = N'CorrelationID', @value = NULL;

        EXEC audit.usp_LogApplicationEvent 'CUSTOMER_TRANSACTION', N'api.usp_PerformTransaction', 1,
             'ACCOUNT', @SourceAccountID, @CorrelationID, NULL, N'Validated customer transaction committed atomically.';

        SELECT @CorrelationID AS CorrelationID, @TransactionType AS TransactionType,
               @SourceAccountID AS SourceAccountID, @DestinationAccountID AS DestinationAccountID,
               @Amount AS Amount, @NewSourceBalance AS SourceBalanceAfter,
               @NewDestinationBalance AS DestinationBalanceAfter;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        EXEC sys.sp_set_session_context @key = N'CorrelationID', @value = NULL;
        DECLARE @ErrorNumber int = ERROR_NUMBER(), @ErrorMessage nvarchar(1000) = LEFT(ERROR_MESSAGE(), 1000);
        EXEC audit.usp_LogApplicationEvent 'CUSTOMER_TRANSACTION', N'api.usp_PerformTransaction', 0,
             'ACCOUNT', @SourceAccountID, @CorrelationID, @ErrorNumber, @ErrorMessage;
        THROW;
    END CATCH;
END;
GO

-- Verify the transaction hash chain and account balances.
CREATE OR ALTER PROCEDURE api.usp_VerifyLedgerChain
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @TransID bigint, @CorrelationID uniqueidentifier, @CustomerID char(6), @AccountID varchar(10),
            @CounterpartyAccountID varchar(10), @TransDate datetime2(3), @Amount decimal(19, 2),
            @Direction varchar(6), @TransactionType varchar(10), @BalanceAfter decimal(19, 2),
            @ActorLogin sysname, @Channel varchar(12), @StoredPreviousHash varbinary(64), @StoredRecordHash varbinary(64),
            @ExpectedPreviousHash varbinary(64) = NULL, @ExpectedRecordHash varbinary(64), @Payload nvarchar(4000),
            @InvalidRows int = 0, @RowsChecked int = 0;

    DECLARE ledger_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT TransID, CorrelationID, CustomerID, AccountID, CounterpartyAccountID, TransDate,
               Amount, Direction, TransactionType, BalanceAfter, ActorLogin, Channel, PreviousHash, RecordHash
        FROM core.TransactionRecord ORDER BY TransID;

    OPEN ledger_cursor;
    FETCH NEXT FROM ledger_cursor INTO @TransID, @CorrelationID, @CustomerID, @AccountID, @CounterpartyAccountID,
         @TransDate, @Amount, @Direction, @TransactionType, @BalanceAfter, @ActorLogin, @Channel,
         @StoredPreviousHash, @StoredRecordHash;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @Payload = CONCAT
        (
            CONVERT(char(36), @CorrelationID), N'|', @CustomerID, N'|', @AccountID, N'|',
            COALESCE(@CounterpartyAccountID, N''), N'|', CONVERT(varchar(33), @TransDate, 126), N'|',
            CONVERT(varchar(40), @Amount), N'|', @Direction, N'|', @TransactionType, N'|',
            CONVERT(varchar(40), @BalanceAfter), N'|', @ActorLogin, N'|', @Channel, N'|',
            COALESCE(CONVERT(varchar(128), @ExpectedPreviousHash, 2), N'GENESIS')
        );
        SET @ExpectedRecordHash = HASHBYTES('SHA2_512', CONVERT(varbinary(max), @Payload));
        SET @RowsChecked += 1;
        IF (ISNULL(@StoredPreviousHash, 0x) <> ISNULL(@ExpectedPreviousHash, 0x)) OR @StoredRecordHash <> @ExpectedRecordHash
            SET @InvalidRows += 1;
        SET @ExpectedPreviousHash = @StoredRecordHash;

        FETCH NEXT FROM ledger_cursor INTO @TransID, @CorrelationID, @CustomerID, @AccountID, @CounterpartyAccountID,
             @TransDate, @Amount, @Direction, @TransactionType, @BalanceAfter, @ActorLogin, @Channel,
             @StoredPreviousHash, @StoredRecordHash;
    END;
    CLOSE ledger_cursor;
    DEALLOCATE ledger_cursor;

    SELECT @RowsChecked AS RowsChecked, @InvalidRows AS InvalidRows,
           CONVERT(bit, CASE WHEN @InvalidRows = 0 THEN 1 ELSE 0 END) AS ChainIsValid,
           @ExpectedPreviousHash AS LastComputedHash,
           (SELECT LastHash FROM ops.LedgerChain WHERE ChainID = 1) AS StoredChainHead;
END;
GO

CREATE OR ALTER PROCEDURE api.usp_VerifyAccountBalances
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    WITH LedgerBalance AS
    (
        SELECT AccountID,
               SUM(CASE WHEN Direction = 'CREDIT' THEN Amount ELSE -Amount END) AS CalculatedBalance
        FROM core.TransactionRecord
        GROUP BY AccountID
    )
    SELECT account.AccountID, account.Balance AS StoredBalance,
           COALESCE(ledger.CalculatedBalance, 0) AS CalculatedBalance,
           account.Balance - COALESCE(ledger.CalculatedBalance, 0) AS Difference,
           CONVERT(bit, CASE WHEN account.Balance = COALESCE(ledger.CalculatedBalance, 0) THEN 1 ELSE 0 END) AS IsReconciled
    FROM core.Account AS account
    LEFT JOIN LedgerBalance AS ledger ON ledger.AccountID = account.AccountID
    ORDER BY account.AccountID;
END;
GO
