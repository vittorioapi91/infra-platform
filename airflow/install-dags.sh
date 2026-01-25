#!/bin/bash
#
# Install Airflow DAGs by creating import scripts that reference the installed trading_agent package
#
# This script creates Python import files in airflow/{env}/dags/ that import DAGs
# from the installed trading_agent package (wheel) without copying files.
#
# Each environment has its own wheel installation at airflow/{env}/trading_agent/
# with DAGs at trading_agent/src/.airflow-dags/
#
# Usage:
#   ./install-dags.sh [dev|test|prod] [package_name]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# Get environment and package name from arguments
ENV="${1:-dev}"
PACKAGE_NAME="${2:-trading_agent}"

INSTALL_DIR_ENV="${ENV}"

# Destination directory for import scripts
# If running in Docker/container, use /opt/airflow/dags (mounted from airflow/{env}/dags)
# Otherwise, use airflow/{env}/dags (versioned) and storage-infra for workspace
if [ -d "/opt/airflow/dags" ]; then
    DEST_DIR="/opt/airflow/dags"
    WORKSPACE_ROOT="/opt/airflow/workspace"
else
    DEST_DIR="${PROJECT_ROOT}/${INSTALL_DIR_ENV}/dags"
    WORKSPACE_ROOT="${PROJECT_ROOT}/../storage-infra/airflow/${INSTALL_DIR_ENV}/workspace"
    [ "${INSTALL_DIR_ENV}" != "dev" ] && WORKSPACE_ROOT="${PROJECT_ROOT}/../storage-infra/airflow/${INSTALL_DIR_ENV}/package_root"
fi

# Source directory: dev uses workspace/{package}-workspace/{package}/; test/prod use package_root/{package}/
if [ "${INSTALL_DIR_ENV}" = "dev" ]; then
    SOURCE_DIR="${WORKSPACE_ROOT}/${PACKAGE_NAME}-workspace/${PACKAGE_NAME}/.airflow-dags"
    [ ! -d "${SOURCE_DIR}" ] && SOURCE_DIR="${WORKSPACE_ROOT}/${PACKAGE_NAME}-workspace/${PACKAGE_NAME}/src/.airflow-dags"
else
    SOURCE_DIR="${WORKSPACE_ROOT}/${PACKAGE_NAME}/.airflow-dags"
    [ ! -d "${SOURCE_DIR}" ] && SOURCE_DIR="${WORKSPACE_ROOT}/${PACKAGE_NAME}/src/.airflow-dags"
fi

log_info "Locating DAGs in installed ${PACKAGE_NAME} package..."
log_info "Expected location: ${SOURCE_DIR}"

# Check if source directory exists
if [ ! -d "${SOURCE_DIR}" ]; then
    log_warn "Could not find .airflow-dags directory at: ${SOURCE_DIR}"
    log_warn ""
    log_warn "Please ensure:"
    log_warn "  1. ${PACKAGE_NAME} wheel is installed to ${PACKAGE_ROOT}/${PACKAGE_NAME}/"
    log_warn "  2. The wheel contains src/.airflow-dags/ directory"
    exit 1
fi

# Check if source directory is empty
if [ -z "$(ls -A "${SOURCE_DIR}" 2>/dev/null)" ]; then
    log_warn "Source directory is empty: ${SOURCE_DIR}"
    log_info "No DAGs to install"
    exit 0
fi

# Create destination directory if it doesn't exist
mkdir -p "${DEST_DIR}"

log_info "Creating DAG import scripts..."
log_info "  DAG source: ${SOURCE_DIR}"
log_info "  Import scripts: ${DEST_DIR}"

# Find all Python DAG files in the source directory
DAG_FILES=$(find "${SOURCE_DIR}" -type f -name "*.py" ! -name "__init__.py" 2>/dev/null)

if [ -z "${DAG_FILES}" ]; then
    log_warn "No Python DAG files found in ${SOURCE_DIR}"
    exit 0
