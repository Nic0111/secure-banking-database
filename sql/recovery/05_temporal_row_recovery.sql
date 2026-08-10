USE [SmartBankDB];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DECLARE @BeforeChange datetime2(3) = SYSUTCDATETIME();
WAITFOR DELAY '00:00:01';

UPDATE core.Customer
SET CustomerName = N'ACCIDENTAL TEST VALUE', Status = 'SUSPENDED'
WHERE CustomerID = 'C00012';

SELECT N'Current accidental value' AS Evidence, CustomerID, CustomerName, Email, Status
FROM core.Customer WHERE CustomerID = 'C00012';

SELECT N'Historical value before change' AS Evidence, CustomerID, CustomerName, Email, Status, ValidFrom, ValidTo
FROM core.Customer FOR SYSTEM_TIME AS OF @BeforeChange
WHERE CustomerID = 'C00012';

UPDATE currentCustomer
SET CustomerName = historicalCustomer.CustomerName,
    Email = historicalCustomer.Email,
    Status = historicalCustomer.Status,
    ICNumberCipher = historicalCustomer.ICNumberCipher,
    PhoneCipher = historicalCustomer.PhoneCipher,
    AddressCipher = historicalCustomer.AddressCipher
FROM core.Customer AS currentCustomer
INNER JOIN core.Customer FOR SYSTEM_TIME AS OF @BeforeChange AS historicalCustomer
    ON historicalCustomer.CustomerID = currentCustomer.CustomerID
WHERE currentCustomer.CustomerID = 'C00012';

SELECT N'Restored current value' AS Evidence, CustomerID, CustomerName, Email, Status
FROM core.Customer WHERE CustomerID = 'C00012';
GO

