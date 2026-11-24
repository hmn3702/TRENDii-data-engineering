# TRENDii - Data Engineering Task

Turns raw ad-tech events (tagloads, mounts, product impressions, clicks) plus
product and campaign dimensions into an analysis-ready **star schema** in
DuckDB, answers the five analysis questions, and checks data quality.

- **Answers:** [`docs/ANALYSIS.md`](docs/ANALYSIS.md) (CSV versions in `output/`)
- **Model design:** [`docs/DATA_MODEL.md`](docs/DATA_MODEL.md)

## Tech choices

| Tool | Why |
|---|---|
| **DuckDB** | Reads Parquet (including nested structs/arrays) and CSV directly, runs SQL fast on a laptop, no server to set up. The SQL is standard and ports easily to Snowflake/BigQuery/dbt. |
| **SQL** for all transformations | The brief's preferred tool. One model per file. |
| **Python** only as the runner | Orders the SQL, handles errors and transactions, runs tests, exports results. |

## Project structure

```
Task_1/
├── data/                          # input (not modified)
│   ├── 2025-05-01.parquet ... 2025-05-31.parquet
│   ├── dim_product.csv
│   └── dim_campaign.csv
├── sql/
│   ├── 01_staging/                # parse, type, flatten, de-duplicate, quarantine bad rows
│   ├── 02_dimensions/             # dim_date, dim_publisher, dim_article, dim_user,
│   │                              # dim_brand, dim_product, dim_campaign (SCD2)
│   ├── 03_facts/                  # fct_page_views, fct_mounts,
│   │                              # fct_product_impressions, fct_product_clicks
│   ├── 04_marts/                  # agg_daily_domain_funnel, agg_daily_product_performance
│   └── 05_analysis/               # q1..q5 - one file per question
├── tests/data_quality.sql         # 18 data-quality tests (error / warn)
├── run_pipeline.py                # runner
├── requirements.txt
├── output/                        # answer CSVs (generated)
├── warehouse/                     # trendii.duckdb (generated, git-ignored)
└── docs/
    ├── ANALYSIS.md                # answers + data-quality findings
    └── DATA_MODEL.md              # schema, grains, decisions
```

## Setup

Requires Python 3.9+.

```bash
python -m pip install -r requirements.txt
```

The raw event files are **not** in this repository (about 90 MB). Copy the
provided `2025-05-01.parquet` ... `2025-05-31.parquet` files into `data/`
(next to `dim_product.csv` and `dim_campaign.csv`) before running.

## Run

From the project folder:

```bash
python run_pipeline.py
```

This builds `warehouse/trendii.duckdb`, runs the tests and writes the answers
to `output/`. It takes about 1–2 minutes on a laptop.

Options:

```bash
python run_pipeline.py --data-dir path/to/data --db path/to/file.duckdb --output-dir path/to/output
python run_pipeline.py --skip-tests      # build without tests
python run_pipeline.py --temp-dir D:/tmp # where DuckDB may spill to disk
python run_pipeline.py -v                # verbose logging
```

Exit codes: `0` success, `1` a model or input failed, `2` an `error`-level test failed.

## Explore the results

```bash
duckdb warehouse/trendii.duckdb     # DuckDB CLI, or:
python -c "import duckdb; print(duckdb.connect('warehouse/trendii.duckdb').sql('SELECT * FROM agg_daily_domain_funnel LIMIT 10'))"
```

## Error handling & reliability

- **Input checks first:** missing folder, no Parquet files, missing CSVs or
  badly named partitions stop the run with a clear message.
- **Bad rows don't crash the load:** events with a missing id, page view id,
  unparseable timestamp or unknown event type go to `stg_events_rejected`
  with a `reject_reason`.
- **De-duplication:** by `eid` (events), `click_id` (clicks), page view
  (tagloads) and page view x image x product (impressions).
- **Explicit schemas** for CSVs, so type guessing cannot change between runs.
- **One transaction per model:** a failing model rolls back and the error
  names the file.
- **Idempotent:** every model is `CREATE OR REPLACE`; re-running gives the same result.
- **Data-quality tests** (`tests/data_quality.sql`): uniqueness, referential
  integrity across the funnel, SCD2 overlaps, campaign fan-out, unknown
  products. `error` tests fail the run; `warn` tests are logged.

## Scaling notes

- The staging layer reads all partitions with a glob; for daily production
  loads, the same SQL can be made incremental by filtering on `event_date` and
  inserting only new partitions (or by moving models to dbt incremental models).
- Facts are keyed and partition-friendly on `event_date`.
- No model depends on hard-coded dates (e.g. "final week" is derived from the data).

## Assumptions

See *Key modelling decisions* in [`docs/DATA_MODEL.md`](docs/DATA_MODEL.md). In short:
day = partition date; brand from `dim_product`; impressions de-duplicated;
campaign matched as of the event date; user = publisher + device id.
