import os
from pathlib import Path
from datetime import timedelta

from feast import Entity, FeatureView, ValueType, FileSource

_repo_dir = Path(__file__).resolve().parent
_default_hp_cycle_path = _repo_dir / "data" / "macro_hp_cycle.parquet"
_hp_cycle_path = Path(
    os.environ.get("FEAST_MACRO_HP_CYCLE_PATH", str(_default_hp_cycle_path))
)

# Legacy wide parquet (optional); HP cycle features preferred when present.
_default_macro_features_path = _repo_dir / "data" / "macro_features.parquet"
_macro_features_path = Path(
    os.environ.get("FEAST_MACRO_FEATURES_PATH", str(_default_macro_features_path))
)

date_entity = Entity(
    name="date",
    value_type=ValueType.UNIX_TIMESTAMP,
    description="Calendar date for macro feature rows",
)

feature_views: list[FeatureView] = []

if _hp_cycle_path.exists():
    macro_hp_cycle_source = FileSource(
        path=str(_hp_cycle_path),
        timestamp_field="date",
        created_timestamp_column="created_at",
    )
    macro_hp_cycle_view = FeatureView(
        name="macro_hp_cycle",
        entities=[date_entity],
        ttl=timedelta(days=3650),
        source=macro_hp_cycle_source,
        online=True,
        tags={
            "team": "macro_modeling",
            "domain": "economics",
            "transform": "hodrick_prescott",
            "mlflow_experiment": "macro-cycle-hmm",
            "dbt_project": "feast_features",
        },
    )
    feature_views.append(macro_hp_cycle_view)

if _macro_features_path.exists():
    macro_features_source = FileSource(
        path=str(_macro_features_path),
        timestamp_field="date",
        created_timestamp_column="created_at",
    )
    macro_feature_view = FeatureView(
        name="macro_indicators",
        entities=[date_entity],
        ttl=timedelta(days=365),
        source=macro_features_source,
        online=True,
        tags={
            "team": "macro_modeling",
            "domain": "economics",
        },
    )
    feature_views.append(macro_feature_view)

if not feature_views:
    raise FileNotFoundError(
        "No Feast source parquet found. Run the dbt HP pipeline and export step, "
        f"or set FEAST_MACRO_HP_CYCLE_PATH / FEAST_MACRO_FEATURES_PATH. "
        f"Expected: {_hp_cycle_path} or {_macro_features_path}"
    )

# Primary view for MLflow / HMM training (HP cycle when available).
macro_feature_view = feature_views[0]
