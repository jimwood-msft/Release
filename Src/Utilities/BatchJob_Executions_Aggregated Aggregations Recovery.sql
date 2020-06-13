/***********************************************************************************************************************
 ***********************************************************************************************************************

							Run query to determine missing aggregation hours

 ***********************************************************************************************************************
************************************************************************************************************************/

SELECT DISTINCT TOP 20 [BatchJobExecutionDateHourUTC]
FROM BatchJob_Executions_Aggregated
ORDER BY [BatchJobExecutionDateHourUTC] DESC

/***********************************************************************************************************************
 ***********************************************************************************************************************

  Once missing hours are determined set the lower and upper timebounds in the query below. Aggregations are perfromed 
  for the prior hours data. Make sure to account for this in your upper and lower time bounds.

  ex. Missing data from 6/11/20 10:00:.000 to 6/11/20 22:00:.000

  Lower bound would be 6/11/20 11:00:.000 as 11 AM aggregating 1 hour back will provide the 10 AM aggregations
  Upper bound would be 6/12/20 00:00:.000 as midnight will return the 23 hour. 1 hour back would aggregate the 22 hour

  *Highlight and run the select query with your times to make sure if has the range desired prior to runnning the insert

  ** If only a single hour is missing the cursor will not work. Comment out all cursor lines top and bottom but retain
     the last and current hour declarations. Above the SET @LastHour add a new line SET @CurrentHour = and set it to
	 1 hour greater then the hour you need aggregated

 ***********************************************************************************************************************
************************************************************************************************************************/

DECLARE Cursor_Date CURSOR
  FOR SELECT FORMAT(MAX(EndDateTimeUTC),'yyyy-MM-dd HH:00:00.000') AS 'Date' 
  FROM [dbo].[BatchJob_Executions]
  WHERE EndDateTimeUTC >= 'ENTER LOWER TIMEBOUND'
    AND EndDateTimeUTC < 'ENTER UPPER TIMEBOUND'
  GROUP BY FORMAT(EndDateTimeUTC,'yyyy-MM-dd HH:00:00.000')
  ORDER BY 1
DECLARE @LastHour DATETIME
DECLARE @CurrentHour DATETIME
DECLARE @systemId VARCHAR(max)
Declare @DelayThreshold INT

SET @DelayThreshold = 60

OPEN Cursor_Date;

