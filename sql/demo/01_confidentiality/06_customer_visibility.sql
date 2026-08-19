-- Run as: sb_customer_amelia or sb_customer_hafiz.
USE [SmartBankDB];
GO

-- The approved procedure automatically decrypts the connected customer's profile.
EXEC api.usp_GetMyCustomerProfile;

-- Row-level security limits these views to the connected customer.
SELECT * FROM api.vw_MyAccounts ORDER BY AccountID;
SELECT * FROM api.vw_MyTransactions ORDER BY TransID;

-- Expected result: permission denied. Customers cannot read the base account table.
SELECT TOP (1) * FROM core.Account;
GO
