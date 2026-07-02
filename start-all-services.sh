#!/bin/bash

# Startup script to launch all trading agent services
# This script is designed to be run at Mac startup via LaunchAgent

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

log "=== Starting Trading Agent Services ==="

# Check if Docker is running; if not, try to start it (macOS: open Docker Desktop)
if ! docker info > /dev/null 2>&1; then
    log "${YELLOW}Docker is not running. Attempting to start Docker Desktop...${NC}"
    if [[ "$(uname)" == "Darwin" ]]; then
        if open -a Docker 2>/dev/null; then
            log "${YELLOW}Waiting for Docker to become ready (up to 120s)...${NC}"
            for i in $(seq 1 120); do
                if docker info > /dev/null 2>&1; then
                    log "${GREEN}✓ Docker is running${NC}"
                    break
                fi
                if [ $i -eq 120 ]; then
                    log "${RED}ERROR: Docker did not start within 120 seconds. Please start Docker Desktop manually.${NC}"
                    exit 1
                fi
                sleep 1
            done
        else
            log "${RED}ERROR: Could not start Docker Desktop. Please start it manually.${NC}"
            exit 1
        fi
    else
        log "${RED}ERROR: Docker is not running. Please start Docker manually.${NC}"
        exit 1
    fi
fi

# Start Docker Compose services (use infra-platform compose file)
log "${YELLOW}Starting Docker Compose services...${NC}"
cd "$DOCKER_COMPOSE_DIR"
COMPOSE_FILE="docker-compose.infra-platform.yml"
if docker compose -f "$COMPOSE_FILE" up -d >> "$LOG_FILE" 2>&1; then
    log "${GREEN}✓ Docker Compose services started${NC}"
else
    log "${RED}ERROR: Failed to start Docker Compose services${NC}"
    exit 1
fi

# Wait a bit for services to initialize
sleep 5

# Check if Kubernetes cluster exists and is running
log "${YELLOW}Checking Kubernetes cluster...${NC}"
if kind get clusters | grep -q "trading-cluster"; then
    log "${GREEN}✓ Kubernetes cluster 'trading-cluster' exists${NC}"
    
    # Check if cluster is accessible
    if kubectl cluster-info --context "$KUBECTL_CONTEXT" > /dev/null 2>&1; then
        log "${GREEN}✓ Kubernetes cluster is accessible${NC}"
    else
        log "${YELLOW}Warning: Kubernetes cluster exists but may not be fully ready${NC}"
    fi
else
    log "${YELLOW}Warning: Kubernetes cluster 'trading-cluster' not found${NC}"
    log "${YELLOW}You may need to create it manually: kind create cluster --name trading-cluster${NC}"
fi

# Jenkins is now running in Docker Compose (no Kubernetes deployment needed)
log "${GREEN}✓ Jenkins is managed by Docker Compose${NC}"

# Kubernetes UI port-forwards run in Docker Compose (k8s-port-forwards sidecar).
log "${YELLOW}Ensuring k8s port-forward sidecars (dashboard + kubeflow)...${NC}"
cd "$DOCKER_COMPOSE_DIR"
docker compose -f "$COMPOSE_FILE" up -d kubernetes-dashboard-port-forward kubeflow-port-forward pma-dashboard-proxy >> "$LOG_FILE" 2>&1 || true
log "${GREEN}✓ k8s UI port-forwards managed by compose sidecars${NC}"

# Kubeflow Pipelines: install in background if missing (do not block dashboard access)
log "${YELLOW}Checking Kubeflow Pipelines install...${NC}"
if kubectl config get-contexts -o name 2>/dev/null | grep -qx "${KUBECTL_CONTEXT}"; then
    if ! kubectl get svc ml-pipeline-ui -n kubeflow --context "$KUBECTL_CONTEXT" > /dev/null 2>&1; then
        log "${YELLOW}Kubeflow not installed; starting install in background (10+ min)...${NC}"
        nohup bash "${PROJECT_ROOT}/kubernetes/install-kubeflow-pipelines.sh" >> "$LOG_FILE" 2>&1 &
        log "${GREEN}✓ Kubeflow install started in background; compose sidecar will port-forward when ready${NC}"
    else
        log "${GREEN}✓ Kubeflow Pipelines already installed${NC}"
    fi
