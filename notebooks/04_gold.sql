-- Databricks notebook source
-- MAGIC %md
-- MAGIC # 04 – Gold layer (star schema)
-- MAGIC - `dim_date`, `dim_store`, `dim_product` – dimensions
-- MAGIC - `fact_store_product_daily` – one row per date + store + product
-- MAGIC - `gold_monthly_region_sales`, `gold_category_sales` – summary tables for Power BI

-- COMMAND ----------

USE CATALOG workspace;
USE SCHEMA smartretail;

-- COMMAND ----------

CREATE OR REPLACE TABLE dim_date AS
SELECT DISTINCT
  CAST(date_format(sale_date, 'yyyyMMdd') AS INT) AS date_key,
  sale_date                                       AS full_date,
  year(sale_date)                                 AS year,
  quarter(sale_date)                              AS quarter,
  month(sale_date)                                AS month_number,
  date_format(sale_date, 'MMMM')                  AS month_name,
  date_format(sale_date, 'yyyy-MM')               AS year_month,
  date_format(sale_date, 'EEEE')                  AS day_name,
  dayofweek(sale_date) IN (1, 7)                  AS is_weekend,
  CASE
    WHEN month(sale_date) IN (12, 1, 2) THEN 'Winter'
    WHEN month(sale_date) IN (3, 4, 5)  THEN 'Spring'
    WHEN month(sale_date) IN (6, 7, 8)  THEN 'Summer'
    ELSE 'Autumn'
  END                                             AS season
FROM silver_retail_inventory;

-- COMMAND ----------

CREATE OR REPLACE TABLE dim_store AS
SELECT
  store_id,
  MIN(sale_date) AS first_sale_date,
  MAX(sale_date) AS last_sale_date
FROM silver_retail_inventory
GROUP BY store_id;

-- COMMAND ----------

CREATE OR REPLACE TABLE dim_product AS
SELECT
  product_id,
  MIN(sale_date) AS first_sale_date,
  MAX(sale_date) AS last_sale_date
FROM silver_retail_inventory
GROUP BY product_id;

-- COMMAND ----------

CREATE OR REPLACE TABLE fact_store_product_daily AS
SELECT
  CAST(date_format(sale_date, 'yyyyMMdd') AS INT) AS date_key,
  store_id,
  product_id,
  category,
  region,
  inventory_level,
  units_sold,
  units_ordered,
  demand_forecast,
  forecast_was_negative,
  price,
  discount_pct,
  net_revenue,
  competitor_price,
  price - competitor_price                        AS price_gap_vs_competitor,
  weather_condition,
  is_holiday_promotion
FROM silver_retail_inventory;

-- COMMAND ----------

CREATE OR REPLACE TABLE gold_monthly_region_sales AS
SELECT
  d.year_month,
  f.region,
  SUM(f.net_revenue)                 AS net_revenue,
  SUM(f.units_sold)                  AS units_sold,
  ROUND(AVG(f.inventory_level), 1)   AS avg_inventory_level
FROM fact_store_product_daily f
JOIN dim_date d ON f.date_key = d.date_key
GROUP BY d.year_month, f.region;

-- COMMAND ----------

CREATE OR REPLACE TABLE gold_category_sales AS
SELECT
  category,
  SUM(net_revenue)                                         AS net_revenue,
  SUM(units_sold)                                          AS units_sold,
  ROUND(SUM(units_sold) / SUM(units_sold + inventory_level), 3) AS sell_through_rate
FROM fact_store_product_daily
GROUP BY category;

-- COMMAND ----------

-- Quick look: revenue by region
SELECT region, SUM(net_revenue) AS net_revenue
FROM fact_store_product_daily
GROUP BY region
ORDER BY net_revenue DESC;