#!/bin/bash
#
# Install Airflow DAGs from the installed trading_agent wheel to ../infra-platform/airflow/dags/
#
# This script extracts DAG files from the installed trading_agent package (wheel)
# to the infra-platform repository's Airflow DAGs directory where they will be loaded by Airflow.
#
# Each environment has its own wheel installation (trading_agent_dev, trading_agent_test, trading_agent_prod)
# with DAGs at {package}/src/.airflow-dags/
#
# Usage:
#   ./install-dags.sh [dev|test|staging|prod]
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

# Get environment from argument or default to dev
ENV="${1:-dev}"
# Map staging to test for directory naming
INSTALL_DIR_ENV="${ENV}"
if [ "${ENV}" = "staging" ]; then
    INSTALL_DIR_ENV="test"
fi

# Package name is always trading_agent (no suffix)
# But it's installed to environment-specific directories: trading_agent-dev/, trading_agent-test/, trading_agent-prod/
PACKAGE_NAME="trading_agent"
INSTALL_DIR_NAME="trading_agent-${INSTALL_DIR_ENV}"

# Destination directory
# If running in Docker/container, use /opt/airflow/dags
# Otherwise, use relative path from script location
if [ -d "/opt/airflow/dags" ]; then
    DEST_DIR="/opt/airflow/dags"
else
    DEST_DIR="${PROJECT_ROOT}/../infra-platform/airflow/dags"
fi

# Find the installed trading_agent package location
# The wheel structure shows src/.airflow-dags/ which will be at {install_dir}/trading_agent/src/.airflow-dags/ after installation
log_info "Locating installed ${PACKAGE_NAME} package in ${INSTALL_DIR_NAME}/ directory..."

# Try to find the installed package in environment-specific installation directory
# Structure: {install_dir_name}/trading_agent/src/.airflow-dags/
# e.g., trading_agent_dev/trading_agent/src/.airflow-dags/

# First, try to find trading_agent package and check if it's in an env-specific directory
TRADING_AGENT_PACKAGE_DIR=$(python3 -c "
import sys
import importlib.util
import os

package_name = '${PACKAGE_NAME}'
install_dir_name = '${INSTALL_DIR_NAME}'

try:
    # Try to import trading_agent package
    spec = importlib.util.find_spec(package_name)
    if spec and spec.origin:
        package_file = spec.origin
        package_dir = os.path.dirname(os.path.abspath(package_file))
        
        # Check if package is in an environment-specific directory
        # Path structure: .../trading_agent_dev/trading_agent/...
        if install_dir_name in package_dir:
            print(package_dir)
        else:
            print('')
    else:
        print('')
except Exception:
    print('')
" 2>/dev/null || echo "")

# Look for .airflow-dags directory in the installed package
# Based on the wheel structure: src/.airflow-dags/ becomes {install_dir}/trading_agent/src/.airflow-dags/ after installation
SOURCE_DIR=""

if [ -n "${TRADING_AGENT_PACKAGE_DIR}" ] && [ -d "${TRADING_AGENT_PACKAGE_DIR}" ]; then
    # Expected path: {install_dir}/trading_agent/src/.airflow-dags/
    POSSIBLE_PATH="${TRADING_AGENT_PACKAGE_DIR}/src/.airflow-dags"
    
    if [ -d "${POSSIBLE_PATH}" ]; then
        SOURCE_DIR="${POSSIBLE_PATH}"
        log_info "Found .airflow-dags at: ${SOURCE_DIR}"
    fi
fi

# If not found via import, search in site-packages for environment-specific installation directory
if [ -z "${SOURCE_DIR}" ]; then
    log_info "Searching for ${INSTALL_DIR_NAME}/${PACKAGE_NAME}/src/.airflow-dags in Python site-packages..."
    SOURCE_DIR=$(python3 -c "
import site
import os
install_dir_name = '${INSTALL_DIR_NAME}'
package_name = '${PACKAGE_NAME}'
for site_dir in site.getsitepackages():
    # Expected path: {install_dir}/{package}/src/.airflow-dags
    # e.g., site-packages/trading_agent-dev/trading_agent/src/.airflow-dags
    path = os.path.join(site_dir, install_dir_name, package_name, 'src', '.airflow-dags')
    if os.path.isdir(path):
        print(path)
        break
    # Also try at root of install_dir: site-packages/trading_agent-dev/src/.airflow-dags
    path2 = os.path.join(site_dir, install_dir_name, 'src', '.airflow-dags')
    if os.path.isdir(path2):
        print(path2)
        break
" 2>/dev/null || echo "")
fi

# Check if source directory was found
if [ -z "${SOURCE_DIR}" ] || [ ! -d "${SOURCE_DIR}" ]; then
    log_warn "Could not find .airflow-dags directory in installed ${PACKAGE_NAME} package"
    log_warn "Expected location:"
    log_warn "  - ${INSTALL_DIR_NAME}/${PACKAGE_NAME}/src/.airflow-dags/"
    log_warn "  - site-packages/${INSTALL_DIR_NAME}/${PACKAGE_NAME}/src/.airflow-dags/"
    log_warn ""
    log_warn "Please ensure:"
    log_warn "  1. trading_agent wheel is installed to ${INSTALL_DIR_NAME}/ directory"
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

log_info "Installing Airflow DAGs..."
log_info "  From: ${SOURCE_DIR}"
log_info "  To:   ${DEST_DIR}"

# Copy all Python files and related files from airflow-dags to ../infra-platform/airflow/dags
# Preserve directory structure
DAG_FILES=$(find "${SOURCE_DIR}" -type f \( -name "*.py" -o -name "*.md" -o -name "*.yaml" -o -name "*.yml" -o -name "*.json" \) 2>/dev/null)

if [ -z "${DAG_FILES}" ]; then
    log_warn "No DAG files found in ${SOURCE_DIR}"
    exit 0
fi

# Count files to copy
FILE_COUNT=$(echo "${DAG_FILES}" | wc -l | tr -d ' ')
log_info "Found ${FILE_COUNT} file(s) to install"

# Copy files, preserving directory structure
COPIED_COUNT=0
while IFS= read -r source_file; do
    if [ -n "${source_file}" ]; then
        # Get relative path from source directory
        rel_path="${source_file#${SOURCE_DIR}/}"
        
        # Create destination path
        dest_file="${DEST_DIR}/${rel_path}"
        dest_dir=$(dirname "${dest_file}")
        
        # Skip __init__.py if it already exists in destination (preserve original)
        if [ "${rel_path}" = "__init__.py" ] && [ -f "${dest_file}" ]; then
            log_debug "  Skipped: ${rel_path} (preserving existing file)"
            continue
        fi
        
        # Create destination directory if needed
        mkdir -p "${dest_dir}"
        
        # Copy file
        cp "${source_file}" "${dest_file}"
        COPIED_COUNT=$((COPIED_COUNT + 1))
        
        log_debug "  Copied: ${rel_path}"
    fi
done <<< "${DAG_FILES}"

log_info "✓ Installed ${COPIED_COUNT} file(s) to ${DEST_DIR}"

# List installed DAGs
PYTHON_DAGS=$(find "${DEST_DIR}" -maxdepth 1 -name "*.py" -type f 2>/dev/null | wc -l | tr -d ' ')
if [ "${PYTHON_DAGS}" -gt 0 ]; then
    log_info "Python DAG files in destination:"
    find "${DEST_DIR}" -maxdepth 1 -name "*.py" -type f -exec basename {} \; | sed 's/^/  - /'
fi
