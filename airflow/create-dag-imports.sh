#!/bin/bash
#
# Create DAG import scripts after wheel installation
#
# This script goes into airflow/{env}/{package_name}/.airflow_dags (or .airflow-dags)
# and creates import scripts in airflow/{env}/dags/ that import the DAGs from the installed package.
#
# Usage:
#   ./create-dag-imports.sh [dev|test|staging|prod] [package_name]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
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

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Get environment and package name from arguments
ENV="${1:-dev}"
PACKAGE_NAME="${2:-trading_agent}"

# Map staging to test for directory naming
INSTALL_DIR_ENV="${ENV}"
if [ "${ENV}" = "staging" ]; then
    INSTALL_DIR_ENV="test"
fi

# Determine paths
# If running in Docker/container, use /opt/airflow paths
# Otherwise, use local paths
if [ -d "/opt/airflow/dags" ]; then
    # Inside Docker container
    WORKSPACE_ROOT="/opt/airflow/workspace"
    DAGS_DIR="/opt/airflow/dags"
else
    # Local filesystem
    WORKSPACE_ROOT="${SCRIPT_DIR}/${INSTALL_DIR_ENV}/workspace"
    DAGS_DIR="${SCRIPT_DIR}/${INSTALL_DIR_ENV}/dags"
fi

# Source directory: DAGs are in airflow/{env}/workspace/{package_name}-workspace/{package_name}/_airflow_dags_
SOURCE_DIR="${WORKSPACE_ROOT}/${PACKAGE_NAME}-workspace/${PACKAGE_NAME}/_airflow_dags_"

# Check for fallback location: mounted source code
# Try mounted source code location: /workspace/trading-agent/src/_airflow_dags_ (inside container)
# or TradingPythonAgent/src/_airflow_dags_ (on host)
FALLBACK_DIR=""
if [ -d "/workspace/trading-agent/src/_airflow_dags_" ]; then
    # Inside Docker container
    FALLBACK_DIR="/workspace/trading-agent/src/_airflow_dags_"
elif [ -d "${SOURCE_PARENT}/src/_airflow_dags_" ]; then
    # On host filesystem
    FALLBACK_DIR="${SOURCE_PARENT}/src/_airflow_dags_"
fi

