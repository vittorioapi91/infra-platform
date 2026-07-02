# Release Notes v1.7.0

## Per-environment Feast and MLflow

### Main features

#### MLflow split by environment
- **Before:** Single `mlflow` container on port `55000` with `storage-infra/mlflow/data/`.
- **After:** `mlflow-dev`, `mlflow-test`, `mlflow-prod` — one tracking server per env.
- **Ports:** `55000` (dev), `55001` (test), `55002` (prod).
- **Gateway:** `mlflow.local.{dev,test,prod}.info` via `nginx-mlflow-{dev,test,prod}.conf` (replaces single `nginx-mlflow.conf`).
- **Storage:** `storage-infra/mlflow/{dev,test,prod}/data/` (SQLite backend + artifacts per env).
- **dbt integration:** Each `dbt-{env}` container sets `MLFLOW_TRACKING_URI=http://mlflow-{env}:5000`.

#### Feast split by environment
- **Before:** Single `feast` container and shared `feast/feast_repo/`.
- **After:** `feast-dev`, `feast-test`, `feast-prod` with isolated repos under `feast/repos/{dev,test,prod}/`.
- **Config:** Per-env `feature_store.yaml` and `definitions.py`; `FEAST_REPO_PATH` wired in compose and dbt sidecars.
- **Pipeline:** dbt → `feast` schema on `postgres-{env}` → parquet export → `feast apply` in matching env.

#### Kubernetes monitoring stack
- Per-env MLflow deployments (`mlflow-dev`, `mlflow-test`, `mlflow-prod`) in `kubernetes/monitoring-stack.yaml`.
- HMM training job and model-training image updated for env-scoped MLflow/Feast paths.

### Migration notes

1. **MLflow data:** If you had experiments under `storage-infra/mlflow/data/`, copy into the env you use (e.g. dev):
   ```bash
   cp -a storage-infra/mlflow/data/. storage-infra/mlflow/dev/data/
   ```
2. **Feast:** Use `feast/repos/{env}/` instead of `feast/feast_repo/` (`feast_repo/` kept as legacy, deprecated).
3. **Hosts:** Add to `/etc/hosts`:
   ```
   127.0.0.1 mlflow.local.dev.info mlflow.local.test.info mlflow.local.prod.info
   ```
4. **Restart:** `docker compose -f docker/docker-compose.infra-platform.yml up -d mlflow-dev mlflow-test mlflow-prod feast-dev feast-test feast-prod nginx-proxy`

### Breaking changes

- Removed single `mlflow` and `feast` compose services; update scripts/automation to use `mlflow-{env}` / `feast-{env}`.
- Removed `gateway/nginx/nginx-mlflow.conf`; use per-env nginx configs.
- `MLFLOW_TRACKING_URI` must target the matching env server (dbt/Airflow/training jobs).

### Files added / changed (high level)

- `docker/docker-compose.infra-platform.yml` — per-env MLflow and Feast services
- `feast/repos/{dev,test,prod}/` — isolated Feast repos
- `gateway/nginx/nginx-mlflow-{dev,test,prod}.conf`, `gateway/nginx/redirects.md`
- `mlflow/README.md`, `feast/README.md`, `storage-infra/README.md`
- `dbt/` — env-scoped `FEAST_REPO_PATH` and `MLFLOW_TRACKING_URI`
- `kubernetes/monitoring-stack.yaml`, `kubernetes/hmm-model-training-job.yaml`
- `start-all-services.sh`, `stop-all-services.sh`, `prometheus/prometheus.yml`

---

**Tag:** v1.7.0  
**Date:** 2026-07-02  
**Branch:** main
