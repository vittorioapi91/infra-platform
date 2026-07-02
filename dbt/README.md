# dbt (feature engineering for Feast)

[dbt](https://www.getdbt.com) materializes **engineered feature tables** into the `feast` schema on each Postgres `datalake` database (dev/test/prod). Feast consumes the exported parquet for local archiving; MLflow logs lineage on HMM training runs.

**Python feature pipelines** (`trading_agent._dbt_`, `trading_agent._feast_`) live in **TradingPythonAgent** and are installed into dbt sidecars at startup via `install-trading-agent.sh` (same wheel/source pattern as Airflow `_airflow_dags_`).

## Pipeline overview

```
fred.time_series + fred.series (idp macro downloader)
    → dbt staging/intermediate (SQL views)
    → python -m trading_agent.features.macro.hodrick_prescott
    → feast.macro_hp_decomposition + feast.feature_transform_lineage
    → python -m trading_agent.features.macro.hp_feast_export
    → feast apply (feast-{env})
    → dbt feature views + tests
    → HMM training (--feature-method hp_cycle) logs lineage to MLflow
```

## Containers

| Env | Container | Postgres | DB target |
|-----|-----------|----------|-----------|
| dev | `dbt-dev` | `postgres-dev` | `dev` |
| test | `dbt-test` | `postgres-test` | `test` |
| prod | `dbt-prod` | `postgres-prod` | `prod` |

Start with the rest of the stack:

```bash
./start-all-services.sh
# or
docker compose -f docker/docker-compose.infra-platform.yml up -d dbt-dev feast-dev
```

## dbt docs (lineage + catalog)

Each `dbt-{env}` sidecar serves generated docs on port **8880** (host-mapped **8880/8881/8882**).

| Env | nginx | Direct |
|-----|-------|--------|
| dev | http://dbt.local.dev.info | http://localhost:8880 |
| test | http://dbt.local.test.info | http://localhost:8881 |
| prod | http://dbt.local.prod.info | http://localhost:8882 |

Docs regenerate on container start and when `dbt docs serve` restarts. Add hostnames via `gateway/nginx/redirects.md`.

dbt `target/` and `logs/` are bind-mounted from `storage-infra/dbt/{env}/target` and `storage-infra/dbt/{env}/logs` (not stored in the image).

## Project layout

```
dbt/
├── install-trading-agent.sh         # pip install trading_agent (wheel or mounted source)
├── profiles.yml
├── requirements.txt
├── scripts/
│   ├── materialize_hp_features.py   # thin CLI → trading_agent._feast_.features.hodrick_prescott
│   ├── export_feast_parquet.py
│   └── provision-feast-schema.sql
└── feast_features/
    └── models/ ...

TradingPythonAgent/src/
├── _dbt_/                           # config, connection, FRED catalog
└── _feast_/                         # materialize_feature, lineage, feature transforms
```

## Usage (dev example)

```bash
docker exec -it dbt-dev bash
export DBT_TARGET=dev FEATURE_CODE_VERSION=1.1.0

dbt run --project-dir /workspace/dbt/feast_features --select staging intermediate
python -m trading_agent._feast_.features.hodrick_prescott
python -m trading_agent._feast_.features.hp_feast_export
dbt run --project-dir /workspace/dbt/feast_features --select features
dbt test --project-dir /workspace/dbt/feast_features --select features
```

From Kubeflow `macro_ml_pipeline` (or manual steps in `dbt-{env}`):

## Lineage columns (registered in dbt / Postgres)

**`feast.macro_hp_decomposition`** (per series, per date):

| Column | Description |
|--------|-------------|
| `observation_date` | FRED observation date |
| `series_id` | FRED series code |
| `value` | Raw level |
| `cycle` / `trend` | HP components |
| `hp_lambda` | Smoothing parameter (from `fred.series.frequency`) |
| `feature_code_version` | dbt project var (currently `1.1.0`) |
| `git_sha` | Git commit at materialization |
| `materialized_at` | UTC timestamp |
| `transform_name` | `hodrick_prescott` |
| `statsmodels_version` | Library version |

**`feast.feature_transform_lineage`** (per pipeline run):

| Column | Description |
|--------|-------------|
| `run_id` | UUID |
| `series_count` / `row_count` | Coverage stats |
| `feast_feature_view` | `macro_hp_cycle` |
| `mlflow_experiment` | `macro-cycle-hmm` |

## Feast + MLflow

- Parquet: `feast/repos/{env}/data/macro_hp_cycle.parquet`
- Feature view: `macro_hp_cycle` in `feast/repos/{env}/definitions.py`
- Training: `python -m trading_agent.macro.main --feature-method hp_cycle --series-ids GDP CPIAUCSL FEDFUNDS`
- MLflow tags: `feast_feature_view`, `feature_code_version`, `feature_git_sha`, etc.

See `feast/README.md` and `mlflow/README.md`.

## Environment

- `POSTGRES_*` / `ENV` — canonical `postgres_connection` (mounted from idp; mirrored in TPA wheel)
- `DBT_TARGET` — used by `get_datalake_env()` when `ENV` is unset (dbt sidecars)
- `DBT_PROFILES_DIR` — `/workspace/dbt` in containers (dbt CLI only)
- `FEATURE_CODE_VERSION` — defaults to dbt var `1.1.0`
- `GIT_SHA` — optional override for lineage
