"""
MLflow integration for experiment tracking and model registry.

Implementation lives in the trading_agent wheel (trading_agent._mlflow_).
This module re-exports it for IFP mounts and legacy PYTHONPATH usage.
"""

try:
    from trading_agent._mlflow_.tracking import MACRO_HMM_MODEL_NAME, MLflowTracker
except ImportError as exc:
    raise ImportError(
        "Install trading_agent wheel before using mlflow_tracking "
        "(see dbt/install-trading-agent.sh or kubernetes/install-model-wheels.sh)."
    ) from exc

__all__ = ["MACRO_HMM_MODEL_NAME", "MLflowTracker"]
