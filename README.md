# Group 4: Clarity Analytics Center — Final Project Prototype

**DSIO 2010 — Implementation Path A (Working Prototype)**
Contributors: Hillary Ssemakula, Sonali Manohar, Crystal Lopez-Franco

## Overview

The Clarity Analytics Center (CAC) is a nonprofit focused on government accountability, immigration policy transparency, and public spending oversight. This prototype builds a unified data pipeline linking ICE enforcement, staffing, and Treasury funding data — currently fragmented across federal sources — into a single medallion-architecture database to support oversight-style reporting.

Full context on the problem statement and goals is in Group4_Proposal.pdf (not included in this repo).

## Repository Structure

```
Group_4_Clarity_Analytics_Center/
├── notebooks/
│   ├── 01_storage.ipynb       # creates the SQLite DB and Bronze/Silver/Gold schema
│   ├── 02_ingestion.ipynb     # pulls raw data into the Bronze landing zone
│   └── 03_processing.ipynb    # transforms Bronze -> Silver -> Gold (star schema)
├── data/
│   ├── clarity_analytics_center.db   # SQLite database (Bronze/Silver/Gold)
│   └── [ICE ERO Statistics PDFs]     # source PDFs used during ingestion
├── requirements.txt
└── README.md
```

## Architecture

Data moves through a **medallion architecture**:

- **Bronze** — raw, source-native data, no transformations. Tables: `bronze_ice_operations`, `bronze_ice_budget`, `bronze_treasury_reconciliation`, `bronze_ice_enforcement_pdfs`, `bronze_ice_enforcement_metrics`.
- **Silver** — cleaned and standardized. Tables: `silver_operations`, `silver_budget`, `silver_treasury_reconciliation`, `silver_enforcement`.
- **Gold** — star schema for analysis. Dimensions: `gold_dim_date`, `gold_dim_org_unit`, `gold_dim_role`, `gold_dim_facility`, `gold_dim_treasury_line`. Facts: `gold_fact_budget`, `gold_fact_treasury`, `gold_fact_enforcement`, `gold_fact_assignment`.

`01_storage.ipynb` creates this full schema before any data is loaded.

## Data Sources

This pipeline ingests four sources into Bronze:

1. **Treasury Fiscal Data API** — pulled from `https://api.fiscaldata.treasury.gov`, multiple accounting/reconciliation endpoints, with pagination. Landed as timestamped JSON.
   - *APA:* U.S. Department of Treasury. (n.d.). U.S. government financial report: Reconciliations of net operating cost and budget deficit. [Data set]. Fiscal Data. Retrieved August 12, 2026, from https://fiscaldata.treasury.gov/datasets/u-s-government-financial-report/reconciliations-of-net-operating-cost-and-budget-deficit#reports-and-files 

2. **Synthetic ICE operations dataset** — generated staffing/assignment data (agent, region, role, department, facility) since real ICE staffing data isn't publicly available. Saved as `ice_operations.csv` before landing.

3. **ICE ERO Statistics PDFs (5 files)** — downloaded via `gdown` from shared Google Drive links, extracted with `pdfplumber`. **Note:** these five PDFs were originally published for FY2016–FY2020. To align with our Treasury data's date range, they have been relabeled FY2020–FY2024 in this pipeline (see mapping below). This is a disclosed synthetic-alignment decision, not a claim that these are newly published reports.

   | Filename in `data/` | Labeled fiscal year | Original publication year |
   |---|---|---|
   | FY_2020_ICE_ERO_Report.pdf | 2020 | 2016 |
   | FY_2021_ICE_ERO_Report.pdf | 2021 | 2017 |
   | FY_2022_ICE_ERO_Report.pdf | 2022 | 2018 |
   | FY_2023_ICE_ERO_Report.pdf | 2023 | 2019 |
   | FY_2024_ICE_ERO_Report.pdf | 2024 | 2020 |

   - *APA:* U.S. Immigration and Customs Enforcement. (2026, July 24). Enforcement and Removal Operations statistics. U.S. Department of Homeland Security. https://www.ice.gov/statistics



4. **Enforcement metrics CSV** — a supplementary structured extract (`ero_enforcement_metrics_claude_extract.csv`) pulled via `gdown`, feeding `bronze_ice_enforcement_metrics`, later joined with the PDF-extracted table in Silver.

All raw ingestion output additionally lands as timestamped JSON in `data/landing_zone/` for lineage and reproducibility, before being loaded into Bronze tables.

## How to Reproduce

**1. Clone the repository** and make sure your working directory is the repo root when running notebooks (all data paths are relative to the repo root, e.g. `data/clarity_analytics_center.db`).

**2. Install dependencies:**
```bash
pip install -r requirements.txt
```

**3. Run notebooks in order:**
1. `notebooks/01_storage.ipynb` — creates `data/clarity_analytics_center.db` and the full schema
2. `notebooks/02_ingestion.ipynb` — ingests all four sources into Bronze
3. `notebooks/03_processing.ipynb` — transforms Bronze into Silver and Gold

**4. Verify:** query `data/clarity_analytics_center.db` directly, or check `data/landing_zone/` for the raw timestamped JSON.

> **A note on environment:** this pipeline was originally developed in Google Colab against a team Shared Drive. Paths have been updated to work against the local `data/` folder in this repository instead, so it can run outside Colab without Drive access. A `USE_DRIVE` flag remains in each notebook if you need to run it against the original shared Drive location instead.

## Known Limitations / Future Work

- The reporting and dashboard layer described in the original proposal is not yet built — the prototype currently stops at a queryable Gold layer.
- FY2016–2020 ERO source data is relabeled (not newly collected) to align with the Treasury date range; a production version would source real historical or current-year ICE data directly.
- Available enforcement data is aggregated which limits the amount questions that can be answered by the gold layer. Future work would involve obtaining row level enforcement data that would enable development of robust metric dashboards.

## Contributors

- **Crystal Lopez-Franco** — data ingestion (02_ingestion.ipynb: Bronze landing zone, source integration)
- **Sonali Manohar** — storage (01_storage.ipynb: schema setup, Gold star schema design)
- **Hillary Ssemakula** — processing (03_processing.ipynb: Silver/Gold transformation)
