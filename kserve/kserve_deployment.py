"""
KServe deployment shim — implementation in trading_agent._kserve_.deployment.
"""

from trading_agent._kserve_.deployment import (
    KServeDeployment,
    apply_inference_service,
    build_inference_service_body,
)

__all__ = ["KServeDeployment", "apply_inference_service", "build_inference_service_body"]
