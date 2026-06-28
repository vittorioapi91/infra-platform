"""Resolve deployed package wheels and database facts for the Airflow UI banner."""
from __future__ import annotations

import glob
import os
import re
from dataclasses import dataclass
from typing import List, Optional, Tuple


@dataclass(frozen=True)
class PackageInstallInfo:
    """Installed package and wheel state for one deployable package."""

    key: str
    label: str
    package_name: Optional[str] = None
    installed_version: Optional[str] = None
    wheel_filename: Optional[str] = None
    is_installed: bool = False

    @property
    def is_stale(self) -> bool:
        if not self.is_installed or not self.wheel_filename or not self.installed_version:
            return False
        wheel_version = _version_from_wheel_filename(self.wheel_filename, self.key)
        return bool(wheel_version and wheel_version != self.installed_version)


# Backward-compatible alias
IdpInstallInfo = PackageInstallInfo

_PACKAGE_SPECS = {
    "idp": {
        "display": "IDP",
        "dist_glob": "idp*.dist-info",
        "wheel_glob": "idp-*.whl",
        "workspace_dirs": [
            "/opt/airflow/workspace/idp-workspace",
            "/opt/airflow/package_root/idp",
        ],
        "storage_workspace_dirs": [
            ("dev", "workspace/idp-workspace"),
            ("test", "package_root/idp"),
            ("prod", "package_root/idp"),
        ],
    },
    "trading_agent": {
        "display": "TPA",
        "dist_glob": "trading_agent*.dist-info",
        "wheel_glob": "trading_agent-*.whl",
        "workspace_dirs": [
            "/opt/airflow/workspace/trading_agent-workspace",
            "/opt/airflow/package_root/trading_agent",
        ],
        "storage_workspace_dirs": [
            ("dev", "workspace/trading_agent-workspace"),
            ("test", "package_root/trading_agent"),
            ("prod", "package_root/trading_agent"),
        ],
    },
}


def _version_from_wheel_filename(filename: str, package_key: str) -> Optional[str]:
    prefix = "idp" if package_key == "idp" else package_key
    match = re.match(rf"^{re.escape(prefix)}-(\d+\.\d+\.\d+)", filename)
    return match.group(1) if match else None


def _parse_metadata(metadata_path: str) -> Tuple[Optional[str], Optional[str]]:
    name: Optional[str] = None
    version: Optional[str] = None
    try:
        with open(metadata_path, encoding="utf-8") as handle:
            for line in handle:
                line = line.strip()
                if line.startswith("Name:"):
                    name = line.split(":", 1)[1].strip()
                elif line.startswith("Version:"):
                    version = line.split(":", 1)[1].strip()
                    if name:
                        break
    except OSError:
        return None, None
    return name, version


def _repo_storage_airflow_root() -> str:
    plugin_dir = os.path.dirname(__file__)
    airflow_root = os.path.join(plugin_dir, "..", "..")
    repo_root = os.path.join(airflow_root, "..")
    return os.path.join(repo_root, "storage-infra", "airflow")


def _installed_search_dirs(spec: dict) -> List[str]:
    dirs = list(spec["workspace_dirs"])
    storage_root = _repo_storage_airflow_root()
    for env_name, rel_path in spec["storage_workspace_dirs"]:
        dirs.append(os.path.join(storage_root, env_name, rel_path))
    return dirs


def _read_installed_from_dist_info(package_key: str) -> Tuple[Optional[str], Optional[str]]:
    spec = _PACKAGE_SPECS[package_key]
    newest: Tuple[Optional[str], Optional[str]] = (None, None)
    for base_dir in _installed_search_dirs(spec):
        if not os.path.isdir(base_dir):
            continue
        for dist_info in glob.glob(os.path.join(base_dir, spec["dist_glob"])):
            metadata_path = os.path.join(dist_info, "METADATA")
            if not os.path.isfile(metadata_path):
                continue
            name, version = _parse_metadata(metadata_path)
            if name and version and (newest[1] is None or version > newest[1]):
                newest = (name, version)
    return newest


