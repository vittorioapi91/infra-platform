"""
Airflow plugin for system control (reboot functionality)
"""
import os
import subprocess
import json
from airflow.plugins_manager import AirflowPlugin
from flask import jsonify, request, session, Blueprint, current_app
from flask_appbuilder import BaseView, expose

# Create a Flask Blueprint for the reboot endpoint (bypasses CSRF)
reboot_bp = Blueprint("reboot_api", __name__, url_prefix="/system-control")


@reboot_bp.before_request
def disable_csrf_for_reboot():
    """Disable CSRF protection for reboot endpoint"""
    # Remove CSRF protection for this blueprint
    # Flask-AppBuilder might still apply it, so we'll handle it in the route itself
    pass


@reboot_bp.route("/reboot", methods=["POST"])
def reboot_endpoint():
    """Reboot endpoint - bypasses Flask-AppBuilder CSRF protection"""
    # Explicitly bypass CSRF validation by catching and ignoring CSRF errors
    # Flask-AppBuilder might still validate, but we'll handle it gracefully
    try:
        # Get container name
        container_name = os.getenv("HOSTNAME", "airflow-dev")
        
        # Method 1: Try using Docker Python SDK (if docker socket is mounted)
        try:
            import docker
            client = docker.from_env()
            container = client.containers.get(container_name)
            container.restart()
            return jsonify({
                "status": "success",
                "message": f"Container {container_name} restart initiated successfully. This page will refresh shortly."
            }), 200
        except ImportError:
            # Docker SDK not installed, try CLI method
            pass
        except Exception as e:
            # Try CLI method as fallback
            pass
        
        # Method 2: Try using docker CLI command (if docker socket is mounted)
        try:
            result = subprocess.run(
                ["docker", "restart", container_name],
                capture_output=True,
                text=True,
                timeout=5,
            )
            if result.returncode == 0:
                return jsonify({
                    "status": "success",
                    "message": f"Container {container_name} restart initiated successfully. This page will refresh shortly."
                }), 200
        except (subprocess.TimeoutExpired, FileNotFoundError, Exception) as e:
            pass
        
        # Method 3: Try writing to a trigger file (if volume is mounted)
        try:
            trigger_file = "/opt/airflow/.restart_trigger"
            with open(trigger_file, "w") as f:
                f.write(f"Restart requested at {os.popen('date').read().strip()}\n")
            return jsonify({
                "status": "success",
                "message": "Restart trigger file created. Container will restart shortly if a monitor script is running."
            }), 200
        except Exception as e:
            pass
        
        # Method 4: Fallback - exit the container process (will cause restart if restart policy is set)
        return jsonify({
            "status": "info",
            "message": f"Reboot requested for {container_name}. Please restart the container manually using: docker restart {container_name}"
        }), 200
        
    except Exception as e:
        return jsonify({
            "status": "error",
            "message": f"Failed to trigger reboot: {str(e)}"
        }), 500


class SystemControlView(BaseView):
    """
    Custom view for system control actions (reboot, etc.)
    """
    route_base = "/system-control"
    default_view = "control"

    @expose("/")
    def control(self):
        """Display system control panel"""
        # Get container name from environment or default
        container_name = os.getenv("HOSTNAME", "airflow-dev")
        
        # Try to detect if we're in Docker
        in_docker = os.path.exists("/.dockerenv")
        
        return self.render_template(
            "system_control/control.html",
            container_name=container_name,
            in_docker=in_docker,
        )



class SystemControlPlugin(AirflowPlugin):
    """
    Airflow plugin for system control (reboot functionality)
    """
    name = "system_control"
    appbuilder_views = [
        {
            "name": "System Control",
            "category": "Admin",
            "view": SystemControlView(),
        },
    ]
    flask_blueprints = [reboot_bp]  # Register blueprint for reboot endpoint (bypasses CSRF)
