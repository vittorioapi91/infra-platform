import os
from pathlib import Path
from feast import Entity, FeatureView, ValueType, FileSource
from datetime import timedelta

_default_macro_features_path = Path(__file__).resolve().parent / "data" / "macro_features.parquet"
_macro_features_path = Path(
    os.environ.get("FEAST_MACRO_FEATURES_PATH", str(_default_macro_features_path))
)

if not _macro_features_path.exists():
    raise FileNotFoundError(
        "Feast source parquet not found. Set FEAST_MACRO_FEATURES_PATH to a valid file "
        f"or create: {_default_macro_features_path}"
    )

# Entity: Date (time-based entity)
date_entity = Entity(
    name="date",
    value_type=ValueType.UNIX_TIMESTAMP,
    description="Date entity for time series features"
)

# Feature View: Macro Economic Indicators
macro_features_source = FileSource(
    path=str(_macro_features_path),
    timestamp_field="date",
    created_timestamp_column="created_at"
)

macro_feature_view = FeatureView(
    name="macro_indicators",
    entities=[date_entity],
    ttl=timedelta(days=365),
    source=macro_features_source,
    online=True,
    tags={
        "team": "macro_modeling",
        "domain": "economics"
    }
)

