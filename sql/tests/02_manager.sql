-- Connect as: sb_manager_daniel
USE [SmartBankDB];
GO

SELECT * FROM api.vw_StaffDirectory;                -- SUCCESS: public staff directory.
EXEC api.usp_GetMyStaffProfile;                     -- SUCCESS: manager's own full/decrypted record.
EXEC api.usp_ManagerGetStaffProfiles;               -- SUCCESS: own record plus all bank officers.
SELECT * FROM api.vw_CustomerAccountSummary;        -- SUCCESS: all accounts; customer name/email remain dynamically masked.
SELECT * FROM api.vw_MyTransactions ORDER BY TransDate DESC; -- SUCCESS: all transaction records.

-- SUCCESS: manager updates only the manager's own non-salary contact columns.
EXEC api.usp_UpdateOwnStaffProfile @StaffName = N'Daniel Wong', @Phone = '012-3101002';

-- SUCCESS: controlled officer update; salary is only changed inside the procedure.
EXEC api.usp_ManagerUpdateOfficer
    @StaffID = 'S00003', @StaffName = N'Farid Iskandar', @Phone = '012-3101093',
    @BranchID = 'B0001', @Salary = 5300.00;
GO

-- EXPECTED DENIAL: manager cannot directly update base data.
UPDATE core.StaffEmployment SET SalaryCipher = 0x00 WHERE StaffID = 'S00003';
GO

-- EXPECTED DENIAL: only customers can execute transactions.
EXEC api.usp_PerformTransaction 'DEPOSIT', 'A000000001', NULL, 10.00, '482731', 'ONLINE';
GO
