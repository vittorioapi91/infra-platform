"""
Airflow plugin for system control (reboot functionality)
"""
import os
import subprocess
import json
from airflow.plugins_manager import AirflowPlugin
from flask_appbuilder import BaseView, expose


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

    @expose("/reboot", methods=["POST"])
    def reboot(self):
        """Trigger container reboot"""
        try:
            # Get container name
            container_name = os.getenv("HOSTNAME", "airflow-dev")
            
            # Method 1: Try using docker command (if docker socket is mounted)
            try:
                # Try to restart via docker command
                result = subprocess.run(
                    ["docker", "restart", container_name],
                    capture_output=True,
                    text=True,
                    timeout=5,
                )
                if result.returncode == 0:
                    return json.dumps({
                        "status": "success",
                        "message": f"Container {container_name} restart initiated successfully. This page will refresh shortly."
                    }), 200, {"Content-Type": "application/json"}
            except (subprocess.TimeoutExpired, FileNotFoundError, Exception) as e:
                pass
            
            # Method 2: Try writing to a trigger file (if volume is mounted)
            try:
                trigger_file = "/opt/airflow/.restart_trigger"
                with open(trigger_file, "w") as f:
                    f.write(f"Restart requested at {os.popen('date').read().strip()}\n")
                return json.dumps({
                    "status": "success",
                    "message": "Restart trigger file created. Container will restart shortly if a monitor script is running."
                }), 200, {"Content-Type": "application/json"}
            except Exception as e:
                pass
            
            # Method 3: Fallback - exit the container process (will cause restart if restart policy is set)
            return json.dumps({
                "status": "info",
                "message": f"Reboot requested for {container_name}. Please restart the container manually using: docker restart {container_name}"
            }), 200, {"Content-Type": "application/json"}
            
        except Exception as e:
            return json.dumps({
                "status": "error",
                "message": f"Failed to trigger reboot: {str(e)}"
            }), 500, {"Content-Type": "application/json"}


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
