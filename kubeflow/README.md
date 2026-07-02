# Kubeflow Pipelines

Macro ML workflow orchestration: **dbt → HP features → Feast → train → optional KServe**.

Pipeline definition lives in the **trading_agent wheel** (`trading_agent._kubeflow_`). IFP supplies the pipeline-runner image, compile/submit scripts, and Kubeflow install docs.

## Layout

| Path | Role |
|------|------|
| `kubeflow/install-trading-agent.sh` | Install wheel (same pattern as `dbt/install-trading-agent.sh`) |
| `kubeflow/compile-pipeline.sh` | Compile `macro_ml_pipeline.yaml` from the wheel |
| `kubernetes/Dockerfile.pipeline-runner` | Image for all pipeline steps |
| `kubernetes/build-pipeline-image.sh` | Build image + stage wheels |
| `kubernetes/deploy-pipeline-image-to-kind.sh` | `kind load` for `tpa-pipeline-runner:latest` |

## Prerequisites

1. Docker Compose stack running (Postgres, MLflow, Feast repos on host ports).
2. kind cluster with Kubeflow Pipelines (`kubernetes/QUICK_START.md`).
3. Pipeline runtime data dirs: `bash kubernetes/provision-pipeline-runtime-data.sh`
4. Built pipeline image loaded into kind.

**Image vs data:** `tpa-pipeline-runner` contains dbt/Feast **project code** only. Feast registry/parquet and dbt `target/` live under `storage-infra/feast/` and `storage-infra/dbt/`, mounted into Compose sidecars and Kubeflow pipeline pods (PVC `ifp-feast-runtime-data`, `ifp-dbt-runtime-data`).

```bash
# From infra-platform/
bash kubernetes/build-pipeline-image.sh dev
bash kubernetes/deploy-pipeline-image-to-kind.sh
kubectl port-forward -n kubeflow svc/ml-pipeline-ui 8088:80
```

## Compile pipeline

```bash
bash kubeflow/compile-pipeline.sh
# → kubeflow/macro_ml_pipeline.yaml
```

## Submit a run

```python
from kfp import Client

client = Client(host="http://localhost:8088")
client.create_run_from_pipeline_package(
    "kubeflow/macro_ml_pipeline.yaml",
    arguments={
        "env": "dev",
        "series_ids": ["GDP", "CPIAUCSL", "FEDFUNDS"],
        "skip_kserve": True,
    },
)
```

Or via UI at http://kubeflow.local.info (nginx → port-forward 8088).

## Pipeline steps

1. `dbt_run_staging` — staging/intermediate SQL
2. `materialize_hp` — Hodrick-Prescott → `feast.macro_hp_decomposition`
3. `export_feast_parquet` — wide parquet for Feast offline store
4. `feast_apply` — apply feature definitions
5. `dbt_run_features` / `dbt_test` — feature views + tests
6. `train` — HMM training → MLflow (`hp_cycle` features)
7. `deploy_kserve` (optional) — MLflow PyFunc → KServe

## Recurring runs

Use Kubeflow **Recurring runs** with a cron schedule (e.g. `0 4 * * *`) to replace the former Airflow feature DAG.

## Environment

| Param `env` | Postgres (host) | MLflow (host) |
|-------------|-----------------|---------------|
| `dev` | `:54324` | `:55000` |
| `test` | `:54325` | `:55001` |
| `prod` | `:54326` | `:55002` |

kind pods reach Compose via `host.docker.internal` (override with `K8S_HOST_GATEWAY`).
