#!/bin/bash
#
# Copy wheels from dist/ to airflow/wheels/
# This script helps sync built wheels to the Airflow wheels directory
#
# Usage:
#   ./install-wheel.sh [dev|staging|prod]
#
# If no environment is specified, automatically detects from git branch
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detect TradingPythonAgent root location
# Priority: 1) Docker mount path, 2) Environment variable, 3) Relative path, 4) Absolute path
if [ -d "/workspace/trading-agent" ]; then
    # Running in Docker/Jenkins - use mounted path
    TRADING_AGENT_ROOT="/workspace/trading-agent"
elif [ -n "${TRADING_AGENT_ROOT:-}" ] && [ -d "${TRADING_AGENT_ROOT}" ]; then
    # Use environment variable if set
    TRADING_AGENT_ROOT="${TRADING_AGENT_ROOT}"
elif [ -d "${SCRIPT_DIR}/../../TradingPythonAgent" ]; then
    # Relative path from infra-platform/airflow to TradingPythonAgent
    TRADING_AGENT_ROOT="$(cd "${SCRIPT_DIR}/../../TradingPythonAgent" && pwd)"
elif [ -d "/Users/Snake91/CursorProjects/TradingPythonAgent" ]; then
    # Fallback to absolute path (local development)
    TRADING_AGENT_ROOT="/Users/Snake91/CursorProjects/TradingPythonAgent"
else
    log_warn "Could not find TradingPythonAgent directory"
    log_warn "Please set TRADING_AGENT_ROOT environment variable or mount it in Docker"
    exit 1
fi

PROJECT_ROOT="${TRADING_AGENT_ROOT}"

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

# Function to get current git branch
get_git_branch() {
    local branch
    if command -v git &> /dev/null; then
        branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
        if [ -n "$branch" ]; then
            echo "$branch"
            return 0
        fi
    fi
    # Fallback to environment variable
    echo "${GIT_BRANCH:-${BRANCH_NAME:-}}"
}

# Function to convert to lowercase (bash 3 compatible)
to_lower() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

# Function to determine environment from branch
get_env_from_branch() {
    local branch="$1"
    local branch_lower=$(to_lower "$branch")
    
    # Check for staging branch
    if [[ "$branch_lower" == "staging" ]]; then
        echo "staging"
        return 0
    fi
    
    # Check for main/master branch
    if [[ "$branch_lower" == "main" || "$branch_lower" == "master" ]]; then
        echo "prod"
        return 0
    fi
    
    # Check for dev branches (dev/* or starts with dev)
    if [[ "$branch_lower" =~ ^dev/ ]] || [[ "$branch_lower" =~ ^dev ]]; then
        echo "dev"
        return 0
    fi
    
    # Default to dev for any other branch
    echo "dev"
}

# Get environment from argument or auto-detect from branch
if [ $# -gt 0 ]; then
    ENV="${1}"
    ENV="${ENV,,}"  # Convert to lowercase
    
    # Validate environment
    if [[ ! "$ENV" =~ ^(dev|staging|prod)$ ]]; then
        log_warn "Invalid environment: $ENV. Auto-detecting from branch..."
        ENV=""
    fi
else
    ENV=""
fi

# Auto-detect environment from branch if not specified
if [ -z "$ENV" ]; then
    CURRENT_BRANCH=$(get_git_branch)
    if [ -n "$CURRENT_BRANCH" ]; then
        ENV=$(get_env_from_branch "$CURRENT_BRANCH")
        log_info "Auto-detected environment from branch '$CURRENT_BRANCH': $ENV"
    else
        log_warn "Could not determine git branch. Defaulting to 'dev'"
        ENV="dev"
    fi
fi

# Create environment-specific wheels directory if it doesn't exist
# Map staging to test for directory naming consistency
WHEELS_ENV="${ENV}"
if [ "${ENV}" = "staging" ]; then
    WHEELS_ENV="test"
fi
WHEELS_DIR="${SCRIPT_DIR}/wheels-${WHEELS_ENV}"
mkdir -p "${WHEELS_DIR}"

# Find the latest wheel for this environment
# Note: Wheels can be named with hyphens or underscores
# trading_agent-dev-*.whl or trading_agent_dev-*.whl
WHEEL_FILE=$(find "${PROJECT_ROOT}/dist" -name "trading_agent_${ENV}-*.whl" -o -name "trading_agent-${ENV}-*.whl" 2>/dev/null | sort -V | tail -n 1)

if [ -z "${WHEEL_FILE}" ]; then
    log_warn "No wheel found for environment '${ENV}' in ${PROJECT_ROOT}/dist/"
    log_warn "Please build the wheel first: ./build-wheel.sh ${ENV}"
    exit 1
fi

# Copy wheel to Airflow wheels directory
WHEEL_NAME=$(basename "${WHEEL_FILE}")
TARGET="${WHEELS_DIR}/${WHEEL_NAME}"

log_info "Copying wheel for environment: ${ENV}"
log_info "  From: ${WHEEL_FILE}"
log_info "  To:   ${TARGET}"

cp "${WHEEL_FILE}" "${TARGET}"

log_info "✓ Wheel installed: ${WHEEL_NAME}"
log_info "  Airflow will install this wheel on startup"

# List all wheels in the directory
log_info "Available wheels in ${WHEELS_DIR}:"
ls -lh "${WHEELS_DIR}"/trading_agent_*.whl 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}' || log_warn "  No wheels found"
