# dbt (feature engineering for Feast)

[dbt](https://www.getdbt.com) runs in Docker alongside Feast. Models materialize **engineered feature tables** into the `feast` schema on each Postgres `datalake` database (dev/test/prod). Feast can consume those tables (e.g. via `PostgreSQLSource` or parquet export).

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
docker compose -f docker/docker-compose.infra-platform.yml up -d dbt-dev dbt-test dbt-prod
```

## Project layout

```
dbt/
├── profiles.yml              # DBT_PROFILES_DIR (dev/test/prod outputs)
├── requirements.txt
└── feast_features/           # dbt project (working_dir in container)
    ├── dbt_project.yml
    └── models/features/      # feature models → schema feast
```

## Usage (dev example)

```bash
docker exec -it dbt-dev bash
cd /workspace/dbt/feast_features   # already working_dir
dbt debug
dbt run
dbt test
```

From the host (same container):

```bash
docker exec -it dbt-dev dbt run --project-dir /workspace/dbt/feast_features
```

Models land in **`feast.*`** on `datalake`. Source data stays in schemas like `fred`, `edgar`, `postgres`, etc.

## Feast integration

1. Add dbt models under `feast_features/models/features/` (e.g. `macro_indicators.sql`).
2. Run `dbt run` in the matching env container.
3. Point Feast offline/ batch sources at the `feast` tables, or export to parquet under `feast/feast_repo/data/` for the current `FileSource` setup.

See `feast/README.md` for the Feast repo path and materialization commands.

## Environment

- `POSTGRES_PASSWORD` — same as other utilities (compose default `2014`).
- `DBT_TARGET` — set per container (`dev` / `test` / `prod`).
- `DBT_PROFILES_DIR` — `/workspace/dbt` in containers.