fi

# Count files to create import scripts for
FILE_COUNT=$(echo "${DAG_FILES}" | wc -l | tr -d ' ')
log_info "Found ${FILE_COUNT} DAG file(s) to create import scripts for"

# Process each DAG file
CREATED_COUNT=0
while IFS= read -r dag_file; do
    if [ -n "${dag_file}" ]; then
        # Get relative path from source directory
        rel_path="${dag_file#${SOURCE_DIR}/}"
        
        # Get base filename without extension (e.g., "my_dag.py" -> "my_dag")
        dag_basename=$(basename "${rel_path}" .py)
        
        # Import script filename: same as DAG file
        import_script="${DEST_DIR}/${dag_basename}.py"
        
        # Calculate relative import path from DEST_DIR to SOURCE_DIR
        # When in Docker: DEST_DIR=/opt/airflow/dags, SOURCE_DIR=/opt/airflow/package_root/trading_agent/src/.airflow-dags
        # We need to import from: trading_agent.src.airflow_dags.{module}
        # When not in Docker: DEST_DIR=airflow/{env}/dags, SOURCE_DIR=airflow/{env}/trading_agent/src/.airflow-dags
        # We need to import from: trading_agent.src.airflow_dags.{module}
        
        # For Airflow to find the package, we need to add the package root to sys.path
        # The package is at {package_root}/{package_name}, so we add {package_root} to sys.path
        # Then import as: from {package_name}.src.airflow_dags.{module} import *
        
        # Get directory path relative to package root (e.g., "src/.airflow-dags/subdir" -> "src/airflow_dags/subdir")
        rel_dir=$(dirname "${rel_path}")
        # Replace .airflow-dags with airflow_dags for Python import (dashes not allowed)
        rel_dir_normalized=$(echo "${rel_dir}" | sed 's/\.airflow-dags/airflow_dags/g')
        
        # Build import path: {package_name}.{rel_dir_normalized}.{dag_basename}
        if [ "${rel_dir_normalized}" = "." ] || [ -z "${rel_dir_normalized}" ]; then
            import_module="${PACKAGE_NAME}.src.airflow_dags.${dag_basename}"
        else
            # Replace slashes with dots for Python import
            rel_dir_dots=$(echo "${rel_dir_normalized}" | tr '/' '.')
            import_module="${PACKAGE_NAME}.${rel_dir_dots}.${dag_basename}"
        fi
        
        # Create import script
        cat > "${import_script}" << EOF
#!/usr/bin/env python3
"""
Airflow DAG import script for ${dag_basename}

This file imports DAGs from the installed ${PACKAGE_NAME} package.
The actual DAG definitions are in: ${SOURCE_DIR}/${rel_path}
"""

import sys
import os

# Add package root to Python path to enable imports from installed package
# Package is installed at: ${PACKAGE_ROOT}/${PACKAGE_NAME}
package_root = "${PACKAGE_ROOT}"
if package_root not in sys.path:
    sys.path.insert(0, package_root)

# Import all DAG objects from the package module
try:
    from ${import_module} import *
except ImportError as e:
    import logging
    logger = logging.getLogger(__name__)
    logger.error(f"Failed to import DAGs from ${import_module}: {e}")
    # Re-raise to make the error visible in Airflow
    raise
EOF
        
        CREATED_COUNT=$((CREATED_COUNT + 1))
        log_debug "  Created import script: ${dag_basename}.py (imports from ${import_module})"
    fi
done <<< "${DAG_FILES}"

log_info "✓ Created ${CREATED_COUNT} import script(s) in ${DEST_DIR}"

# List created import scripts
if [ "${CREATED_COUNT}" -gt 0 ]; then
    log_info "Import scripts created:"
    find "${DEST_DIR}" -maxdepth 1 -name "*.py" -type f -exec basename {} \; | sed 's/^/  - /'
fi
