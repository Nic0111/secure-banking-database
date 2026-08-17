-- Connect as: sb_dba_aisha.
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
INSERT core.Staff (StaffID, StaffName, Phone) VALUES ('S99999', N'Not allowed', '012-0000000');
GO
