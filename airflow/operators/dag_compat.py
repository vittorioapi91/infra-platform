"""Airflow 2/3 compatible imports and scheduling helpers."""

from __future__ import annotations

from datetime import datetime
from typing import Any

import pendulum

try:
    from airflow.providers.standard.operators.python import PythonOperator
except ImportError:
    from airflow.operators.python import PythonOperator  # type: ignore[no-redef]

try:
    from airflow.sdk import TaskGroup
except ImportError:
    from airflow.utils.task_group import TaskGroup  # type: ignore[no-redef]


def default_start_date() -> datetime:
    return pendulum.today('UTC').add(days=-1)


def resolve_logical_date(context: dict[str, Any]) -> datetime:
    """Resolve schedule anchor from Airflow 3 logical_date or legacy execution_date."""
    dag_run = context.get('dag_run')
    candidates = [
        context.get('logical_date'),
        context.get('data_interval_start'),
        context.get('execution_date'),
    ]
    if dag_run is not None:
        candidates.extend(
            [
                getattr(dag_run, 'logical_date', None),
                getattr(dag_run, 'data_interval_start', None),
                getattr(dag_run, 'execution_date', None),
            ]
        )

    for value in candidates:
        if value is None:
            continue
        if isinstance(value, str):
            return datetime.fromisoformat(value.replace('Z', '+00:00'))
        return value

    raise KeyError('No logical_date, data_interval_start, or execution_date in task context')
