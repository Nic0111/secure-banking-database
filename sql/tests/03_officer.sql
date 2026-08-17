-- Run in two fresh connections: first as sb_officer_farid, then as sb_officer_priya.
USE [SmartBankDB];
GO

SELECT * FROM api.vw_StaffDirectory;                 -- SUCCESS.
EXEC api.usp_GetMyStaffProfile;                      -- SUCCESS: officer's own decrypted employment record.
SELECT * FROM api.vw_CustomerAccountSummary;         -- SUCCESS: every account; PII is dynamically masked.
SELECT * FROM api.vw_MyTransactions ORDER BY TransDate DESC; -- SUCCESS: every transaction.

-- SUCCESS: each officer updates only that officer's own non-salary contact columns.
DECLARE @ExpectedName nvarchar(100) =
    CASE ORIGINAL_LOGIN()
        WHEN N'sb_officer_farid' THEN N'Farid Iskandar'
        WHEN N'sb_officer_priya' THEN N'Priya Nair'
    END;
DECLARE @ExpectedPhone varchar(20) =
    CASE ORIGINAL_LOGIN()
        WHEN N'sb_officer_farid' THEN '012-3101003'
        WHEN N'sb_officer_priya' THEN '012-3101004'
    END;
IF @ExpectedName IS NULL
    THROW 51020, 'Run this test only as a configured officer login.', 1;
EXEC api.usp_UpdateOwnStaffProfile @StaffName = @ExpectedName, @Phone = @ExpectedPhone;

-- SUCCESS: account management through a validated stored procedure.
IF NOT EXISTS (SELECT 1 FROM api.vw_CustomerAccountSummary WHERE AccountID = 'ATEST00001')
    EXEC api.usp_OfficerOpenAccount @AccountID = 'ATEST00001', @CustomerID = 'C00012', @AccountType = 'CURRENT';
EXEC api.usp_OfficerSetAccountStatus @AccountID = 'ATEST00001', @Status = 'FROZEN';
EXEC api.usp_OfficerSetAccountStatus @AccountID = 'ATEST00001', @Status = 'ACTIVE';
GO

-- EXPECTED DENIAL: officer cannot directly alter balances.
UPDATE core.Account SET Balance = 999999.99 WHERE AccountID = 'A000000001';
GO

-- EXPECTED DENIAL: an officer cannot directly alter any salary, including the officer's own.
UPDATE core.StaffEmployment SET SalaryCipher = 0x00 WHERE StaffID IN ('S00003', 'S00004');
GO

-- EXPECTED DENIAL: officer is not a manager.
EXEC api.usp_ManagerGetStaffProfiles;
GO

-- EXPECTED DENIAL: only customers can execute transactions.
EXEC api.usp_PerformTransaction 'DEPOSIT', 'A000000001', NULL, 10.00, '482731', 'ONLINE';
GO
