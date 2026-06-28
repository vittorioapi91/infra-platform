"""
Airflow 3 plugin: environment banner API, detail pages, and system control.

Replaces legacy FAB views and Flask blueprints (plugin_wheel_display, plugin_reboot,
plugin_startup_animation). The dashboard banner is provided by DASHBOARD_UIALERTS in
airflow_local_settings.py; this plugin adds Admin nav pages and reboot API.
"""
from __future__ import annotations

import os
import subprocess

from airflow.plugins_manager import AirflowPlugin
from fastapi import FastAPI
from fastapi.responses import HTMLResponse, JSONResponse, PlainTextResponse

from environment_info.idp_install_info import resolve_banner_context

ENV = os.getenv("AIRFLOW_ENV", "unknown")


def _env_badge_colors(env: str) -> tuple[str, str]:
    upper = env.upper()
    if upper == "DEV":
        return "#28a745", "white"
    if upper in {"STAGING", "TEST"}:
        return "#ffc107", "black"
    return "#dc3545", "white"


def _render_environment_info_html() -> str:
    ctx = resolve_banner_context()
    env = ctx["airflow_env"]
    bg, fg = _env_badge_colors(env)
    wheel_file = ctx["airflow_wheel_file"] or ""
    wheel_row = (
        f"<tr><th>Latest wheel file</th><td><code>{wheel_file}</code></td></tr>"
        if wheel_file
        else ""
    )
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>Environment Information</title>
  <style>
    body {{ font-family: system-ui, sans-serif; margin: 24px; color: #212529; }}
    h1 {{ margin-bottom: 8px; }}
    .badge {{
      display: inline-block; padding: 4px 12px; border-radius: 4px;
      background: {bg}; color: {fg}; font-weight: 700;
    }}
    table {{ border-collapse: collapse; margin-top: 20px; min-width: 520px; }}
    th, td {{ border: 1px solid #dee2e6; padding: 10px 14px; text-align: left; }}
    th {{ background: #f8f9fa; width: 220px; }}
    code {{ font-family: ui-monospace, monospace; }}
  </style>
</head>
<body>
  <h1>Environment Information <span class="badge">{env}</span></h1>
  <table>
    <tr><th>Environment</th><td>{env}</td></tr>
    <tr><th>IDP package</th><td>{ctx['idp_label']}</td></tr>
    <tr><th>TPA package</th><td>{ctx['tpa_label']}</td></tr>
    {wheel_row}
    <tr><th>AIRFLOW_ENV</th><td>{ctx.get('airflow_env', ENV)}</td></tr>
    <tr><th>GIT_BRANCH</th><td>{ctx['git_branch']}</td></tr>
    <tr><th>Database</th><td><code>{ctx['airflow_db_instance']}</code></td></tr>
    <tr><th>Database host</th><td>{ctx['db_host']}</td></tr>
    <tr><th>Database port</th><td>{ctx['db_port']}</td></tr>
    <tr><th>Database name</th><td>{ctx['db_name']}</td></tr>
    <tr><th>Database user</th><td>{ctx['airflow_db_user']}</td></tr>
    <tr><th>Logged in as</th><td>{ctx['logged_in_user']}</td></tr>
  </table>
</body>
</html>"""


def _render_system_control_html() -> str:
    container_name = os.getenv("HOSTNAME", "airflow-dev")
    in_docker = os.path.exists("/.dockerenv")
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>System Control</title>
  <style>
    body {{ font-family: system-ui, sans-serif; margin: 24px; color: #212529; }}
    button {{
      margin-top: 16px; padding: 10px 16px; border: 0; border-radius: 6px;
      background: #dc3545; color: white; font-weight: 600; cursor: pointer;
    }}
    button:disabled {{ opacity: 0.6; cursor: not-allowed; }}
    #status {{ margin-top: 12px; }}
  </style>
</head>
<body>
  <h1>System Control</h1>
  <ul>
    <li><strong>Container:</strong> <code>{container_name}</code></li>
    <li><strong>Running in Docker:</strong> {"Yes" if in_docker else "No"}</li>
  </ul>
  <button id="reboot-btn" type="button">Restart Airflow container</button>
  <div id="status"></div>
  <script>
    document.getElementById("reboot-btn").addEventListener("click", async () => {{
      const btn = document.getElementById("reboot-btn");
      const status = document.getElementById("status");
      btn.disabled = true;
      status.textContent = "Requesting restart...";
      try {{
        const response = await fetch("system-control/reboot", {{ method: "POST" }});
        const data = await response.json();
        status.textContent = data.message || JSON.stringify(data);
      }} catch (err) {{
        status.textContent = "Request failed: " + err;
      }} finally {{
        btn.disabled = false;
      }}
    }});
  </script>
</body>
</html>"""


def _reboot_container() -> JSONResponse:
    container_name = os.getenv("HOSTNAME", "airflow-dev")
    try:
        import docker

        client = docker.from_env()
        client.containers.get(container_name).restart()
        return JSONResponse(
            {
                "status": "success",
                "message": f"Container {container_name} restart initiated successfully.",
            }
        )
    except Exception:
        pass

    try:
        result = subprocess.run(
            ["docker", "restart", container_name],
            capture_output=True,
            text=True,
            timeout=5,
        )
        if result.returncode == 0:
            return JSONResponse(
                {
                    "status": "success",
                    "message": f"Container {container_name} restart initiated successfully.",
                }
            )
    except Exception:
        pass

    try:
        trigger_file = "/opt/airflow/.restart_trigger"
        with open(trigger_file, "w", encoding="utf-8") as handle:
            handle.write(f"Restart requested for {container_name}\n")
        return JSONResponse(
            {
                "status": "success",
                "message": "Restart trigger file created.",
            }
        )
    except Exception:
        pass

    return JSONResponse(
        {
            "status": "info",
            "message": (
                f"Reboot requested for {container_name}. "
                f"Restart manually: docker restart {container_name}"
            ),
        }
    )


def _build_environment_info_app() -> FastAPI:
    app = FastAPI()

    @app.get("/", response_class=HTMLResponse)
    def show_environment_info():
        return HTMLResponse(_render_environment_info_html())

    @app.get("/api/context")
    def fetch_banner_context():
        return resolve_banner_context()

    @app.get("/api/badge", response_class=PlainTextResponse)
    def fetch_environment_badge():
        ctx = resolve_banner_context()
        return PlainTextResponse(
            f"Environment: {ENV} | IDP: {ctx['idp_label']} | TPA: {ctx['tpa_label']} | "
            f"Database: {ctx['airflow_db_instance']}"
        )

    @app.get("/system-control", response_class=HTMLResponse)
    def show_system_control():
        return HTMLResponse(_render_system_control_html())

    @app.post("/system-control/reboot")
    def reboot_airflow_container():
        return _reboot_container()

    return app


class EnvironmentInfoPlugin(AirflowPlugin):
    name = "environment_info"

    fastapi_apps = [
        {
            "name": "environment_info",
            "app": _build_environment_info_app(),
            "url_prefix": "/plugins/environment-info",
        }
    ]

    external_views = [
        {
            "name": "Environment Info",
            "href": "/plugins/environment-info/",
            "destination": "nav",
            "category": "admin",
            "url_route": "environment-info",
        },
        {
            "name": "System Control",
            "href": "/plugins/environment-info/system-control",
            "destination": "nav",
            "category": "admin",
            "url_route": "system-control",
        },
    ]
