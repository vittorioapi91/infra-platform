# MLflow Integration (infra-platform)

MLflow tracking helpers for model training jobs. The model-training Docker image
copies this folder to `/workspace/mlflow` and sets `IFP_MLFLOW_PATH`.

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