FETCH NEXT FROM Cursor_Date INTO @CurrentHour;

  WHILE @@FETCH_STATUS = 0
  BEGIN
  
    SET @LastHour = (SELECT CAST(CAST(CAST(Dateadd (hour, -1, FORMAT(@CurrentHour,'yyyy-MM-dd HH:00:00.000')) AS DATE) AS CHAR(11)) + LEFT(CAST(CAST(Dateadd (hour, -1, FORMAT(@CurrentHour,'yyyy-MM-dd HH:00:00.000')) AS TIME) AS CHAR), 2) + ':00:00.000' AS DATETIME));

    INSERT INTO BatchJob_Executions_Aggregated
    SELECT a.BatchJobID, 
      a.BatchJobExecutionDateHour,  
      ISNULL(a.TotalExecutions, 0) AS TotalExecutions, 
      ISNULL(b.FailureExecutions, 0) AS FailureExecutions, 
      ISNULL(c.LatencyViolation, 0) AS LatencyViolation,
      ISNULL(d.DelayViolation,0) AS DelayViolation,
      CAST(((ISNULL(a.TotalExecutions, 0) - ISNULL(b.FailureExecutions, 0) - ISNULL(c.LatencyViolation, 0)- ISNULL(d.DelayViolation,0 )) / ( a.TotalExecutions * 1.0 ) ) * 100.0 AS DECIMAL(5, 2))  AS QoS, 
      CAST(((ISNULL(a.TotalExecutions, 0) - ISNULL(b.FailureExecutions, 0)) / ( a.TotalExecutions * 1.0 ) ) * 100.0 AS DECIMAL(5, 2))   AS ReliabilityRate,
      CAST(((ISNULL(c.LatencyViolation, 0) ) / ( a.TotalExecutions * 1.0 ) ) * 100.0 AS DECIMAL(5, 2))   AS LatencyViolationRate,
      CAST(((ISNULL(d.DelayViolation, 0) ) / ( a.TotalExecutions * 1.0 ) ) * 100.0 AS DECIMAL(5, 2))   AS DelayViolationRate 
    FROM
    (
      SELECT BatchJobID,
        DATEADD(Hour, DATEDIFF(Hour, 0, EndDateTimeUTC), 0) AS 'BatchJobExecutionDateHour', 
        COUNT(BatchJobID) AS TotalExecutions
      FROM BatchJob_Executions
      WHERE EndDateTimeUTC >= @LastHour 
        AND EndDateTimeUTC < @CurrentHour
      GROUP BY BatchJobID, DATEADD(Hour, DATEDIFF(Hour, 0, EndDateTimeUTC), 0)
    ) AS a 
    LEFT JOIN 
    (
      SELECT BatchJobID,
        DATEADD(Hour, DATEDIFF(Hour, 0, EndDateTimeUTC), 0) AS 'BatchJobExecutionDateHour', 
        COUNT(BatchJobID) AS FailureExecutions 
      FROM BatchJob_Executions
      WHERE EndDateTimeUTC >= @LastHour 
        AND EndDateTimeUTC < @CurrentHour
        AND Status = 2 
      GROUP BY BatchJobID, DATEADD(Hour, DATEDIFF(Hour, 0, EndDateTimeUTC), 0)
    ) AS b ON a.BatchJobID = b.BatchJobID
        AND a.BatchJobExecutionDateHour = b.BatchJobExecutionDateHour
    LEFT JOIN
    (
      SELECT m.BatchJobID, 
        DATEADD(Hour, DATEDIFF(Hour, 0, ex.EndDateTimeUTC), 0) AS 'BatchJobExecutionDateHour', 
        COUNT(ex.BatchJobID) AS LatencyViolation 
      FROM BatchJob_Executions ex
      INNER JOIN BatchJob_Master m ON ex.BatchJobID = m.BatchJobID
      WHERE ex.EndDateTimeUTC >= @LastHour 
        AND ex.EndDateTimeUTC < @CurrentHour 
        AND ( ex.Duration > m.LatencyThreshold and Status = 1)
      GROUP BY m.BatchJobID, DATEADD(Hour, DATEDIFF(Hour, 0, ex.EndDateTimeUTC), 0)
    ) AS c ON c.BatchJobID = a.BatchJobID
        AND c.BatchJobExecutionDateHour = a.BatchJobExecutionDateHour
    LEFT JOIN
    (
      SELECT BatchJobID,
        DATEADD(Hour, DATEDIFF(Hour, 0, EndDateTimeUTC), 0) AS 'BatchJobExecutionDateHour', 
        COUNT(BatchJobID) AS DelayViolation 
      FROM BatchJob_Executions 
      WHERE EndDateTimeUTC >= @LastHour 
        AND EndDateTimeUTC < @CurrentHour 
        AND ( Delay > @DelayThreshold and Status = 1)
      GROUP BY BatchJobID, DATEADD(Hour, DATEDIFF(Hour, 0, EndDateTimeUTC), 0)
    ) AS d ON a.BatchJobID = d.BatchJobID
        AND a.BatchJobExecutionDateHour = d.BatchJobExecutionDateHour

    --DELETE BatchJob_Executions
    --WHERE EndDateTimeUTC >= @LastHour 
    --  AND EndDateTimeUTC < @CurrentHour
    --  AND EndDateTimeUTC < DATEADD(day, -10, GETUTCDATE())
		
    FETCH NEXT FROM Cursor_Date INTO  @CurrentHour;
  END

CLOSE Cursor_Date;
DEALLOCATE Cursor_Date;