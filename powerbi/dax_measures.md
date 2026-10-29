# Power BI – Semantic Model and DAX Measures

## Tables (Import mode)

| Table | Role |
|---|---|
| `fact_store_product_daily` | Fact – one row per date + store + product |
| `dim_date` | Date dimension (marked as date table on `full_date`) |
| `dim_store` | Store dimension |
| `dim_product` | Product dimension |
| `validation_results` | Data-quality page (no relationships) |

## Relationships

| From (many) | To (one) | Filter |
|---|---|---|
| `fact_store_product_daily[date_key]` | `dim_date[date_key]` | Single |
| `fact_store_product_daily[store_id]` | `dim_store[store_id]` | Single |
| `fact_store_product_daily[product_id]` | `dim_product[product_id]` | Single |

`dim_date[month_name]` is sorted by `dim_date[month_number]`.

## Measures

Create a blank table called `_Measures` (Enter data → name it → Load) and add these measures to it.

```DAX
Total Net Revenue =
SUM ( fact_store_product_daily[net_revenue] )

Total Units Sold =
SUM ( fact_store_product_daily[units_sold] )

Avg Selling Price =
DIVIDE ( [Total Net Revenue], [Total Units Sold] )

Avg Inventory Level =
AVERAGE ( fact_store_product_daily[inventory_level] )

Sell-Through Rate =
DIVIDE (
    [Total Units Sold],
    [Total Units Sold] + SUM ( fact_store_product_daily[inventory_level] )
)

-- Shows a value only when one year is selected (2023 vs 2022 = -1.0%)
Revenue YoY % =
IF (
    HASONEVALUE ( dim_date[year] ),
    VAR PrevYear =
        CALCULATE ( [Total Net Revenue], SAMEPERIODLASTYEAR ( dim_date[full_date] ) )
    RETURN
        DIVIDE ( [Total Net Revenue] - PrevYear, PrevYear )
)

Promo Revenue Share =
DIVIDE (
    CALCULATE ( [Total Net Revenue], fact_store_product_daily[is_holiday_promotion] = TRUE () ),
    [Total Net Revenue]
)

Forecast Accuracy % =
VAR ValidRows =
    FILTER (
        fact_store_product_daily,
        NOT ISBLANK ( fact_store_product_daily[demand_forecast] )
    )
VAR AbsError =
    SUMX (
        ValidRows,
        ABS ( fact_store_product_daily[units_sold] - fact_store_product_daily[demand_forecast] )
    )
VAR Actual =
    SUMX ( ValidRows, fact_store_product_daily[units_sold] )
RETURN
    1 - DIVIDE ( AbsError, Actual )

Avg Price Gap vs Competitor =
AVERAGE ( fact_store_product_daily[price_gap_vs_competitor] )

Validation Checks Passed =
COUNTROWS ( FILTER ( validation_results, validation_results[status] = "PASS" ) )

Validation Pass Rate =
DIVIDE ( [Validation Checks Passed], COUNTROWS ( validation_results ) )
```

Formats: revenue measures as currency (0 decimals); `Sell-Through Rate`, `Revenue YoY %`, `Promo Revenue Share`, `Forecast Accuracy %` and `Validation Pass Rate` as percentage (1 decimal).

## Report pages

1. **Executive Summary** – cards: Total Net Revenue, Total Units Sold, Avg Selling Price, Sell-Through Rate, Revenue YoY %; line chart of revenue by `year_month`; bar chart of revenue by `region`; slicers for year, region, category.
2. **Sales Performance** – revenue by category; revenue by store; matrix of store × category; promo vs non-promo revenue.
3. **Inventory & Forecast** – avg inventory level by month; units sold vs demand forecast by month; Forecast Accuracy % card; price gap vs competitor by category.
4. **Data Quality** – Validation Pass Rate card; table of `validation_results` (check, expected, actual, status) with conditional formatting on status; architecture diagram image.
