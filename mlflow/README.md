# MLflow Integration (infra-platform)

MLflow tracking helpers for model training jobs. The model-training Docker image
copies this folder to `/workspace/mlflow` and sets `IFP_MLFLOW_PATH`.

## Artifact storage (outside the image)

Run artifacts and the tracking DB must **not** live inside container images.

| Environment | Host path | Container mount |
|-------------|-----------|-----------------|
| Docker Compose | `storage-infra/mlflow/data/` | `/mlflow` |
| Kubernetes (kind) | `/var/lib/trading/mlflow` on the node | `/mlflow` |

The MLflow server is started with:

```bash
mlflow server \
  --backend-store-uri sqlite:////mlflow/mlflow.db \
  --artifacts-destination /mlflow/artifacts \
  --serve-artifacts
```

Use `--artifacts-destination` (not `--default-artifact-root`) so new experiments get
`mlflow-artifacts:/…` URIs and clients upload over HTTP. With `--default-artifact-root`
set to a filesystem path, the local debugger tries to write `/mlflow` on the Mac and fails.

For kind, map the host repo path into nodes if you want the same folder as Docker Compose:

```yaml
# kind cluster config excerpt
extraMounts:
  - hostPath: /path/to/infra-platform/storage-infra/mlflow/data
    containerPath: /var/lib/trading/mlflow
```

## Usage (inside training_agent)

```python
from src.mlflow import get_mlflow_tracker_class

MLflowTracker = get_mlflow_tracker_class()
tracker = MLflowTracker(
    tracking_uri="http://mlflow:5000",
    experiment_name="macro-cycle-hmm",
)
run_id = tracker.log_hmm_experiment(
    model=model,
    params={"n_regimes": 4},
    metrics={"log_likelihood": -100.5},
)
```

## Configuration

```bash
export MLFLOW_TRACKING_URI=http://mlflow.local.info:55000
export IFP_MLFLOW_PATH=/workspace/mlflow
```

Local debugger (training on Mac, MLflow in Docker):

```bash
export MLFLOW_TRACKING_URI=http://localhost:55000
export IFP_MLFLOW_PATH=/path/to/infra-platform/mlflow
```

After changing the server command, recreate the container:

```bash
cd infra-platform/docker
docker compose -f docker-compose.infra-platform.yml up -d mlflow
```
