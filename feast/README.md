# Feast Feature Store (per environment)

Each Airflow / dbt environment uses its **own** Feast repo — same pattern as `dbt-dev` / `postgres-dev`.

## Layout

```
feast/
├── repos/
│   ├── dev/          # feast-dev container
│   │   ├── feature_store.yaml
│   │   ├── definitions.py
│   │   └── data/     # macro_hp_cycle.parquet, registry.db, online_store.db
│   ├── test/         # feast-test
│   └── prod/         # feast-prod
└── feast_repo/       # legacy single-env repo (deprecated)
```

## Containers

| Env | Container | Repo path | Postgres features |
|-----|-----------|-----------|-------------------|
| dev | `feast-dev` | `/workspace/feast/repos/dev` | `postgres-dev` / `feast.*` |
| test | `feast-test` | `/workspace/feast/repos/test` | `postgres-test` |
| prod | `feast-prod` | `/workspace/feast/repos/prod` | `postgres-prod` |

Start with dbt sidecars:

```bash
docker compose -f docker/docker-compose.infra-platform.yml up -d dbt-dev feast-dev
```

## Pipeline (per env)

From `dbt-{env}` (or Airflow `dbt_feast_features_{env}`):

1. HP materialize → `feast.macro_hp_decomposition` on that env's Postgres
2. `python -m trading_agent.features.macro.hp_feast_export` → `repos/{env}/data/macro_hp_cycle.parquet`
3. `feast apply` in `feast-{env}`

`FEAST_REPO_PATH` and `ENV` are set automatically in dbt sidecars and Airflow docker exec commands.

## Training

HMM training with `--feature-method hp_cycle` resolves parquet via `trading_agent._feast_.paths.resolve_hp_cycle_parquet_path()` using `ENV` / `DBT_TARGET`.
