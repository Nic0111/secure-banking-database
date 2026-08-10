-- Connect as: sb_customer_hafiz
USE [SmartBankDB];
GO

SELECT * FROM api.vw_StaffDirectory;
EXEC api.usp_GetMyCustomerProfile;                    -- Must return only C00002 with decrypted PII.
SELECT * FROM api.vw_MyAccounts;                      -- Must return only A000000003 and A000000004.
SELECT * FROM api.vw_MyTransactions ORDER BY TransDate DESC;

-- EXPECTED VALIDATION FAILURE: source account belongs to Amelia, not Hafiz.
EXEC api.usp_PerformTransaction
    @TransactionType = 'WITHDRAWAL', @SourceAccountID = 'A000000001',
    @DestinationAccountID = NULL, @Amount = 10.00, @TransactionPin = '482731', @Channel = 'ONLINE';
GO

