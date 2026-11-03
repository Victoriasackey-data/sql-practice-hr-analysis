
-- does resigned  employees status have high overtime rate compared to Active employee status?

/*Calculate a company-wide overtime threshold
  top quartile of overtime_hours across all records)*/
  WITH top_quartil AS (
  SELECT employee_id,
         overtime_hours,
         COUNT(*) OVER() overtime_Count,
         ROW_NUMBER() OVER(ORDER BY overtime_hours) Overtime_row
  FROM attendance
),
Threshold AS (
  SELECT overtime_hours
  FROM top_quartil
  WHERE Overtime_row >= CEIL(0.75 * overtime_Count)
),
Cut_off AS (
  SELECT MIN(overtime_hours) Threshold_cutof
  FROM Threshold
),
Exceed AS (
  SELECT employee_id,
         attendance_month,
         overtime_hours,
         CASE WHEN overtime_hours >= c.Threshold_cutof THEN 'High' ELSE 'Not_high' END High_overtime
  FROM attendance a
  CROSS JOIN Cut_off c
),
high_months AS(
SELECT employee_id,
         High_overtime,
         YEAR(attendance_month) Overtime_year,
         COUNT(attendance_month) Num_high_months
  FROM Exceed
  GROUP BY employee_id, High_overtime, YEAR(attendance_month)
),
/* Rule: an employee is flagged "Exceed hour" if they had high overtime in 3 or more months
 within one calendar year. The data covers 3 years, so months are counted per year.*/
-- The 3-month cut-off was a working choice, and its original reason was not recorded.
Classify_employees AS (
  SELECT employee_id,
         Overtime_year,
         Num_high_months,
         CASE 
           WHEN Num_high_months >= 3 THEN 'Exceed hour'ELSE 'Within Hour'END AS Classify
  FROM high_months
  WHERE High_overtime = 'High'
), 
Ever_High AS(
  SELECT  employee_id,
  MAX(CASE WHEN Classify = 'Exceed hour' THEN 1 ELSE 0 END) AS Ever_High_Overtime
  FROM Classify_employees
  GROUP BY employee_id
),
At_num AS(
SELECT e.employment_status,
	COALESCE(eh.Ever_High_Overtime, 0) AS Ever_High_Overtime,
	COUNT(*) Attrition_number
FROM employees e
LEFT JOIN  Ever_High eh
  ON e.employee_id = eh.employee_id
 GROUP BY   e.employment_status,
          COALESCE(eh.Ever_High_Overtime, 0) 
),
Total AS(
 SELECT employment_status,
     SUM(Attrition_number) Total_AR
 FROM At_num
GROUP BY employment_status
),
Ac_Re AS(
SELECT t.employment_status,
	    Ever_High_Overtime,
        Attrition_number,
        Total_AR
FROM At_num a
JOIN Total t
  ON a.employment_status = t.employment_status
WHERE a.Ever_High_Overtime  = 1
),
Resigned_pct AS(
SELECT employment_status,
      CONCAT(ROUND((Attrition_number/Total_AR)*100,2),'%') Resigned_pct
FROM Ac_Re
WHERE employment_status = 'Resigned'
),
Active_pct AS(
SELECT employment_status,
      CONCAT(ROUND((Attrition_number/Total_AR)*100,2),'%') Active_pct
FROM Ac_Re
WHERE employment_status = 'Active'
)
SELECT  a.employment_status,
         Resigned_pct,
         Active_pct
FROM Resigned_pct  re
CROSS JOIN Active_pct a

;   
  /* CONCLUSION:
   The data does not support the hypothesis: Resigned employees had a lower
   high-overtime rate (47.62%) than Active employees (64.90%).
*/
-- Limitations: the result depends on the 3-month rule. High months in different years are
-- not added together.