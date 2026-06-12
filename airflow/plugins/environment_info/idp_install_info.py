"""Resolve installed idp package and wheel facts for the Airflow UI banner."""
from __future__ import annotations

import glob
import os
import re
from dataclasses import dataclass
from typing import List, Optional, Tuple


@dataclass(frozen=True)
class IdpInstallInfo:
    """Installed package and wheel state for display."""

    label: str
    package_name: Optional[str] = None
    installed_version: Optional[str] = None
    wheel_filename: Optional[str] = None
    is_installed: bool = False

    @property
    def is_stale(self) -> bool:
        if not self.is_installed or not self.wheel_filename or not self.installed_version:
            return False
        wheel_version = _version_from_wheel_filename(self.wheel_filename)
        return bool(wheel_version and wheel_version != self.installed_version)


def _version_from_wheel_filename(filename: str) -> Optional[str]:
    match = re.match(r"^idp-(\d+\.\d+\.\d+)", filename)
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


def _installed_search_dirs() -> List[str]:
    plugin_dir = os.path.dirname(__file__)
    airflow_root = os.path.join(plugin_dir, "..", "..")
    repo_root = os.path.join(airflow_root, "..")
    storage_airflow = os.path.join(repo_root, "storage-infra", "airflow")
    return [
        "/opt/airflow/workspace/idp-workspace",
        "/opt/airflow/package_root/idp",
        os.path.join(storage_airflow, "dev", "workspace", "idp-workspace"),
        os.path.join(storage_airflow, "test", "package_root", "idp"),
        os.path.join(storage_airflow, "prod", "package_root", "idp"),
    ]


def _read_installed_from_dist_info() -> Tuple[Optional[str], Optional[str]]:
    newest: Tuple[Optional[str], Optional[str]] = (None, None)
    for base_dir in _installed_search_dirs():
        if not os.path.isdir(base_dir):
            continue
        for dist_info in glob.glob(os.path.join(base_dir, "idp*.dist-info")):
            metadata_path = os.path.join(dist_info, "METADATA")
            if not os.path.isfile(metadata_path):
                continue
            name, version = _parse_metadata(metadata_path)
            if name and version:
                if newest[1] is None or version > newest[1]:
                    newest = (name, version)
    return newest


def _read_installed_from_importlib() -> Tuple[Optional[str], Optional[str]]:
    try:
        import importlib.metadata as metadata
    except ImportError:
        try:
            import importlib_metadata as metadata  # type: ignore
        except ImportError:
            return None, None
    for dist in metadata.distributions():
        name = dist.metadata.get("Name", "")
        if name == "idp" or name.startswith("idp-"):
            return name, dist.version
    return None, None


def _latest_wheel_filename() -> Optional[str]:
    wheel_dirs = [
        "/opt/airflow/wheels",
        os.path.join(os.path.dirname(__file__), "..", "..", "wheels"),
    ]
    candidates: List[str] = []
    for wheel_dir in wheel_dirs:
        if os.path.isdir(wheel_dir):
            candidates.extend(
                os.path.basename(path)
                for path in glob.glob(os.path.join(wheel_dir, "idp-*.whl"))
            )
    if not candidates:
        return None
    return sorted(candidates, key=lambda name: _version_from_wheel_filename(name) or "0.0.0")[-1]


def resolve_idp_install_info() -> IdpInstallInfo:
    """
    Return banner facts from installed package metadata.

    Never reports a wheel filename as installed unless dist-info matches that version.
    """
    package_name, installed_version = _read_installed_from_dist_info()
    if not installed_version:
        package_name, installed_version = _read_installed_from_importlib()

    latest_wheel = _latest_wheel_filename()

    if package_name and installed_version:
        label = f"{package_name} {installed_version}"
        wheel_filename = latest_wheel
        if (
            wheel_filename
            and _version_from_wheel_filename(wheel_filename)
            and _version_from_wheel_filename(wheel_filename) != installed_version
        ):
            label = (
                f"{package_name} {installed_version} "
                f"(newer wheel available: {_version_from_wheel_filename(wheel_filename)})"
            )
        return IdpInstallInfo(
            label=label,
            package_name=package_name,
            installed_version=installed_version,
            wheel_filename=wheel_filename,
            is_installed=True,
        )

    if latest_wheel:
        wheel_version = _version_from_wheel_filename(latest_wheel)
        pending = f"idp {wheel_version}" if wheel_version else latest_wheel
        return IdpInstallInfo(
            label=f"not installed (wheel available: {pending})",
            wheel_filename=latest_wheel,
            is_installed=False,
        )

    return IdpInstallInfo(label="Not installed", is_installed=False)


def resolve_database_display() -> Tuple[str, str]:
    """Return (user@host:port/db, user) from container env vars."""
    db_host = os.getenv("POSTGRES_HOST", "not set")
    db_port = os.getenv("POSTGRES_PORT", "not set")
    db_name = os.getenv("POSTGRES_DB", "not set")
    db_user = os.getenv("POSTGRES_USER", "not set")
    if db_host != "not set" and db_port != "not set":
        return f"{db_user}@{db_host}:{db_port}/{db_name}", db_user
    return "not configured", db_user
