-- Run in fresh connections as: either manager or either officer login.
USE [SmartBankDB];
GO

-- Staff can update only their own non-sensitive contact details.
DECLARE @ExpectedName nvarchar(100) =
    CASE ORIGINAL_LOGIN()
        WHEN N'sb_manager_daniel' THEN N'Daniel Wong'
        WHEN N'sb_manager_siti' THEN N'Siti Aminah'
        WHEN N'sb_officer_farid' THEN N'Farid Iskandar'
        WHEN N'sb_officer_priya' THEN N'Priya Nair'
    END;
DECLARE @ExpectedPhone varchar(20) =
    CASE ORIGINAL_LOGIN()
        WHEN N'sb_manager_daniel' THEN '012-3101001'
        WHEN N'sb_manager_siti' THEN '012-3101002'
        WHEN N'sb_officer_farid' THEN '012-3101004'
        WHEN N'sb_officer_priya' THEN '012-3101005'
    END;
IF @ExpectedName IS NULL
    THROW 51210, 'Run this test only as a configured manager or officer login.', 1;

EXEC api.usp_UpdateOwnStaffProfile @StaffName = @ExpectedName, @Phone = @ExpectedPhone;
GO
