"""
MLflow integration for experiment tracking and model registry
"""

from typing import Any, Dict, Optional
import logging
import os
import pickle
import tempfile

from mlflow.tracking import MlflowClient, set_tracking_uri
from mlflow.tracking.fluent import (
    get_artifact_uri,
    log_artifact,
    log_metrics,
    log_params,
    set_experiment,
    set_tag,
    start_run,
)
from mlflow.tracking._model_registry.fluent import register_model as register_mlflow_model

logger = logging.getLogger(__name__)


class MLflowTracker:
    """
    MLflow tracker for HMM model experiments
    """
    
    def __init__(self, tracking_uri: Optional[str] = None,
                 experiment_name: str = 'macro-cycle-hmm'):
        """
        Initialize MLflow tracker
        
        Args:
            tracking_uri: MLflow tracking URI (default: from env or local)
            experiment_name: Name of MLflow experiment
        """
        self.tracking_uri = tracking_uri or os.getenv(
            'MLFLOW_TRACKING_URI',
            'http://localhost:5000'
        )
        self.experiment_name = experiment_name
        
        set_tracking_uri(self.tracking_uri)
        set_experiment(experiment_name)
        
        logger.info(f"MLflow tracking initialized: {self.tracking_uri}")
        logger.info(f"Experiment: {experiment_name}")

    @staticmethod
    def _set_run_tags(tags: Dict[str, str]) -> None:
        for key, value in tags.items():
            if value:
                set_tag(key, str(value))
    
    def log_hmm_experiment(self,
                          model: Any,
                          params: Dict[str, Any],
                          metrics: Dict[str, float],
                          artifacts: Optional[Dict[str, str]] = None,
                          tags: Optional[Dict[str, str]] = None,
                          feature_lineage: Optional[Dict[str, Any]] = None) -> str:
        """
        Log HMM model experiment to MLflow
        
        Args:
            model: Trained HMM model
            params: Model parameters
            metrics: Model metrics
            artifacts: Optional artifacts to log (dict of name: path)
            tags: Optional tags for the run
            
        Returns:
            Run ID
        """
        logged_run_id: str | None = None
        with start_run() as run:
            # Log parameters
            log_params(params)
            
            # Log metrics
            log_metrics(metrics)
            
            # Log tags
            if tags:
                self._set_run_tags(tags)

            if feature_lineage:
                self.log_feast_feature_lineage(feature_lineage)
            
            # Log model artifact (Pyro HMM is not a sklearn estimator)
            with tempfile.NamedTemporaryFile(suffix=".pkl", delete=False) as handle:
                pickle.dump(model, handle)
                artifact_path = handle.name
            log_artifact(artifact_path, artifact_path="model")
            os.unlink(artifact_path)
            
            # Log artifacts
            if artifacts:
                for name, path in artifacts.items():
                    log_artifact(path, name)
            
            logged_run_id = run.info.run_id
            model_uri = get_artifact_uri('model')
            
            logger.info(f"Experiment logged. Run ID: {logged_run_id}")
            logger.info(f"Model URI: {model_uri}")

        if logged_run_id is None:
            raise RuntimeError("MLflow run ended without a run_id")
        return logged_run_id

    def log_feast_feature_lineage(self, lineage: Dict[str, Any]) -> None:
        """
        Log Feast / dbt feature lineage to the active MLflow run.

        Expected keys: feature_view, transform_name, feature_code_version,
        materialized_at, git_sha, feast_source_path (optional), row_count, series_count.
        """
        tags = {
            "feast_feature_view": str(lineage.get("feast_feature_view", "macro_hp_cycle")),
            "feature_transform": str(lineage.get("transform_name", "hodrick_prescott")),
            "feature_code_version": str(lineage.get("feature_code_version", "")),
            "feature_materialized_at": str(lineage.get("materialized_at", "")),
            "feast_source": str(lineage.get("feast_source_path", "")),
        }
        git_sha = lineage.get("git_sha")
        if git_sha:
            tags["feature_git_sha"] = str(git_sha)
        self._set_run_tags(tags)

        params = {}
        for key in ("row_count", "series_count", "hp_lambda", "dbt_target"):
            if key in lineage and lineage[key] is not None:
                params[f"feature_{key}"] = lineage[key]
        if params:
            log_params(params)

        source_path = lineage.get("feast_source_path")
        if source_path and os.path.isfile(source_path):
            log_artifact(source_path, artifact_path="feast")
    
    def register_model(self, run_id: str, model_name: str = 'macro-cycle-hmm',
                      stage: str = 'Production') -> str:
        """
        Register model in MLflow model registry
        
        Args:
            run_id: MLflow run ID
            model_name: Model name in registry
            stage: Model stage (Staging, Production, Archived)
            
        Returns:
            Model version
        """
        model_uri = f"runs:/{run_id}/model"
        
        model_version = register_mlflow_model(
            model_uri,
            model_name
        )
        
        # Transition to stage
        client = MlflowClient()
        client.transition_model_version_stage(
            name=model_name,
            version=model_version.version,
            stage=stage
        )
        
        logger.info(f"Model registered: {model_name} v{model_version.version} -> {stage}")
        
        return model_version.version
    
    def load_model(self, model_name: str, version: Optional[int] = None,
                  stage: Optional[str] = None) -> Any:
        """
        Load model from MLflow registry
        
        Args:
            model_name: Model name
            version: Model version (optional)
            stage: Model stage (optional)
            
        Returns:
            Loaded model
        """
        if stage:
            model_uri = f"models:/{model_name}/{stage}"
        elif version:
            model_uri = f"models:/{model_name}/{version}"
        else:
            model_uri = f"models:/{model_name}/latest"
        
        raise NotImplementedError(
            "HMM models are logged as pickle artifacts; load via mlflow.artifacts.download_artifacts"
        )