def _read_installed_from_importlib(package_key: str) -> Tuple[Optional[str], Optional[str]]:
    import_name = "idp" if package_key == "idp" else package_key
    try:
        import importlib.metadata as metadata
    except ImportError:
        try:
            import importlib_metadata as metadata  # type: ignore
        except ImportError:
            return None, None

    for dist in metadata.distributions():
        name = dist.metadata.get("Name", "")
        if name == import_name or name.startswith(f"{import_name}-"):
            return name, dist.version
    return None, None


def _latest_wheel_filename(package_key: str) -> Optional[str]:
    spec = _PACKAGE_SPECS[package_key]
    wheel_dirs = [
        "/opt/airflow/wheels",
        os.path.join(os.path.dirname(__file__), "..", "..", "wheels"),
    ]
    candidates: List[str] = []
    for wheel_dir in wheel_dirs:
        if os.path.isdir(wheel_dir):
            candidates.extend(
                os.path.basename(path)
                for path in glob.glob(os.path.join(wheel_dir, spec["wheel_glob"]))
            )
    if not candidates:
        return None
    return sorted(
        candidates,
        key=lambda name: _version_from_wheel_filename(name, package_key) or "0.0.0",
    )[-1]


def resolve_package_install_info(package_key: str) -> PackageInstallInfo:
    """Return banner facts for one package (idp or trading_agent)."""
    if package_key not in _PACKAGE_SPECS:
        raise ValueError(f"Unknown package key: {package_key}")

    display = _PACKAGE_SPECS[package_key]["display"]
    package_name, installed_version = _read_installed_from_dist_info(package_key)
    if not installed_version:
        package_name, installed_version = _read_installed_from_importlib(package_key)

    latest_wheel = _latest_wheel_filename(package_key)

    if package_name and installed_version:
        label = f"{display}: {package_name} {installed_version}"
        wheel_filename = latest_wheel
        if (
            wheel_filename
            and _version_from_wheel_filename(wheel_filename, package_key)
            and _version_from_wheel_filename(wheel_filename, package_key) != installed_version
        ):
            label = (
                f"{display}: {package_name} {installed_version} "
                f"(newer wheel: {_version_from_wheel_filename(wheel_filename, package_key)})"
            )
        return PackageInstallInfo(
            key=package_key,
            label=label,
            package_name=package_name,
            installed_version=installed_version,
            wheel_filename=wheel_filename,
            is_installed=True,
        )

    if latest_wheel:
        wheel_version = _version_from_wheel_filename(latest_wheel, package_key)
        pending = f"{package_name or package_key} {wheel_version}" if wheel_version else latest_wheel
        return PackageInstallInfo(
            key=package_key,
            label=f"{display}: not installed (wheel: {pending})",
            wheel_filename=latest_wheel,
            is_installed=False,
        )

    return PackageInstallInfo(key=package_key, label=f"{display}: not installed", is_installed=False)


def resolve_idp_install_info() -> PackageInstallInfo:
    return resolve_package_install_info("idp")


def resolve_tpa_install_info() -> PackageInstallInfo:
    return resolve_package_install_info("trading_agent")


def resolve_database_display() -> Tuple[str, str]:
    """Return (user@host:port/db, user) from container env vars."""
    db_host = os.getenv("POSTGRES_HOST", "not set")
    db_port = os.getenv("POSTGRES_PORT", "not set")
    db_name = os.getenv("POSTGRES_DB", "not set")
    db_user = os.getenv("POSTGRES_USER", "not set")
    if db_host != "not set" and db_port != "not set":
        return f"{db_user}@{db_host}:{db_port}/{db_name}", db_user
    return "not configured", db_user


