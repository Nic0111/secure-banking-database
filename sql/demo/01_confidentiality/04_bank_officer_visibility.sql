-- Run as: sb_officer_farid or sb_officer_priya.
USE [SmartBankDB];
GO

-- Officers see their own staff record.
EXEC api.usp_GetMyStaffProfile;

-- Officers can view customer accounts and transactions through views.
SELECT * FROM api.vw_CustomerAccountSummary ORDER BY AccountID;
SELECT * FROM api.vw_MyTransactions ORDER BY TransID;

-- Expected result: permission denied. Officers cannot read employment data directly.
SELECT TOP (1) * FROM core.StaffEmployment;
GO
