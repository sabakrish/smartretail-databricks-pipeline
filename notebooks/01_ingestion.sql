-- Databricks notebook source
-- MAGIC %md
-- MAGIC # 01 – Ingestion
-- MAGIC Sets up the schema and a Unity Catalog volume for raw files, then checks that the source CSV is readable.
-- MAGIC
-- MAGIC **Before running:** upload `data/retail_store_inventory_data.csv` to the volume
-- MAGIC (Catalog → workspace → smartretail → raw_files → *Upload to this volume*).

-- COMMAND ----------

CREATE SCHEMA IF NOT EXISTS workspace.smartretail;
USE CATALOG workspace;
USE SCHEMA smartretail;

-- COMMAND ----------

-- Volume = managed storage location for raw source files
CREATE VOLUME IF NOT EXISTS raw_files;

-- COMMAND ----------

-- Confirm the file is in the volume
LIST '/Volumes/workspace/smartretail/raw_files/';

-- COMMAND ----------

-- Preview the raw file (header row, inferred types)
SELECT *
FROM read_files(
  '/Volumes/workspace/smartretail/raw_files/retail_store_inventory_data.csv',
  format => 'csv',
  header => true
)
LIMIT 10;

-- COMMAND ----------

-- Source row count: used later by the validation notebook (expected 73,100)
SELECT COUNT(*) AS source_row_count
FROM read_files(
  '/Volumes/workspace/smartretail/raw_files/retail_store_inventory_data.csv',
  format => 'csv',
  header => true
);