else
    log "${YELLOW}Warning: ${KUBECTL_CONTEXT} not found; skip Kubeflow${NC}"
fi

# Ensure dashboard RBAC for skip-login (kubernetes-dashboard SA needs cluster-admin)
if kubectl get namespace kubernetes-dashboard --context "$KUBECTL_CONTEXT" > /dev/null 2>&1; then
    kubectl apply -f "${PROJECT_ROOT}/kubernetes/kubernetes-dashboard-rbac.yaml" --context "$KUBECTL_CONTEXT" >> "$LOG_FILE" 2>&1 || true
fi

# Wait a bit for dashboard to be ready, then generate and copy token
log "${YELLOW}Generating Kubernetes Dashboard token...${NC}"
sleep 3
if kubectl get serviceaccount admin-user -n kubernetes-dashboard --context "$KUBECTL_CONTEXT" > /dev/null 2>&1; then
    DASHBOARD_TOKEN=$(kubectl create token admin-user -n kubernetes-dashboard --context "$KUBECTL_CONTEXT" --duration=8760h 2>/dev/null)
    if [ -n "$DASHBOARD_TOKEN" ]; then
        if echo "$DASHBOARD_TOKEN" | pbcopy 2>/dev/null; then
            log "${GREEN}✓ Kubernetes Dashboard token generated and copied to clipboard${NC}"
            log "${GREEN}  Token is ready to paste (Cmd+V) when accessing https://localhost:8001${NC}"
        else
            log "${YELLOW}Warning: Token generated but could not copy to clipboard (pbcopy failed)${NC}"
            log "${YELLOW}  You can get the token manually with:${NC}"
            log "${YELLOW}  kubectl create token admin-user -n kubernetes-dashboard --context $KUBECTL_CONTEXT${NC}"
        fi
    else
        log "${YELLOW}Warning: Could not generate dashboard token${NC}"
    fi
else
    log "${YELLOW}Warning: admin-user service account not found. Token generation skipped.${NC}"
fi

# Summary
log "${GREEN}=== Service Startup Complete ===${NC}"
log "${GREEN}Services available at:${NC}"
log "  - Airflow: http://airflow.local.dev.info (direct: http://localhost:8082)"
log "  - Jenkins: http://localhost:8081"
log "  - Grafana: http://localhost:3000"
log "  - MLflow dev:  http://localhost:55000  (http://mlflow.local.dev.info)"
log "  - MLflow test: http://localhost:55001  (http://mlflow.local.test.info)"
log "  - MLflow prod: http://localhost:55002  (http://mlflow.local.prod.info)"
log "  - Feast dev:   http://localhost:8890  (http://feast.local.dev.info)"
log "  - Feast test:  http://localhost:8891  (http://feast.local.test.info)"
log "  - Feast prod:  http://localhost:8892  (http://feast.local.prod.info)"
log "  - dbt docs dev:  http://localhost:8880  (http://dbt.local.dev.info)"
log "  - dbt docs test: http://localhost:8881  (http://dbt.local.test.info)"
log "  - dbt docs prod: http://localhost:8882  (http://dbt.local.prod.info)"
log "  - Prometheus: http://localhost:9090"
log "  - Kubernetes Dashboard: https://localhost:8001"
log "  - Kubeflow Pipelines: http://kubeflow.local.info (direct: http://localhost:8088)"
log "  - PostgreSQL: via nginx 54324–54326 (postgres.{dev|test|prod}.local.info)"
log "  - Doltgres: via nginx 54334–54336 (doltgres.{dev|test|prod}.local.info; see doltgres/README.md)"
log "  - dbt: docker exec -it dbt-dev dbt run (feature models → feast schema; docs at http://dbt.local.dev.info)"
log "  - Redis: localhost:6379"
log "  - RedisInsight: http://localhost:5540 (Redis web GUI)"
log "  - NATS: localhost:4222 (client), localhost:8222 (monitoring)"
log "  - OpenProject: http://localhost:8086 (Project Management - replacement for Jira)"
log ""
log "Log file: $LOG_FILE"

