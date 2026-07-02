# KServe Deployment

Serves **macro-cycle-hmm** from the MLflow Model Registry (PyFunc wrapper in `trading_agent._mlflow_`).

## Files

| File | Role |
|------|------|
| `kserve-inference-service.yaml` | Dev-oriented manifest (`MLFLOW_TRACKING_URI` → host `:55000`) |
| `kserve_deployment.py` | Shim → `trading_agent._kserve_.deployment` |

## Apply manifest

```bash
kubectl apply -f kserve/kserve-inference-service.yaml
```

Promote the model to **Production** in MLflow before pointing `storageUri` at `models:/macro-cycle-hmm/Production`.

## Python API

```python
from trading_agent._kserve_.deployment import KServeDeployment

deployment = KServeDeployment(namespace="default")
deployment.apply_inference_service(env="dev", model_stage="Staging")
```

Or from a Kubeflow pipeline step (`skip_kserve=False`).

## Per-environment MLflow URIs (kind → Compose)

| env | `MLFLOW_TRACKING_URI` on predictor |
|-----|-------------------------------------|
| dev | `http://host.docker.internal:55000` |
| test | `http://host.docker.internal:55001` |
| prod | `http://host.docker.internal:55002` |

## Requirements

- KServe installed in kind (`kubernetes/QUICK_START.md`)
- Model registered in MLflow (`macro-cycle-hmm`)
- Compose MLflow servers running with artifact store accessible from kind pods
