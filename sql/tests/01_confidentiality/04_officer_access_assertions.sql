-- Run in fresh connections as: sb_officer_farid and sb_officer_priya.
USE [SmartBankDB];
GO

-- Officers can use approved views and see only their own employment profile.
EXEC api.usp_GetMyStaffProfile;
SELECT * FROM api.vw_StaffDirectory;
SELECT * FROM api.vw_CustomerAccountSummary;
SELECT * FROM api.vw_MyTransactions ORDER BY TransDate DESC;
GO

-- EXPECTED DENIAL: an officer cannot access manager-only employment records.
EXEC api.usp_ManagerGetStaffProfiles;
-- EXPECTED DENIAL: only customers can submit transactions.
EXEC api.usp_PerformTransaction 'DEPOSIT', 'A000000001', NULL, 10.00, '482731', 'ONLINE';
GO
