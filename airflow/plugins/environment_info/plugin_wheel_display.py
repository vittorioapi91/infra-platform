"""
Airflow plugin to display environment and wheel version information
"""
import os

from airflow.plugins_manager import AirflowPlugin
from flask import Blueprint, request, g, render_template
from flask_appbuilder import BaseView, expose

from environment_info.idp_install_info import (
    resolve_database_display,
    resolve_idp_install_info,
)

ENV = os.getenv("AIRFLOW_ENV", "unknown")


def _banner_context() -> dict:
    install = resolve_idp_install_info()
    db_instance, db_user = resolve_database_display()
    return {
        "airflow_env": ENV.upper(),
        "airflow_wheel_version": install.label,
        "airflow_wheel_file": install.wheel_filename,
        "airflow_package_version": install.installed_version,
        "airflow_db_instance": db_instance,
        "airflow_db_user": db_user,
    }


class EnvironmentInfoView(BaseView):
    """Custom view to display environment and wheel information."""

    route_base = "/environment-info"
    default_view = "info"

    @expose("/")
    def list(self):
        return self.info()

    @expose("/info")
    def info(self):
        ctx = _banner_context()
        return self.render_template(
            "environment_info/info.html",
            env=ENV,
            wheel_version=ctx["airflow_wheel_version"],
            wheel_file=ctx["airflow_wheel_file"],
            package_version=ctx["airflow_package_version"],
            airflow_env=os.getenv("AIRFLOW_ENV", "not set"),
            git_branch=os.getenv("GIT_BRANCH", "not set"),
            db_host=os.getenv("POSTGRES_HOST", "not set"),
            db_port=os.getenv("POSTGRES_PORT", "not set"),
            db_name=os.getenv("POSTGRES_DB", "not set"),
            db_user=ctx["airflow_db_user"],
            db_instance=ctx["airflow_db_instance"],
        )


bp = Blueprint(
    "environment_info",
    __name__,
    template_folder="templates",
    static_folder="static",
    static_url_path="/static/environment_info",
)


@bp.app_context_processor
def inject_environment_info():
    return _banner_context()


@bp.route("/environment-badge")
def environment_badge():
    ctx = _banner_context()
    return (
        f"Environment: {ENV} | Package: {ctx['airflow_wheel_version']}",
        200,
        {"Content-Type": "text/plain"},
    )


@bp.before_app_request
def inject_banner_data():
    ctx = _banner_context()
    for key, value in ctx.items():
        setattr(g, key, value)


@bp.after_app_request
def inject_banner_into_dags_page(response):
    if not (
        response.content_type
        and "text/html" in response.content_type
        and request.path in ["/home", "/dags", "/"]
    ):
        return response

    try:
        content = response.get_data(as_text=True)
        ctx = _banner_context()
        env_color = "#28a745" if ENV.upper() == "DEV" else "#ffc107" if ENV.upper() == "STAGING" else "#dc3545"
        env_text_color = "black" if ENV.upper() == "STAGING" else "white"

        banner_html = f"""
<div style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 15px 20px; margin-bottom: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1);">
    <div style="display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap;">
        <div style="display: flex; align-items: center; gap: 20px; flex-wrap: wrap;">
            <div>
                <strong style="font-size: 14px; opacity: 0.9;">Environment:</strong>
                <span style="background-color: {env_color}; color: {env_text_color}; padding: 4px 12px; border-radius: 4px; font-weight: bold; margin-left: 8px;">
                    {ctx["airflow_env"]}
                </span>
            </div>
            <div>
                <strong style="font-size: 14px; opacity: 0.9;">Package:</strong>
                <span style="font-family: monospace; margin-left: 8px;">{ctx["airflow_wheel_version"]}</span>
            </div>
            <div>
                <strong style="font-size: 14px; opacity: 0.9;">Database:</strong>
                <span style="font-family: monospace; margin-left: 8px;">{ctx["airflow_db_instance"]}</span>
            </div>
        </div>
        <div>
            <a href="/environment-info/" style="color: white; text-decoration: underline; font-size: 13px;">View Details →</a>
        </div>
    </div>
</div>
"""

        insertion_points = [
            "<h1>DAGs</h1>",
            "<h1 class=",
            '<div class="container-fluid">',
            '<div id="dag-table"',
            '<div class="dag-list-container"',
        ]

        inserted = False
        for point in insertion_points:
            if point in content:
                content = content.replace(point, banner_html + "\n" + point, 1)
                inserted = True
                break

        if not inserted and "<body" in content:
            body_end = content.find(">", content.find("<body"))
            if body_end > 0:
                next_div = content.find("<div", body_end)
                if next_div > 0:
                    content = content[:next_div] + banner_html + "\n" + content[next_div:]
                    inserted = True

        if inserted:
            response.set_data(content)
    except Exception:
        pass

    return response


class EnvironmentInfoPlugin(AirflowPlugin):
    """Airflow plugin to display environment and wheel information."""

    name = "environment_info"
    appbuilder_views = [
        {
            "name": "Environment Info",
            "category": "Admin",
            "view": EnvironmentInfoView(),
        },
    ]
    flask_blueprints = [bp]
