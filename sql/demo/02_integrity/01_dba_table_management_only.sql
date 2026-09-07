-- Run as: sb_dba_aisha or sb_dba_kavitha.
USE [SmartBankDB];
GO

-- The DBA can create and change a table definition.
CREATE TABLE core.DemoDbaDdlProof (ProofID int NOT NULL PRIMARY KEY);
ALTER TABLE core.DemoDbaDdlProof ADD ProofNote nvarchar(100) NULL;
SELECT * FROM sys.columns WHERE object_id = OBJECT_ID(N'core.DemoDbaDdlProof');

-- Expected result: permission denied. The DBA cannot add business data.
INSERT core.DemoDbaDdlProof (ProofID, ProofNote) VALUES (1, N'Not allowed');

-- Remove the proof table after showing the DDL permission.
DROP TABLE core.DemoDbaDdlProof;
GO
