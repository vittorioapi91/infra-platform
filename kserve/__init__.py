"""KServe deployment shim."""

from trading_agent._kserve_.deployment import KServeDeployment, apply_inference_service

__all__ = ["KServeDeployment", "apply_inference_service"]
