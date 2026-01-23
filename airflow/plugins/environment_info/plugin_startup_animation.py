"""
Airflow plugin for startup animation and loading indicators
"""
import os
import subprocess
from airflow.plugins_manager import AirflowPlugin
from flask import Blueprint, request, jsonify

# Get environment from environment variable
ENV = os.getenv("AIRFLOW_ENV", "unknown")

# Create blueprint with URL prefix
bp = Blueprint(
    "startup_animation",
    __name__,
    url_prefix="/startup-animation",
    template_folder="templates",
    static_folder="static",
    static_url_path="/static/startup_animation",
)


# Log endpoint removed - not working reliably
# def get_startup_logs():
#     pass


@bp.after_app_request
def inject_startup_animation(response):
    """Inject startup animation indicator into HTML responses"""
    # Inject on all HTML pages, but only during startup animation
    if response.content_type and 'text/html' in response.content_type:
        
        try:
            content = response.get_data(as_text=True)
            
            # Detect if Airflow is still starting up
            # Only show log window during startup animation phase
            webserver_pid_exists = os.path.exists('/opt/airflow/airflow-webserver.pid')
            response_is_error = response.status_code != 200
            # Show log window only if webserver PID doesn't exist OR response is an error
            # Once Airflow is fully started (PID exists AND response is 200), don't inject
            is_starting = response_is_error or not webserver_pid_exists
            
            if is_starting:
                # Add loading spinner CSS only (log window removed)
                loading_css = """
<style>
@keyframes spin {
    0% { transform: rotate(0deg); }
    100% { transform: rotate(360deg); }
}
.startup-spinner {
    display: inline-block;
    width: 14px;
    height: 14px;
    border: 2px solid rgba(255,255,255,0.3);
    border-top-color: white;
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
    margin-right: 8px;
    vertical-align: middle;
}
</style>
"""
                loading_indicator = '<span class="startup-spinner"></span>'
                
                # Environment color
                env_color = "#28a745" if ENV.upper() == "DEV" else "#ffc107" if ENV.upper() == "STAGING" else "#dc3545"
                env_text_color = "black" if ENV.upper() == "STAGING" else "white"
                
                # Get database info for banner (if banner exists)
                db_host = os.getenv("POSTGRES_HOST", "not set")
                db_port = os.getenv("POSTGRES_PORT", "not set")
                db_name = os.getenv("POSTGRES_DB", "not set")
                db_user = os.getenv("POSTGRES_USER", "not set")
                
                if db_host != "not set" and db_port != "not set":
                    db_instance = f"{db_host}:{db_port}/{db_name}"
                else:
                    db_instance = "not configured"
                
                # Inject CSS and update banner if it exists
                # Look for existing banner with "Environment:" label
                if '<strong style="font-size: 14px; opacity: 0.9;">Environment:</strong>' in content:
                    # Replace the banner's Environment label to add spinner and starting indicator
                    content = content.replace(
                        '<strong style="font-size: 14px; opacity: 0.9;">Environment:</strong>',
                        f'{loading_css}<strong style="font-size: 14px; opacity: 0.9;">{loading_indicator}Environment:</strong>'
                    )
                    # Add "(Starting...)" indicator after environment badge if not already there
                    env_badge_pattern = f'<span style="background-color: {env_color}; color: {env_text_color}; padding: 4px 12px; border-radius: 4px; font-weight: bold; margin-left: 8px;">{ENV.upper()}</span>'
                    if env_badge_pattern in content and '(Starting...)' not in content:
                        content = content.replace(
                            env_badge_pattern,
                            env_badge_pattern + '<span style="margin-left: 10px; font-size: 12px; opacity: 0.8;">(Starting...)</span>'
                        )
                else:
                    # No banner exists, inject CSS in head if possible
                    if '</head>' in content:
                        content = content.replace('</head>', loading_css + '</head>')
                    # Also inject at end of body if no banner found (fallback for pages without banner)
                    elif '</body>' in content:
                        content = content.replace('</body>', loading_css + '</body>')
                
                response.set_data(content)
                
        except Exception as e:
            # Silently fail - don't break the page if animation injection fails
            pass
    
    return response


class StartupAnimationPlugin(AirflowPlugin):
    """
    Airflow plugin for startup animation and loading indicators
    """
    name = "startup_animation"
    flask_blueprints = [bp]
