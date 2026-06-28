"""
Airflow local settings for UI customization (Airflow 2 + 3).
"""
import os
import sys

_plugins_dir = os.path.join(os.path.dirname(__file__), "..", "plugins")
_plugins_dir = os.path.abspath(_plugins_dir)
if _plugins_dir not in sys.path:
    sys.path.insert(0, _plugins_dir)

try:
    from environment_info.idp_install_info import build_banner_markdown, build_banner_html
except Exception:
    def build_banner_markdown() -> str:
        env = os.getenv("AIRFLOW_ENV", "unknown").upper()
        return f"**Environment:** {env} · package metadata unavailable"

    def build_banner_html() -> str:
        return f"<div><strong>Environment:</strong> {os.getenv('AIRFLOW_ENV', 'unknown').upper()}</div>"


def build_dashboard_alerts() -> list:
    """Build fresh UI alerts (IDP/TPA versions, database)."""
    import importlib

    try:
        import environment_info.idp_install_info as install_info

        importlib.reload(install_info)
        markdown = install_info.build_banner_markdown()
        html = install_info.build_banner_html()
    except Exception:
        markdown = build_banner_markdown()
        html = build_banner_html()

    try:
        from airflow.api_fastapi.common.types import UIAlert

        return [UIAlert(text=markdown, category="info")]
    except ImportError:
        try:
            from airflow.utils.ui_alerts import UIAlert

            return [UIAlert(message=html, category="info", html=True)]
        except ImportError:
            return []


class DashboardAlerts(list):
    """Dynamic alerts — rebuilt whenever the UI reads DASHBOARD_UIALERTS."""

    def __iter__(self):
        return iter(build_dashboard_alerts())

    def __len__(self) -> int:
        return len(build_dashboard_alerts())


DASHBOARD_UIALERTS = DashboardAlerts()
