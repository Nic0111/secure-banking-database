-- open new account
EXEC api.usp_OfficerOpenAccount
    @AccountID = 'APRES00001',
    @CustomerID = 'C00012',
    @AccountType = 'SAVINGS';
GO

-- freeze account
EXEC api.usp_OfficerSetAccountStatus
    @AccountID = 'APRES00001',
    @Status = 'FROZEN';
GO

-- show
SELECT AccountID, CustomerID, AccountType, Balance, Status
FROM api.vw_CustomerAccountSummary
WHERE AccountID = 'APRES00001';
GO

-- activate account
EXEC api.usp_OfficerSetAccountStatus
    @AccountID = 'APRES00001',
    @Status = 'ACTIVE';
GO

-- negative test
UPDATE core.Account
SET Balance = 999999.99
WHERE AccountID = 'APRES00001';
GO

--
--
--

-- show
EXEC api.usp_GetMyStaffProfile;
GO

-- Staff update their own contact details through the approved procedure.
EXEC api.usp_UpdateOwnStaffProfile
    @StaffName = N'Farid Iskandar',
    @Phone = '012-3101004';
GO

-- show
EXEC api.usp_GetMyStaffProfile;
GO

-- negative test: cannot update own salary
-- The procedure exposes no salary parameter, so the attempted call fails.
EXEC api.usp_UpdateOwnStaffProfile
    @StaffName = N'Farid Iskandar',
    @Phone = '012-3101004',
    @Salary = 99999.00;
GO

-- negative test: direct salary write is denied by permission model
-- SalaryCipher is encrypted and not writable by staff.
UPDATE core.StaffEmployment
SET SalaryCipher = 0x00
WHERE StaffID = 'S00004';
GO