# Use fallback if installed wheel doesn't exist, is empty, or has fewer DAGs than source
WHEEL_DAG_COUNT=0
FALLBACK_DAG_COUNT=0
if [ -d "${SOURCE_DIR}" ]; then
    WHEEL_DAG_COUNT=$(ls -A "${SOURCE_DIR}"/*.py 2>/dev/null | grep -v __init__ | grep -v __pycache__ | wc -l | tr -d ' ')
fi
if [ -n "${FALLBACK_DIR}" ] && [ -d "${FALLBACK_DIR}" ]; then
    FALLBACK_DAG_COUNT=$(ls -A "${FALLBACK_DIR}"/*.py 2>/dev/null | grep -v __init__ | grep -v __pycache__ | wc -l | tr -d ' ')
fi

# Use fallback if it has more DAGs than the installed wheel
if [ -n "${FALLBACK_DIR}" ] && [ -d "${FALLBACK_DIR}" ] && [ "${FALLBACK_DAG_COUNT}" -gt "${WHEEL_DAG_COUNT}" ]; then
    log_info "Using fallback DAG source (${FALLBACK_DAG_COUNT} DAGs vs ${WHEEL_DAG_COUNT} in wheel): ${FALLBACK_DIR}"
    SOURCE_DIR="${FALLBACK_DIR}"
elif [ ! -d "${SOURCE_DIR}" ] || [ "${WHEEL_DAG_COUNT}" -eq 0 ]; then
    # Fallback: if DAGs not in installed wheel or directory is empty, try mounted source code location
    if [ -n "${FALLBACK_DIR}" ] && [ -d "${FALLBACK_DIR}" ] && [ "${FALLBACK_DAG_COUNT}" -gt 0 ]; then
        log_warn "DAGs not found in installed wheel, using fallback: ${FALLBACK_DIR}"
        SOURCE_DIR="${FALLBACK_DIR}"
    else
        log_error "Could not find _airflow_dags_ directory"
        log_error "Checked locations:"
        log_error "  1. ${WORKSPACE_ROOT}/${PACKAGE_NAME}-workspace/${PACKAGE_NAME}/_airflow_dags_ (${WHEEL_DAG_COUNT} DAGs)"
        log_error "  2. /workspace/trading-agent/src/_airflow_dags_ (container, ${FALLBACK_DAG_COUNT} DAGs)"
        log_error "  3. ${SOURCE_PARENT}/src/_airflow_dags_ (host, ${FALLBACK_DAG_COUNT} DAGs)"
        log_error ""
        log_error "Please ensure:"
        log_error "  1. ${PACKAGE_NAME} wheel is installed with all DAGs, OR"
        log_error "  2. TradingPythonAgent source is mounted and contains src/_airflow_dags_/"
        exit 1
    fi
fi

log_info "Found DAGs directory: ${SOURCE_DIR}"

# Check if source directory is empty
if [ -z "$(ls -A "${SOURCE_DIR}"/*.py 2>/dev/null | grep -v __init__ | grep -v __pycache__)" ]; then
    log_warn "Source directory is empty: ${SOURCE_DIR}"
    log_info "No DAGs to create import scripts for"
    exit 0
fi

# Create destination directory if it doesn't exist
mkdir -p "${DAGS_DIR}"

log_info "Creating DAG import scripts..."
log_info "  DAG source: ${SOURCE_DIR}"
log_info "  Import scripts: ${DAGS_DIR}"

# Find all Python DAG files in the source directory (excluding __init__.py and __pycache__)
DAG_FILES=$(find "${SOURCE_DIR}" -type f -name "*.py" ! -name "__init__.py" ! -path "*/__pycache__/*" 2>/dev/null)

if [ -z "${DAG_FILES}" ]; then
    log_warn "No Python DAG files found in ${SOURCE_DIR}"
    exit 0
fi

# Count files to import
FILE_COUNT=$(echo "${DAG_FILES}" | grep -v '^$' | wc -l | tr -d ' ')
log_info "Found ${FILE_COUNT} DAG file(s) to import"

# Create a single import script that imports all DAGs
# Script name: {package_name}_dags.py
IMPORT_SCRIPT="${DAGS_DIR}/${PACKAGE_NAME}_dags.py"

log_info "Creating import script: $(basename "${IMPORT_SCRIPT}")"

# Start building the import script
cat > "${IMPORT_SCRIPT}" <<EOF
#!/usr/bin/env python3
"""
Airflow DAG import script for ${PACKAGE_NAME}

This file imports all DAGs from the installed ${PACKAGE_NAME} package.
The actual DAG definitions are in: ${SOURCE_DIR}

Generated by create-dag-imports.sh
"""

import sys
import os

# Load .env file before importing anything that might use config.py
# The .env file should be at workspace root (copied during wheel installation)
try:
    from dotenv import load_dotenv
    workspace_root = "${WORKSPACE_ROOT}/${PACKAGE_NAME}-workspace"
    airflow_env = os.getenv('AIRFLOW_ENV', '${ENV}')
    # Map staging to staging (no change needed for .env file name)
    env_file_name = 'staging' if airflow_env == 'staging' else airflow_env
    env_file = os.path.join(workspace_root, f'.env.{env_file_name}')
    if os.path.exists(env_file):
        load_dotenv(env_file, override=True)
    else:
        # Fallback: try mounted location
        mounted_env_file = f"/workspace/trading-agent/.env.{env_file_name}"
        if os.path.exists(mounted_env_file):
            load_dotenv(mounted_env_file, override=True)
except ImportError:
    # python-dotenv not available, continue without loading .env
    pass
except Exception as e:
    # If loading fails, continue anyway
    import logging
    logging.getLogger(__name__).warning(f"Failed to load .env file: {e}")

# Add workspace root to Python path to enable imports from installed package
# Package is installed at: ${WORKSPACE_ROOT}/${PACKAGE_NAME}-workspace/${PACKAGE_NAME}
# Dependencies are at: ${WORKSPACE_ROOT}/${PACKAGE_NAME}-workspace/
workspace_root = "${WORKSPACE_ROOT}/${PACKAGE_NAME}-workspace"
if workspace_root and workspace_root not in sys.path:
    sys.path.insert(0, workspace_root)

# Add source code path so DAGs can import from fundamentals, macro, etc.
# (TradingPythonAgent source is mounted at /workspace/trading-agent)
# The source has src/fundamentals/, but DAGs import trading_agent.fundamentals
# We create a trading_agent namespace that points to src
import os
import types
source_parent = "/workspace/trading-agent"
if os.path.exists(source_parent) and source_parent not in sys.path:
    sys.path.insert(0, source_parent)
    
    # Create trading_agent namespace package that points to src
    # This allows "from trading_agent.fundamentals" to work
    try:
        import src
        trading_agent_module = types.ModuleType('trading_agent')
        trading_agent_module.__path__ = [os.path.join(source_parent, 'src')]
        # Make src's submodules accessible via trading_agent
        for attr_name in dir(src):
            if not attr_name.startswith('_'):
                try:
                    attr = getattr(src, attr_name)
                    if hasattr(attr, '__module__') or isinstance(attr, types.ModuleType):
                        setattr(trading_agent_module, attr_name, attr)
                except:
                    pass
        sys.modules['trading_agent'] = trading_agent_module
    except Exception:
        # Fallback: just add src to path
        source_path = os.path.join(source_parent, 'src')
        if source_path not in sys.path:
            sys.path.insert(0, source_path)

# Add /opt/airflow to Python path so 'operators' package can be imported
# (operators is at /opt/airflow/operators, so we need the parent directory)
airflow_root = "/opt/airflow"
if airflow_root and airflow_root not in sys.path:
    sys.path.insert(0, airflow_root)

# Set up storage path for DAG file writes
# Storage is mounted at /workspace/storage/{env}/ and maps to TradingPythonAgent/storage/{env}/
# DAGs should write to this location instead of source code directories
import os
airflow_env = os.getenv('AIRFLOW_ENV', '${ENV}')
# Map staging to test for storage directory naming
storage_env = 'test' if airflow_env == 'staging' else airflow_env
storage_root = f"/workspace/storage/{storage_env}"
if os.path.exists(storage_root):
    # Set environment variable so DAGs can access storage path
    os.environ['TRADING_AGENT_STORAGE'] = storage_root
    # Also make it available via trading_agent module
    # This allows DAGs to use: from trading_agent import STORAGE_PATH
    if 'trading_agent' in sys.modules:
        trading_agent_module = sys.modules['trading_agent']
        trading_agent_module.STORAGE_PATH = storage_root

# Import all DAG objects from the package module
# DAGs are in {package_name}/_airflow_dags_/, which Python imports as {package_name}._airflow_dags_

EOF

# Determine if we're using fallback location (mounted source code)
# If SOURCE_DIR contains "/workspace/trading-agent" or "/src/_airflow_dags_", we're using fallback
USE_FALLBACK=false
if echo "${SOURCE_DIR}" | grep -q "/workspace/trading-agent\|/src/_airflow_dags_\|TradingPythonAgent"; then
    USE_FALLBACK=true
    # For fallback, DAGs are directly in SOURCE_DIR
    DAG_BASE_PATH="${SOURCE_DIR}"
else
    # For installed wheel, DAGs are in workspace_root/package_name/_airflow_dags_
    DAG_BASE_PATH="${WORKSPACE_ROOT}/${PACKAGE_NAME}-workspace/${PACKAGE_NAME}/_airflow_dags_"
fi

# Process each DAG file and add imports
IMPORT_COUNT=0
while IFS= read -r dag_file; do
    if [ -z "${dag_file}" ]; then
        continue
    fi
    
    # Get relative path from source directory
    rel_path="${dag_file#${SOURCE_DIR}/}"
    
    # Get base filename without extension (e.g., "my_dag.py" -> "my_dag")
    dag_basename=$(basename "${rel_path}" .py)
    
    # Get directory path (empty if DAG is directly in _airflow_dags_, or "subdir" if in subdirectory)
    rel_dir=$(dirname "${rel_path}")
    
    # Build import path
    # DAGs are in airflow/{env}/{package_name}/_airflow_dags_/
    # Python imports this as: {package_name}._airflow_dags_.{module}
    DAG_MODULE_NAME="_airflow_dags_"
    
    if [ "${rel_dir}" = "." ] || [ -z "${rel_dir}" ]; then
        # DAG is directly in the DAGs directory
        import_module="${PACKAGE_NAME}.${DAG_MODULE_NAME}.${dag_basename}"
    else
        # DAG is in a subdirectory (e.g., _airflow_dags/subdir/my_dag.py)
        # Replace slashes with dots for Python import path
        rel_dir_dots=$(echo "${rel_dir}" | tr '/' '.')
        import_module="${PACKAGE_NAME}.${DAG_MODULE_NAME}.${rel_dir_dots}.${dag_basename}"
    fi
    
    # Add import statement to the script
    # For EDGAR DAGs, use direct file import to avoid SQLAlchemy conflicts with workspace dependencies
    # For other DAGs, use standard import
    if echo "${dag_basename}" | grep -q "^edgar"; then
        # EDGAR DAGs: Import directly from file to avoid SQLAlchemy conflicts
        # Use the actual file path (either from fallback or workspace)
        cat >> "${IMPORT_SCRIPT}" <<EOF
# Import EDGAR DAG from ${rel_path} (direct file import to avoid SQLAlchemy conflicts)
try:
    import importlib.util
    # Use actual DAG file path (workspace or fallback location)
    dag_file_path = "${dag_file}"
    if not os.path.exists(dag_file_path):
        # Fallback: try workspace location
        dag_file_path = os.path.join(workspace_root, "${PACKAGE_NAME}", "_airflow_dags_", "${rel_path}")
    if os.path.exists(dag_file_path):
        spec = importlib.util.spec_from_file_location("${import_module}", dag_file_path)
        if spec and spec.loader:
            module = importlib.util.module_from_spec(spec)
            # Temporarily remove workspace from sys.path to avoid SQLAlchemy conflict
            workspace_in_path = workspace_root in sys.path
            if workspace_in_path:
                sys.path.remove(workspace_root)
            try:
                spec.loader.exec_module(module)
                if hasattr(module, 'dag') and module.dag:
                    globals()[module.dag.dag_id] = module.dag
            finally:
                # Restore workspace to sys.path
                if workspace_in_path and workspace_root not in sys.path:
                    sys.path.insert(0, workspace_root)
    else:
        import logging
        logger = logging.getLogger(__name__)
        logger.warning(f"DAG file not found: {dag_file_path}")
except Exception as e:
    import logging
    logger = logging.getLogger(__name__)
    logger.warning(f"Failed to import/register DAG from ${dag_basename}: {e}")
    # Continue with other imports even if one fails

EOF
    else
        # Other DAGs: Use standard import
        cat >> "${IMPORT_SCRIPT}" <<EOF
# Import DAG from ${rel_path}
try:
    import ${import_module} as module
    # Register the DAG in global namespace using its dag_id as the key
    globals()[module.dag.dag_id] = module.dag
except Exception as e:
    import logging
    logger = logging.getLogger(__name__)
    logger.warning(f"Failed to import/register DAG from ${import_module}: {e}")
    # Continue with other imports even if one fails

EOF
    fi
    
    IMPORT_COUNT=$((IMPORT_COUNT + 1))
    log_debug "  Added import for: ${dag_basename} (from ${import_module})"
done <<< "${DAG_FILES}"

chmod +x "${IMPORT_SCRIPT}"

log_info "✓ Created import script: $(basename "${IMPORT_SCRIPT}") with ${IMPORT_COUNT} import(s)"

log_info "Done!"