def resolve_logged_in_user() -> str:
    """Return the Airflow UI user when evaluated inside a web request."""
    try:
        from flask import has_request_context

        if has_request_context():
            from flask_login import current_user

            if current_user and not getattr(current_user, "is_anonymous", True):
                username = getattr(current_user, "username", None)
                if username:
                    return username
                return str(current_user)
    except Exception:
        pass

    try:
        from airflow.providers.fab.auth_manager.fab_auth_manager import FabAuthManager

        auth_manager = FabAuthManager()
        user = auth_manager.get_user()
        if user and not getattr(user, "is_anonymous", True):
            username = getattr(user, "username", None)
            if username:
                return username
    except Exception:
        pass

    return "—"


def resolve_banner_context() -> dict:
    """Facts for dashboard UI alerts and environment info pages."""
    idp = resolve_idp_install_info()
    tpa = resolve_tpa_install_info()
    db_instance, db_user = resolve_database_display()
    logged_in_user = resolve_logged_in_user()
    airflow_env = os.getenv("AIRFLOW_ENV", "unknown").upper()

    return {
        "airflow_env": airflow_env,
        "idp_install": idp,
        "tpa_install": tpa,
        "idp_label": idp.label,
        "tpa_label": tpa.label,
        "airflow_wheel_version": idp.label,
        "airflow_wheel_file": idp.wheel_filename,
        "airflow_package_version": idp.installed_version,
        "airflow_db_instance": db_instance,
        "airflow_db_user": db_user,
        "logged_in_user": logged_in_user,
        "git_branch": os.getenv("GIT_BRANCH", "not set"),
        "db_host": os.getenv("POSTGRES_HOST", "not set"),
        "db_port": os.getenv("POSTGRES_PORT", "not set"),
        "db_name": os.getenv("POSTGRES_DB", "not set"),
    }


def build_banner_markdown() -> str:
    """Markdown banner for Airflow 3 DASHBOARD_UIALERTS."""
    ctx = resolve_banner_context()
    env = ctx["airflow_env"]
    # Escape @ so ReactMarkdown does not autolink / break the line into a code block
    db = ctx["airflow_db_instance"].replace("@", "\\@")
    return (
        f"**Environment:** {env} · **IDP:** {_short_package_label(ctx['idp_install'])} · "
        f"**TPA:** {_short_package_label(ctx['tpa_install'])} · "
        f"**Database:** {db}"
    )


def build_banner_html() -> str:
    """HTML banner fallback when UIAlert markdown is unavailable."""
    ctx = resolve_banner_context()
    env = ctx["airflow_env"]
    env_color = "#28a745" if env == "DEV" else "#ffc107" if env in {"STAGING", "TEST"} else "#dc3545"
    env_text_color = "black" if env in {"STAGING", "TEST"} else "white"
    return f"""
<div style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 10px 16px; margin-bottom: 12px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1);">
    <div style="display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 8px;">
        <div style="display: flex; align-items: center; gap: 14px; flex-wrap: wrap; font-size: 14px;">
            <div>
                <strong style="opacity: 0.9;">Environment:</strong>
                <span style="background-color: {env_color}; color: {env_text_color}; padding: 2px 10px; border-radius: 4px; font-weight: bold; margin-left: 6px;">{env}</span>
            </div>
            <div><strong style="opacity: 0.9;">IDP:</strong> {_short_package_label(ctx['idp_install'])}</div>
            <div><strong style="opacity: 0.9;">TPA:</strong> {_short_package_label(ctx['tpa_install'])}</div>
            <div><strong style="opacity: 0.9;">Database:</strong> {ctx['airflow_db_instance']}</div>
        </div>
        <div><a href="/environment-info/" style="color: white; text-decoration: underline; font-size: 13px;">View Details →</a></div>
    </div>
</div>
"""


def _short_package_label(info: PackageInstallInfo) -> str:
    if info.is_installed and info.package_name and info.installed_version:
        return f"{info.package_name} {info.installed_version}"
    if info.wheel_filename:
        version = _version_from_wheel_filename(info.wheel_filename, info.key)
        if version:
            return f"pending {version}"
    return "not installed"
