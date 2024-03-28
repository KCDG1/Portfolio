USE [EBM_dbo.name] -- change db.name to your database name


---- User Inputs influenced directly by UI or backend hardcode

DECLARE @UserSelectedInputs NVARCHAR(MAX)  = 'Monthly Sales > 0' --selected methodology, either monthly sales or 1st invoice  
		,@Amount NVARCHAR(255) = 'Revenue'    -- change to what amount you want to be measured on
		,@DateField NVARCHAR(100) = 'Fact[CalendarDate]'-- Date reference (CalendarDate/BillDate etc.)	
		,@UserSelectedColumnName NVARCHAR(100) = 'Customer' --Selected column name
		,@UserSelectedTableName NVARCHAR (100) = 'Test_Customer'  --selected table name
		,@CohortNameuserselect nvarchar(100)  = 'Testing' --selected name of cohort

		,@CalculatedColumnName NVARCHAR(100) 
		,@CohortName nvarchar(100) 
		,@TableType NVARCHAR(100)
		,@Column NVARCHAR(100)  
		,@NewDynamicCubeAttributeTableID INT 
		,@AttributeTableUserSelected NVARCHAR(100) 
		,@return_value NVARCHAR (100)
		,@NewDynamicCubeCalculatedColumnID INT
		,@FactTableID INT = 2
		,@UserID INT = 1000000
		,@DaxCode NVARCHAR(MAX)
		,@DatabaseName nvarchar(100)
		,@NewDynamicCubeTableRelationshipID INT
		,@AttributeTableColumnKeyID INT
		,@CustomerMonthlySales NVARCHAR(100)
		,@TestingNewCalcColumn NVARCHAR(100)

--These variables effect Dax Code all values are temp just to get it running Should be direct connect to UI

SELECT @Column = @UserSelectedColumnName 
 ,@CohortName = @CohortNameuserselect
 ,@CalculatedColumnName = @CohortName + ' Cohort Date' -- change these to whatever will distinguish your cohort
 ,@AttributeTableUserSelected = @CohortName + '_Cohort_Dates'
 ,@DatabaseName = DB_NAME()
 ,@TestingNewCalcColumn = @CohortName +'_CustomerMonthlySales'


--============Define Dax code based on user-selected inputs========

-- User Selects Table then SSMS pulls columns and Assigns TableType 

DECLARE @MeasureSelection NVARCHAR(MAX);

SET @MeasureSelection = N'
USE '+QUOTENAME(@DatabaseName)+'
SELECT a.[Table], a.ColumnName, a.[TableType] 
FROM
(
    SELECT [DynamicCubeAttributeTableColumnID]
          , atab.[AttributeTable] AS [Table]
          , [ColumnName]
          , [DisplayName]
          , [DataType]
          , [IsKey]
          , [IsUnique]
          , [IsNullable]
          , [IsHidden]
          , [IsAvailableInDAX]
          , [IsStandardMeasure]
          , [MasterDataTypeID]
          , ''Attribute'' AS [TableType]
    FROM ' + QUOTENAME(@DatabaseName) + '.[dbo].[tbl_Dynamic_Cube_Attribute_Table_Column] acol
    JOIN ' + QUOTENAME(@DatabaseName) + '.[dbo].[tbl_Dynamic_Cube_Attribute_Table] atab
        ON atab.[DynamicCubeAttributeTableID] = acol.[DynamicCubeAttributeTableID]
    
    UNION ALL
    
    SELECT [DynamicCubeFactTableColumnID]
          , ftab.[FactTable] AS [Table]
          , [ColumnName]
          , [DisplayName]
          , [DataType]
          , [IsKey]
          , [IsUnique]
          , [IsNullable]
          , [IsHidden]
          , [IsAvailableInDAX]
          , [StandardMeasures]
          , [MasterDataTypeID]
          , ''Fact'' AS [TableType]
    FROM ' + QUOTENAME(@DatabaseName) + '.[dbo].[tbl_Dynamic_Cube_Fact_Table_Column] fcol
    JOIN ' + QUOTENAME(@DatabaseName) + '.[dbo].[tbl_Dynamic_Cube_Fact_Table] ftab
        ON ftab.[DynamicCubeFactTableID] = fcol.[DynamicCubeFactTableID]
) a';


--============Define Dax code based on user-selected inputs======== 



-- Create a temporary table to store the results
CREATE TABLE #MeasureSelection (
  TableName NVARCHAR(MAX),
  ColumnName NVARCHAR(MAX),
  TableType NVARCHAR(MAX)
);

-- Insert the data into the temporary table
INSERT INTO #MeasureSelection (TableName, ColumnName, TableType)
EXEC sp_executesql @MeasureSelection;

-- Retrieve the table type based on the user-selected column
SELECT @TableType = TableType
FROM #MeasureSelection
WHERE ColumnName = @UserSelectedColumnName
AND TableName = @UserSelectedTableName; 


SELECT * FROM #MeasureSelection
DROP TABLE #MeasureSelection;

--================= Run if Conditions below are true ==============

