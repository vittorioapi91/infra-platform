# Feast Feature Store (per environment)

Each Airflow / dbt environment uses its **own** Feast repo — same pattern as `dbt-dev` / `postgres-dev`.

## Layout

```
feast/
├── repos/
│   ├── dev/          # feast-dev container
│   │   ├── feature_store.yaml
│   │   ├── definitions.py
│   │   └── data/     # runtime: bind-mounted from storage-infra/feast/{env}/data
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

Runtime data (registry, parquet, online store) lives on the host at `storage-infra/feast/{env}/data/` and is bind-mounted into each sidecar. Project code stays in `feast/repos/`.

Start with dbt sidecars:

```bash
docker compose -f docker/docker-compose.infra-platform.yml up -d dbt-dev feast-dev
```

## Feast UI

Each `feast-{env}` container runs `feast ui` on port **8888** (host-mapped **8890/8891/8892**).

| Env | nginx | Direct |
|-----|-------|--------|
| dev | http://feast.local.dev.info | http://localhost:8890 |
| test | http://feast.local.test.info | http://localhost:8891 |
| prod | http://feast.local.prod.info | http://localhost:8892 |

Add hostnames via `gateway/nginx/redirects.md`.

## Pipeline (per env)

From `dbt-{env}` (or Kubeflow `macro_ml_pipeline`):

1. HP materialize → `feast.macro_hp_decomposition` on that env's Postgres
2. `python -m trading_agent.features.macro.hp_feast_export` → `repos/{env}/data/macro_hp_cycle.parquet`
3. `feast apply` in `feast-{env}`

`FEAST_REPO_PATH` and `ENV` are set automatically in dbt sidecars and Airflow docker exec commands.

## Training

HMM training with `--feature-method hp_cycle` resolves parquet via `trading_agent._feast_.paths.resolve_hp_cycle_parquet_path()` using `ENV` / `DBT_TARGET`.
