-- Databricks notebook source
-- MAGIC %md
-- MAGIC # 02 – Bronze layer
-- MAGIC Loads the raw CSV as-is. Values are not changed; columns are only renamed to snake_case
-- MAGIC (Delta tables do not allow spaces or `/` in column names). Two audit columns record
-- MAGIC where and when each row was loaded.

-- COMMAND ----------

USE CATALOG workspace;
USE SCHEMA smartretail;

-- COMMAND ----------

CREATE OR REPLACE TABLE bronze_retail_inventory AS
SELECT
  `Date`               AS sale_date,
  `Store ID`           AS store_id,
  `Product ID`         AS product_id,
  `Category`           AS category,
  `Region`             AS region,
  `Inventory Level`    AS inventory_level,
  `Units Sold`         AS units_sold,
  `Units Ordered`      AS units_ordered,
  `Demand Forecast`    AS demand_forecast,
  `Price`              AS price,
  `Discount`           AS discount,
  `Weather Condition`  AS weather_condition,
  `Holiday/Promotion`  AS holiday_promotion,
  `Competitor Pricing` AS competitor_pricing,
  `Seasonality`        AS seasonality,
  _metadata.file_path  AS _source_file,
  current_timestamp()  AS _ingested_at
FROM read_files(
  '/Volumes/workspace/smartretail/raw_files/retail_store_inventory_data.csv',
  format => 'csv',
  header => true
);

-- COMMAND ----------

SELECT COUNT(*) AS bronze_rows FROM bronze_retail_inventory;

-- COMMAND ----------

DESCRIBE TABLE bronze_retail_inventory;