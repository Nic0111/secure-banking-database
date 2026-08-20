-- Run as: sb_manager_daniel or sb_manager_siti.
USE [SmartBankDB];
GO

-- Managers see their own profile through the self-service procedure.
EXEC api.usp_GetMyStaffProfile;

-- Managers see officer and DBA profiles through the staff-management procedure.
EXEC api.usp_ManagerGetStaffProfiles;

-- Managers can view all customer accounts and transactions through views.
SELECT * FROM api.vw_CustomerAccountSummary ORDER BY AccountID;
SELECT * FROM api.vw_MyTransactions ORDER BY TransID;

-- Expected result: permission denied. Managers cannot read protected tables directly.
SELECT TOP (1) * FROM core.Customer;
GO
