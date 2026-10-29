-- Databricks notebook source
-- MAGIC %md
-- MAGIC # 05 – Validation
-- MAGIC Verifies that data moved through each layer completely and correctly.
-- MAGIC Results are saved to `validation_results` (latest run) and appended to `validation_log` (history).
-- MAGIC The last cell **fails the notebook** if any check fails, so a scheduled job stops on bad data.

-- COMMAND ----------

USE CATALOG workspace;
USE SCHEMA smartretail;

-- COMMAND ----------

CREATE OR REPLACE TABLE validation_results AS
WITH
src    AS (SELECT COUNT(*) AS n FROM read_files('/Volumes/workspace/smartretail/raw_files/retail_store_inventory_data.csv', format => 'csv', header => true)),
bronze AS (SELECT COUNT(*) AS n, SUM(CAST(units_sold AS BIGINT)) AS units FROM bronze_retail_inventory),
silver AS (SELECT COUNT(*) AS n, SUM(net_revenue) AS revenue,
                  COUNT(DISTINCT sale_date, store_id, product_id) AS distinct_keys,
                  datediff(MAX(sale_date), MIN(sale_date)) + 1 AS calendar_days,
                  COUNT(DISTINCT sale_date) AS distinct_days
           FROM silver_retail_inventory),
rej    AS (SELECT COUNT(*) AS n FROM silver_rejected_rows),
fact   AS (SELECT COUNT(*) AS n, SUM(net_revenue) AS revenue, SUM(CAST(units_sold AS BIGINT)) AS units FROM fact_store_product_daily),
checks AS (
  SELECT 1 AS check_id, 'Source file rows = Bronze rows' AS check_name,
         CAST(src.n AS STRING) AS expected, CAST(bronze.n AS STRING) AS actual,
         src.n = bronze.n AS passed
  FROM src, bronze
  UNION ALL
  SELECT 2, 'Bronze rows = Silver rows + rejected rows',
         CAST(bronze.n AS STRING), CAST(silver.n + rej.n AS STRING), bronze.n = silver.n + rej.n
  FROM bronze, silver, rej
  UNION ALL
  SELECT 3, 'Silver has no duplicate date + store + product',
         CAST(silver.n AS STRING), CAST(silver.distinct_keys AS STRING), silver.n = silver.distinct_keys
  FROM silver
  UNION ALL
  SELECT 4, 'Silver key columns have no NULLs', '0',
         CAST(COUNT(*) AS STRING), COUNT(*) = 0
  FROM silver_retail_inventory
  WHERE sale_date IS NULL OR store_id IS NULL OR product_id IS NULL
  UNION ALL
  SELECT 5, 'Fact rows = Silver rows',
         CAST(silver.n AS STRING), CAST(fact.n AS STRING), silver.n = fact.n
  FROM silver, fact
  UNION ALL
  SELECT 6, 'Every fact row matches dim_date', '0', CAST(COUNT(*) AS STRING), COUNT(*) = 0
  FROM fact_store_product_daily f LEFT ANTI JOIN dim_date d ON f.date_key = d.date_key
  UNION ALL
  SELECT 7, 'Every fact row matches dim_store', '0', CAST(COUNT(*) AS STRING), COUNT(*) = 0
  FROM fact_store_product_daily f LEFT ANTI JOIN dim_store s ON f.store_id = s.store_id
  UNION ALL
  SELECT 8, 'Every fact row matches dim_product', '0', CAST(COUNT(*) AS STRING), COUNT(*) = 0
  FROM fact_store_product_daily f LEFT ANTI JOIN dim_product p ON f.product_id = p.product_id
  UNION ALL
  SELECT 9, 'Net revenue reconciles Silver to Fact',
         CAST(silver.revenue AS STRING), CAST(fact.revenue AS STRING), abs(silver.revenue - fact.revenue) < 0.01
  FROM silver, fact
  UNION ALL
  SELECT 10, 'Units sold reconcile Bronze to Fact (no rejects)',
         CAST(bronze.units AS STRING), CAST(fact.units AS STRING), bronze.units = fact.units OR rej.n > 0
  FROM bronze, fact, rej
  UNION ALL
  SELECT 11, 'No missing days in date range',
         CAST(silver.calendar_days AS STRING), CAST(silver.distinct_days AS STRING), silver.calendar_days = silver.distinct_days
  FROM silver
  UNION ALL
  SELECT 12, 'Units sold never exceed inventory level', '0', CAST(COUNT(*) AS STRING), COUNT(*) = 0
  FROM silver_retail_inventory
  WHERE units_sold > inventory_level
)
SELECT
  check_id,
  check_name,
  expected,
  actual,
  CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS status,
  current_timestamp()                          AS checked_at
FROM checks;

-- COMMAND ----------

SELECT * FROM validation_results ORDER BY check_id;

-- COMMAND ----------

-- Keep a history of every run
CREATE TABLE IF NOT EXISTS validation_log AS SELECT * FROM validation_results WHERE 1 = 0;
INSERT INTO validation_log SELECT * FROM validation_results;

-- COMMAND ----------

-- Informational: rows flagged during cleaning (not a failure)
SELECT 'negative demand forecasts set to NULL' AS item, COUNT(*) AS row_count
FROM silver_retail_inventory WHERE forecast_was_negative
UNION ALL
SELECT 'rejected rows', COUNT(*) FROM silver_rejected_rows;

-- COMMAND ----------

-- Stop the run if any check failed
SELECT CASE
         WHEN COUNT(*) > 0 THEN raise_error(concat(COUNT(*), ' validation check(s) failed – see validation_results'))
         ELSE 'All validation checks passed'
       END AS result
FROM validation_results
WHERE status = 'FAIL';