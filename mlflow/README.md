# MLflow Integration (infra-platform)

Per-environment MLflow tracking servers — same pattern as `postgres-dev` / `feast-dev` / `dbt-dev`.

## Servers

| Env | Container | Host port | Nginx hostname | Storage |
|-----|-----------|-----------|----------------|---------|
| dev | `mlflow-dev` | 55000 | `mlflow.local.dev.info` | `storage-infra/mlflow/dev/data` |
| test | `mlflow-test` | 55001 | `mlflow.local.test.info` | `storage-infra/mlflow/test/data` |
| prod | `mlflow-prod` | 55002 | `mlflow.local.prod.info` | `storage-infra/mlflow/prod/data` |

Each server has its own SQLite backend (`mlflow.db`) and artifact directory.

## `/etc/hosts`

```
127.0.0.1 mlflow.local.dev.info mlflow.local.test.info mlflow.local.prod.info
```

## Training (trading_agent wheel)

`trading_agent._mlflow_.paths.resolve_mlflow_tracking_uri()` picks the URI from:

1. `MLFLOW_TRACKING_URI` if set
2. Inside Docker: `http://mlflow-{env}:5000`
3. On host: `http://localhost:55000` (dev), `55001` (test), `55002` (prod)

`dbt-{env}` sidecars set `MLFLOW_TRACKING_URI` automatically.

```bash
ENV=dev python -m trading_agent.macro.main --feature-method hp_cycle --series-ids GDP CPIAUCSL FEDFUNDS
# → http://localhost:55000

docker exec -e ENV=test dbt-test python -m trading_agent.macro.main ...
# → http://mlflow-test:5000
```

## Implementation

`mlflow_tracking.py` re-exports `MLflowTracker` from `trading_agent._mlflow_` (wheel). Install via `mlflow/install-trading-agent.sh` or `dbt/install-trading-agent.sh`.

## Start

```bash
docker compose -f docker/docker-compose.infra-platform.yml up -d mlflow-dev mlflow-test mlflow-prod
```

Legacy single `mlflow` container and `storage-infra/mlflow/data/` are deprecated.
