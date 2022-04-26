CREATE PROCEDURE GenerateNorthwindDW
AS

-- Inserting data into Dim_Customers

TRUNCATE TABLE Northwind_DW.dbo.Dim_Customers

INSERT INTO Northwind_DW.dbo.Dim_Customers (CustomerBK, CustomerName, City, Region, Country)
SELECT CustomerID, CompanyName, City, Region, Country
FROM NORTHWND.dbo.Customers

-- Replace NULL values with 'Unknown' in Region column

UPDATE Northwind_DW.dbo.Dim_Customers
SET Region = 'Unknown'
WHERE Region IS NULL

-- Inserting data into Dim_Employees

TRUNCATE TABLE Northwind_DW.dbo.Dim_Employees

INSERT INTO Northwind_DW.dbo.Dim_Employees (EmployeeBK, LastName, FirstName, FullName, Title, BirthDate, Age, HireDate, Seniority, City, Country, Photo, ReportsTo)
SELECT EmployeeID, LastName, FirstName, FirstName + ' ' + LastName [FullName], TitleOfCourtesy, BirthDate, DATEDIFF(year, BirthDate, GETDATE()) Age, HireDate, DATEDIFF(year, HireDate, GETDATE()) Seniority, City, Country, Photo,
CASE
	WHEN ReportsTo IS NULL THEN EmployeeID
	ELSE ReportsTo
END
FROM NORTHWND.dbo.Employees

-- Inserting data into Dim_Orders

TRUNCATE TABLE Northwind_DW.dbo.Dim_Orders

INSERT INTO Northwind_DW.dbo.Dim_Orders (OrderBK, ShipCity, ShipRegion, ShipCountry)
SELECT OrderID, ShipCity, ShipRegion, ShipCountry
FROM NORTHWND.dbo.Orders

-- Replace NULL values with 'Unknown' in ShipRegion column

UPDATE Northwind_DW.dbo.Dim_Orders
SET ShipRegion = 'Unknown'
WHERE ShipRegion IS NULL

-- UDF for calculating the product type in Dim_Products

DROP FUNCTION IF EXISTS fn_CalculateProductType  

GO

CREATE FUNCTION fn_CalculateProductType(@ProductPrice float)
RETURNS nvarchar(10)
AS
BEGIN
DECLARE @Result  nvarchar(10)
	IF (@ProductPrice >= (SELECT AVG(UnitPrice) FROM NORTHWND.dbo.Products))
		SET @Result = 'Expensive'
	ELSE
		SET @Result = 'Cheap'
RETURN @Result
END

GO

-- Inserting data into Dim_Products

TRUNCATE TABLE Northwind_DW.dbo.Dim_Products

INSERT INTO Northwind_DW.dbo.Dim_Products (ProductBK, ProductName, ProductUnitPrice, ProductType, CategoryName, SupplierName, Discontinued)
SELECT P.ProductID, P.ProductName, P.UnitPrice, NORTHWND.dbo.fn_CalculateProductType(P.UnitPrice) ProductType, C.CategoryName, S.CompanyName, P.Discontinued
FROM NORTHWND.dbo.Products P
JOIN NORTHWND.dbo.Categories C
ON P.CategoryID = C.CategoryID
JOIN NORTHWND.dbo.Suppliers S
ON P.SupplierID = S.SupplierID

-- Helper function to convert int to string

DROP FUNCTION IF EXISTS fn_ConvertToDateKey

GO

CREATE FUNCTION fn_ConvertToDateKey(@Date date)
RETURNS int
AS
BEGIN
	DECLARE @YearPart int
	SET @YearPart = CAST(DATEPART(year, @Date) AS int) * 10000
	DECLARE @MonthPart int
	SET @MonthPart = CAST(DATEPART(month, @Date) AS int) * 100
	DECLARE @DayPart int
	SET @DayPart = CAST(DATEPART(day, @Date) AS int)
	RETURN @YearPart + @MonthPart + @DayPart
END

GO

-- Helper function to create all date keys

DROP FUNCTION IF EXISTS fn_CreateDays

GO

CREATE FUNCTION fn_CreateDays()
RETURNS @Dates TABLE (DateKey int, [Date] date, [Year] int, [Quarter] int, [Month] int, [MonthName] nvarchar(10))
AS
BEGIN

	DECLARE @StartDate date
	SET @StartDate = '1996-01-01'
	DECLARE @EndDate date
	SET @EndDate = '1999-12-31'
	DECLARE @CurrentDate date
	SET @CurrentDate = @StartDate

	WHILE (@CurrentDate <= @EndDate)
	BEGIN
		INSERT INTO @Dates
		VALUES (dbo.fn_ConvertToDateKey(@CurrentDate), @CurrentDate, YEAR(@CurrentDate), DATEPART(quarter, @CurrentDate), DATEPART(month, @CurrentDate), DATENAME(weekday, @CurrentDate))
		SET @CurrentDate = DATEADD(day, 1, @CurrentDate)
	END

	RETURN 

END

GO

-- Creating Dim_Dates table

DROP TABLE Northwind_DW.dbo.Dim_Dates

CREATE TABLE Northwind_DW.dbo.Dim_Dates (
	[DateKey] int PRIMARY KEY NOT NULL,
	[Date] date NOT NULL,
	[Year] int NOT NULL,
	[Quarter] int NOT NULL,
	[Month] int NOT NULL,
	[MonthName] nvarchar(10) NOT NULL
)

-- Inserting data into Dim_Dates

INSERT INTO Northwind_DW.dbo.Dim_Dates(DateKey, [Date], [Year], [Quarter], [Month], [MonthName])
SELECT *
FROM NORTHWND.dbo.fn_CreateDays()

-- Insert data into Fact_Sales

TRUNCATE TABLE Northwind_DW.dbo.Dim_Dates

INSERT INTO Northwind_DW.dbo.Fact_Sales(OrderSK, ProductSK, DateKey, CustomerSK, EmployeeSK, UnitPrice, Quantity, Discount)
SELECT DO.OrderSK,  DP.ProductSK, DD.DateKey, DC.CustomerSK, DE.EmployeeSK, OD.UnitPrice, OD.Quantity, OD.Discount
FROM NORTHWND.dbo.[Order Details] OD
JOIN NORTHWND.dbo.Orders O
ON OD.OrderID = O.OrderID
JOIN NORTHWND.dbo.Customers C
ON O.CustomerID = C.CustomerID
JOIN NORTHWND.dbo.Employees E
ON O.EmployeeID = E.EmployeeID
JOIN NORTHWND.dbo.Products P
ON OD.ProductID = P.ProductID
JOIN Northwind_DW.dbo.Dim_Orders DO
ON O.OrderID = DO.OrderBK
JOIN Northwind_DW.dbo.Dim_Customers DC
ON C.CustomerID = DC.CustomerBK
JOIN Northwind_DW.dbo.Dim_Employees DE
ON E.EmployeeID = DE.EmployeeBK
JOIN Northwind_DW.dbo.Dim_Products DP
ON P.ProductID = DP.ProductBK
JOIN Northwind_DW.dbo.Dim_Dates DD
ON NORTHWND.dbo.fn_ConvertToDateKey(O.OrderDate) = DD.DateKey
