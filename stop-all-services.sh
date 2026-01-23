#!/bin/bash

# Shutdown script to stop all trading agent services
# This script is the counterpart to start-all-services.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Log file
LOG_FILE="$HOME/.trading-agent-services.log"
PROJECT_ROOT="/Users/Snake91/CursorProjects/infra-platform"
DOCKER_COMPOSE_DIR="$PROJECT_ROOT/docker"
KUBECTL_CONTEXT="kind-trading-cluster"

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=== Stopping Trading Agent Services ==="

# Stop Kubernetes Dashboard port forwarding
log "${YELLOW}Stopping Kubernetes Dashboard port forwarding...${NC}"
if pgrep -f "kubectl port-forward.*kubernetes-dashboard.*8001" > /dev/null; then
    pkill -f "kubectl port-forward.*kubernetes-dashboard.*8001" || true
    log "${GREEN}✓ Kubernetes Dashboard port forwarding stopped${NC}"
else
    log "${YELLOW}No Kubernetes Dashboard port forwarding found${NC}"
fi

# Stop any kubectl proxy processes
log "${YELLOW}Stopping kubectl proxy processes...${NC}"
if pgrep -f "kubectl proxy" > /dev/null; then
    pkill -f "kubectl proxy" || true
    log "${GREEN}✓ kubectl proxy processes stopped${NC}"
else
    log "${YELLOW}No kubectl proxy processes found${NC}"
fi

# Stop Docker Compose services
log "${YELLOW}Stopping Docker Compose services...${NC}"
cd "$DOCKER_COMPOSE_DIR"

# Stop application services first (if any)
if [ -f "docker-compose.yml" ]; then
    if docker-compose -f docker-compose.yml down >> "$LOG_FILE" 2>&1; then
        log "${GREEN}✓ Application services stopped${NC}"
    else
        log "${YELLOW}Warning: Failed to stop application services (may not exist)${NC}"
    fi
fi

# Stop infra-platform services
if docker-compose -f docker-compose.infra-platform.yml down >> "$LOG_FILE" 2>&1; then
    log "${GREEN}✓ Docker Compose services stopped${NC}"
else
    log "${RED}ERROR: Failed to stop Docker Compose services${NC}"
    exit 1
fi

# Summary
log "${GREEN}=== Service Shutdown Complete ===${NC}"
log "${GREEN}All services have been stopped${NC}"
log ""
log "Note: Kubernetes cluster 'trading-cluster' is still running."
log "To delete the cluster, run: kind delete cluster --name trading-cluster"
log ""
log "Log file: $LOG_FILE"
