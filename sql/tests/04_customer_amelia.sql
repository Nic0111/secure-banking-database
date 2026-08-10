-- Connect as: sb_customer_amelia
USE [SmartBankDB];
GO

SELECT * FROM api.vw_StaffDirectory;                  -- SUCCESS: staff names and phones.
EXEC api.usp_GetMyCustomerProfile;                   -- SUCCESS: own encrypted PII is automatically decrypted.
SELECT * FROM api.vw_MyAccounts;                     -- SUCCESS: only C00001 accounts.
SELECT * FROM api.vw_MyTransactions ORDER BY TransDate DESC; -- SUCCESS: only ledger entries on C00001 accounts.

-- SUCCESS: valid customer-only deposit and transfer.
EXEC api.usp_PerformTransaction
    @TransactionType = 'DEPOSIT', @SourceAccountID = 'A000000001',
    @DestinationAccountID = NULL, @Amount = 25.00, @TransactionPin = '482731', @Channel = 'MOBILE';
EXEC api.usp_PerformTransaction
    @TransactionType = 'WITHDRAWAL', @SourceAccountID = 'A000000001',
    @DestinationAccountID = NULL, @Amount = 5.00, @TransactionPin = '482731', @Channel = 'ATM';
EXEC api.usp_PerformTransaction
    @TransactionType = 'TRANSFER', @SourceAccountID = 'A000000001',
    @DestinationAccountID = 'A000000003', @Amount = 10.00, @TransactionPin = '482731', @Channel = 'ONLINE';
GO

-- EXPECTED VALIDATION FAILURE: insufficient funds; application audit records Succeeded=0.
EXEC api.usp_PerformTransaction
    @TransactionType = 'WITHDRAWAL', @SourceAccountID = 'A000000001',
    @DestinationAccountID = NULL, @Amount = 999999.00, @TransactionPin = '482731', @Channel = 'ONLINE';
GO

-- EXPECTED DENIAL: customer cannot read a base table or another customer's data.
SELECT * FROM core.Account;
GO

-- EXPECTED DENIAL: customer cannot manage staff.
EXEC api.usp_ManagerGetStaffProfiles;
GO
