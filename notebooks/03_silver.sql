-- Databricks notebook source
-- MAGIC %md
-- MAGIC # 03 – Silver layer
-- MAGIC Cleans and standardizes the Bronze data:
-- MAGIC - casts every column to an explicit type and trims/standardizes text
-- MAGIC - removes duplicates on the natural key (date + store + product)
-- MAGIC - sends invalid rows to a **rejected** table with a reason, instead of silently dropping them
-- MAGIC - sets negative demand forecasts to NULL and flags them
-- MAGIC - calculates net revenue
-- MAGIC
-- MAGIC Every Bronze row ends up in exactly one of `silver_retail_inventory` or `silver_rejected_rows`.

-- COMMAND ----------

USE CATALOG workspace;
USE SCHEMA smartretail;

-- COMMAND ----------

-- Typed, standardized rows with a duplicate rank and a rejection reason (NULL = valid)
CREATE OR REPLACE TEMP VIEW silver_staging AS
WITH typed AS (
  SELECT
    try_cast(CAST(sale_date AS STRING) AS DATE)       AS sale_date,
    upper(trim(CAST(store_id AS STRING)))              AS store_id,
    upper(trim(CAST(product_id AS STRING)))            AS product_id,
    initcap(trim(CAST(category AS STRING)))            AS category,
    initcap(trim(CAST(region AS STRING)))              AS region,
    try_cast(inventory_level AS INT)                   AS inventory_level,
    try_cast(units_sold AS INT)                        AS units_sold,
    try_cast(units_ordered AS INT)                     AS units_ordered,
    try_cast(demand_forecast AS DECIMAL(10,2))         AS demand_forecast_raw,
    try_cast(price AS DECIMAL(10,2))                   AS price,
    try_cast(discount AS INT)                          AS discount_pct,
    initcap(trim(CAST(weather_condition AS STRING)))   AS weather_condition,
    try_cast(holiday_promotion AS INT) = 1             AS is_holiday_promotion,
    try_cast(competitor_pricing AS DECIMAL(10,2))      AS competitor_price,
    initcap(trim(CAST(seasonality AS STRING)))         AS source_seasonality,
    _source_file,
    _ingested_at
  FROM bronze_retail_inventory
),
ranked AS (
  SELECT *,
    ROW_NUMBER() OVER (
      PARTITION BY sale_date, store_id, product_id
      ORDER BY _ingested_at DESC
    ) AS dup_rank
  FROM typed
)
SELECT *,
  CASE
    WHEN sale_date IS NULL OR store_id IS NULL OR product_id IS NULL THEN 'Missing key (date, store or product)'
    WHEN dup_rank > 1                                               THEN 'Duplicate of date + store + product'
    WHEN units_sold IS NULL OR units_sold < 0                       THEN 'Invalid units sold'
    WHEN inventory_level IS NULL OR inventory_level < 0             THEN 'Invalid inventory level'
    WHEN price IS NULL OR price <= 0                                THEN 'Invalid price'
    WHEN discount_pct IS NULL OR discount_pct NOT BETWEEN 0 AND 100 THEN 'Invalid discount'
  END AS reject_reason
FROM ranked;

-- COMMAND ----------

CREATE OR REPLACE TABLE silver_retail_inventory AS
SELECT
  sale_date,
  store_id,
  product_id,
  category,
  region,
  inventory_level,
  units_sold,
  units_ordered,
  CASE WHEN demand_forecast_raw < 0 THEN NULL ELSE demand_forecast_raw END AS demand_forecast,
  demand_forecast_raw < 0                                                AS forecast_was_negative,
  price,
  discount_pct,
  CAST(round(units_sold * price * (1 - discount_pct / 100.0), 2) AS DECIMAL(14,2)) AS net_revenue,
  competitor_price,
  weather_condition,
  is_holiday_promotion,
  source_seasonality,
  _source_file,
  _ingested_at
FROM silver_staging
WHERE reject_reason IS NULL;

-- COMMAND ----------

CREATE OR REPLACE TABLE silver_rejected_rows AS
SELECT *, current_timestamp() AS _rejected_at
FROM silver_staging
WHERE reject_reason IS NOT NULL;

-- COMMAND ----------

-- Load summary
SELECT 'silver_retail_inventory' AS table_name, COUNT(*) AS row_count FROM silver_retail_inventory
UNION ALL
SELECT 'silver_rejected_rows', COUNT(*) FROM silver_rejected_rows
UNION ALL
SELECT 'negative forecasts set to NULL', COUNT(*) FROM silver_retail_inventory WHERE forecast_was_negative;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Data-quality findings (profiling)
-- MAGIC - Each `product_id` appears under **all 5 categories**, and each `store_id` under **all 4 regions**.
-- MAGIC   Category and region are therefore not stable attributes of a product or store, so they are kept
-- MAGIC   at row level in the fact table rather than on the dimensions.
-- MAGIC - `source_seasonality` does not match the calendar (one date can carry several seasons).
-- MAGIC   The Gold layer derives season from the date instead.
-- MAGIC - 673 rows have a negative demand forecast. These are set to NULL and flagged.

-- COMMAND ----------

-- Evidence for the findings above
SELECT 'categories per product (max)' AS finding, MAX(n) AS value
FROM (SELECT product_id, COUNT(DISTINCT category) AS n FROM silver_retail_inventory GROUP BY product_id)
UNION ALL
SELECT 'regions per store (max)', MAX(n)
FROM (SELECT store_id, COUNT(DISTINCT region) AS n FROM silver_retail_inventory GROUP BY store_id)
UNION ALL
SELECT 'seasons per date (max)', MAX(n)
FROM (SELECT sale_date, COUNT(DISTINCT source_seasonality) AS n FROM silver_retail_inventory GROUP BY sale_date);