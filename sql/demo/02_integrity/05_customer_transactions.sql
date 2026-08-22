-- Run as: sb_customer_amelia in SSMS SQLCMD mode.
:setvar DemoTransactionPin "482731"

USE [SmartBankDB];
GO

DECLARE @DemoPin varchar(12) = '$(DemoTransactionPin)';

-- Valid transactions on Amelia's own accounts.
EXEC api.usp_PerformTransaction 'DEPOSIT', 'A000000001', NULL, 10.00, @DemoPin, 'MOBILE';
EXEC api.usp_PerformTransaction 'WITHDRAWAL', 'A000000001', NULL, 10.00, @DemoPin, 'MOBILE';
EXEC api.usp_PerformTransaction 'TRANSFER', 'A000000001', 'A000000002', 5.00, @DemoPin, 'ONLINE';
EXEC api.usp_PerformTransaction 'TRANSFER', 'A000000002', 'A000000001', 5.00, @DemoPin, 'ONLINE';
SELECT TOP (10) * FROM api.vw_MyTransactions ORDER BY TransID DESC;

-- Expected results: validation errors for an invalid amount and another customer's account.
EXEC api.usp_PerformTransaction 'WITHDRAWAL', 'A000000001', NULL, -1.00, @DemoPin, 'ONLINE';
EXEC api.usp_PerformTransaction 'DEPOSIT', 'A000000003', NULL, 1.00, @DemoPin, 'ONLINE';
GO
