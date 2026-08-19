-- Run as: sb_officer_farid.
USE [SmartBankDB];
GO

-- Officers can update their own contact details through the approved procedure.
EXEC api.usp_UpdateOwnStaffProfile @StaffName = N'Farid Iskandar', @Phone = '012-3101003';
EXEC api.usp_GetMyStaffProfile;

-- Expected result: permission denied. Salary remains protected.
UPDATE core.StaffEmployment SET SalaryCipher = 0x00 WHERE StaffID = 'S00003';
GO
