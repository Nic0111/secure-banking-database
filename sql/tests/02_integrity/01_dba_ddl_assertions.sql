-- Connect as: sb_dba_aisha or sb_dba_kavitha.
USE [SmartBankDB];
GO

-- The DBA can manage definitions in the core schema.
IF OBJECT_ID(N'core.DbaValidationProof', N'U') IS NOT NULL
    DROP TABLE core.DbaValidationProof;
CREATE TABLE core.DbaValidationProof
(
    ProofID int NOT NULL CONSTRAINT PK_DbaValidationProof PRIMARY KEY
);
ALTER TABLE core.DbaValidationProof ADD ProofNote nvarchar(100) NULL;
DROP TABLE core.DbaValidationProof;
GO

-- EXPECTED DENIAL: the DBA role cannot manipulate business data.
DECLARE @BusinessInsertDenied bit = 0;
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT core.Staff (StaffID, StaffName, Phone) VALUES ('S99999', N'Not allowed', '012-0000000');
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    IF ERROR_NUMBER() <> 229
        THROW;

    SET @BusinessInsertDenied = 1;
    SELECT N'PASS - business-data INSERT denied to DBA' AS Result,
           ERROR_NUMBER() AS ActualErrorNumber,
           ERROR_MESSAGE() AS ActualErrorMessage;
END CATCH;

IF @BusinessInsertDenied = 0
    THROW 51201, 'FAIL: the DBA unexpectedly inserted a core.Staff row.', 1;
GO
