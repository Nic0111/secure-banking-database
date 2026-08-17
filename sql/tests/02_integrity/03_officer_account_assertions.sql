-- Run in fresh connections as: sb_officer_farid and sb_officer_priya.
USE [SmartBankDB];
GO

-- Officers can open and update accounts through stored procedures.
IF NOT EXISTS (SELECT 1 FROM api.vw_CustomerAccountSummary WHERE AccountID = 'ATEST00001')
    EXEC api.usp_OfficerOpenAccount @AccountID = 'ATEST00001', @CustomerID = 'C00012', @AccountType = 'CURRENT';
EXEC api.usp_OfficerSetAccountStatus @AccountID = 'ATEST00001', @Status = 'FROZEN';
EXEC api.usp_OfficerSetAccountStatus @AccountID = 'ATEST00001', @Status = 'ACTIVE';
GO

-- EXPECTED DENIAL: officers cannot bypass the account or salary controls.
UPDATE core.Account SET Balance = 999999.99 WHERE AccountID = 'A000000001';
UPDATE core.StaffEmployment SET SalaryCipher = 0x00 WHERE StaffID IN ('S00003', 'S00004');
GO