IF (@UserSelectedInputs = 'Monthly Sales > 0' AND @TableType = 'Fact') 
BEGIN
    SET @DaxCode = '
	  var monthly = CALCULATE (
    SUM (''Fact''['+@Amount+'] ),
    ALLEXCEPT (
        ''Fact'',
        ''Time''[FiscalYear],
        ''Time''[FiscalPeriod],
        '''+@UserSelectedTableName+'''['+@Column+']
)
       IF (
            NOT(ISBLANK('''+@UserSelectedTableName+'''['+@Column+'])),  
            MINX(
                FILTER(
                    ALL(''Fact''),
                    [monthly] > 0
                    && ['+@Column+'] = EARLIER('''+@UserSelectedTableName+'''['+@Column+'])
                ),
                DATEVALUE('+@DateField+')
            )
        )'
END


ELSE IF (@UserSelectedInputs = 'Monthly Sales > 0' AND @TableType = 'Attribute') ---edit ifs
BEGIN
    SET @DaxCode = '
   var monthly = CALCULATE (
    SUM (''Fact''['+@Amount+'] ),
    ALLEXCEPT (
        ''Fact'',
        ''Time''[FiscalYear],
        ''Time''[FiscalPeriod],
        '''+@UserSelectedTableName+'''['+@Column+']
    )
)

return 
        IF (
            NOT(ISBLANK(RELATED('''+@UserSelectedTableName+'''['+@Column+']))),
            MINX(
                FILTER(
                    ALL(''Fact''),
                    monthly > 0
                    && RELATED('''+@UserSelectedTableName+'''['+@Column+']) = EARLIER(RELATED('''+@UserSelectedTableName+'''['+@Column+']))
                ),
                DATEVALUE(Fact['+@DateField+'])
            )
        )'
END

  
ELSE IF (@UserSelectedInputs = '1st Invoice' AND @TableType = 'Fact')
BEGIN
    SET @DaxCode = '
        IF (
            NOT(ISBLANK('''+@UserSelectedTableName+'''['+@Column+'])),
            MINX(
                FILTER(ALL(''Fact''), '''+@UserSelectedTableName+'''['+@Column+'] = EARLIER('''+@UserSelectedTableName+'''['+@Column+'])),
                DATEVALUE('+@DateField+')
            )
        )'
END


ELSE IF (@UserSelectedInputs = '1st Invoice' AND @TableType = 'Attribute')
BEGIN
    SET @DaxCode = '
        IF (
            NOT(ISBLANK(RELATED('''+@UserSelectedTableName+'''['+@Column+']))),
            MINX(
                FILTER(
                    ALL(''Fact''),
                    RELATED('''+@UserSelectedTableName+'''['+@Column+']) = EARLIER(RELATED('''+@UserSelectedTableName+'''['+@Column+']))
                ),
                DATEVALUE('+@DateField+')
            )
        )'

END

--===============Calc Column insert Stored Procedure ================================


 EXECUTE [dbo].[Dynamic_Cube_Calculated_Column_Insert] 
  @UserID = @UserID
  ,@CalculatedColumnName = @CalculatedColumnName
  ,@CalculatedColumnExpression = @DaxCode 
  ,@FormatString =''
  ,@DynamicCubeFactTableID = @FactTableID 
  ,@IsHidden = 0
  ,@StandardNameFactTableColumnID = NULL
  ,@NewDynamicCubeCalculatedColumnID = @NewDynamicCubeCalculatedColumnID OUTPUT



--===============Create a Cohort Attribute Table========================================
--
DECLARE @SQLQUERY NVARCHAR(MAX);


SET @SQLQUERY = N'
USE ' + QUOTENAME(@DatabaseName) + ';
SELECT [CalendarDate],
       [FiscalYear],
       [FiscalQuarter],
       [FiscalPeriod],
       [FiscalQuarterDescription],
       [FiscalPeriodDescription],
       [FiscalPeriodDescriptionMonthName],
       CONCAT([FiscalYear], '' Cohort'') AS [Annual Cohort],
       CONCAT([FiscalYear], '' '', [FiscalQuarterDescription]) AS [Quarterly Cohort],
       CONCAT([FiscalYear], ''-'', RIGHT(CONCAT(''0'', [FiscalPeriod]), 2), '' Cohort'') AS [Monthly Cohort]
INTO ' + QUOTENAME(@DatabaseName) + '.[dynamic].' + QUOTENAME(@AttributeTableUserSelected) + '
FROM [dbo].[vw_Core_Fiscal_Date]';

EXEC sp_executesql @SQLQUERY;

--=======================Assigns the cohort table as an attribute table and retrieves the Attribute Table ID====================================
-- Pull the keys from Attribute (Cohort) and fact table creates a relationship and joins 
-- Executes the Dynamic_Cube_Attribute_Table_Insert stored procedure



EXEC @return_value = [dbo].[Dynamic_Cube_Attribute_Table_Insert]
     @UserID = 1000000
    ,@AttributeTable = @AttributeTableUserSelected
    ,@NewDynamicCubeAttributeTableID = @NewDynamicCubeAttributeTableID OUTPUT;

	SELECT	'Return Value Table Insert' = @return_value
	    	,@NewDynamicCubeAttributeTableID as N'@NewDynamicCubeAttributeTableID'


--=========Gets the CalendarDate key from the created cohort date table============

SELECT @AttributeTableColumnKeyID = B.DynamicCubeAttributeTableColumnID 
FROM dbo.tbl_Dynamic_Cube_Attribute_Table A
JOIN dbo.tbl_Dynamic_Cube_Attribute_Table_Column B ON A.DynamicCubeAttributeTableID = B.DynamicCubeAttributeTableID
WHERE A.DynamicCubeAttributeTableID = @NewDynamicCubeAttributeTableID
AND B.ColumnName = 'CalendarDate';



--====Create a relationship between the attribute table and the fact table insert the calculated column=======


EXECUTE [dbo].[Dynamic_Cube_Table_Relationship_Insert] 
   @UserID = @UserID
  ,@FromDynamicCubeTableID = @FactTableID 
  ,@ToDynamicCubeTableID = @NewDynamicCubeAttributeTableID
  ,@FromDynamicCubeTableColumnID = @NewDynamicCubeCalculatedColumnID
  ,@ToDynamicCubeTableColumnID = @AttributeTableColumnKeyID
  ,@IsCalculatedColumn = 1
 ,@NewDynamicCubeTableRelationshipID = @NewDynamicCubeTableRelationshipID OUTPUT




