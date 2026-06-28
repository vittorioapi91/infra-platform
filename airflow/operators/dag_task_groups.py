"""TaskGroup styling by package owner (idp vs tpa).

Mounted on PYTHONPATH at /opt/airflow/operators for tradingpythonagent DAGs.
idp DAGs ship an identical copy in idp/_airflow_dags_/dag_task_groups.py.
"""

from __future__ import annotations

try:
    from dag_compat import TaskGroup
except ImportError:
    from airflow.utils.task_group import TaskGroup  # type: ignore[no-redef]

IDP_TASK_GROUP_ID = 'idp'
TPA_TASK_GROUP_ID = 'tpa'

# Red — infra-data-pipelines
IDP_UI_COLOR = '#e74c3c'
IDP_UI_FG_COLOR = '#ffffff'

# Blue — tradingpythonagent
TPA_UI_COLOR = '#3498db'
TPA_UI_FG_COLOR = '#ffffff'


def create_idp_task_group(dag, group_id: str = IDP_TASK_GROUP_ID) -> TaskGroup:
    """Wrap idp-owned tasks in a red TaskGroup in the Airflow graph."""
    return TaskGroup(
        group_id=group_id,
        dag=dag,
        ui_color=IDP_UI_COLOR,
        ui_fgcolor=IDP_UI_FG_COLOR,
        tooltip='infra-data-pipelines (idp)',
    )


def create_tpa_task_group(dag, group_id: str = TPA_TASK_GROUP_ID) -> TaskGroup:
    """Wrap tradingpythonagent tasks in a blue TaskGroup in the Airflow graph."""
    return TaskGroup(
        group_id=group_id,
        dag=dag,
        ui_color=TPA_UI_COLOR,
        ui_fgcolor=TPA_UI_FG_COLOR,
        tooltip='tradingpythonagent (tpa)',
    )
