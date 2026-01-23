# Docker Configuration

This folder contains Docker Compose configurations for infrastructure and application services.

## Files

- **`docker-compose.infra-platform.yml`**: Infrastructure services Docker Compose configuration
  - Defines all infrastructure services: Grafana, Prometheus, MLflow, Airflow (dev/test/prod), PostgreSQL, Redis, Jenkins
  - Configures networking and volumes
  - Sets up service dependencies
  - **Use this for infrastructure deployment**

- **`docker-compose.yml`**: Application services Docker Compose configuration
  - For application-specific services (future use)
  - Currently minimal, ready for application services
  - **Use this for application-specific services**

- **`docker-compose.override.yml.example`**: Example override file
  - Template for custom configurations
  - Copy to `docker-compose.override.yml` to use

- **`DOCKER_SETUP.md`**: Detailed Docker setup documentation
  - Service configuration
  - Troubleshooting guide
  - Production considerations

- **`DOCKER_START.md`**: Quick guide for starting Docker
  - How to start Docker daemon
  - Verification steps
  - Common issues

## Quick Start

### Start Services

```bash
# From .ops/.docker directory (recommended - starts both infra and app services)
./start-docker-monitoring.sh

# Or manually start infrastructure services
docker-compose -f docker-compose.infra-platform.yml up -d

# Start application services (if any)
docker-compose -f docker-compose.yml up -d
```

### Stop Services

```bash
# From .ops/.docker directory (stops both infra and app services)
./stop-docker-monitoring.sh

# Or manually stop services
docker-compose -f docker-compose.infra-platform.yml down
docker-compose -f docker-compose.yml down
```

## Services

### Grafana
- **Port**: 3000
- **URL**: 
  - Direct: http://localhost:3000
  - Via alias: http://grafana.local.info (requires `/etc/hosts` entry and nginx proxy)
- **Credentials**: admin/admin
- **Volumes**: 
  - `../grafana/provisioning` → Auto-configures datasources and dashboards
  - `../grafana_dashboards` → Dashboard JSON files

### Prometheus
- **Port**: 9090
- **URL**: 
  - Direct: http://localhost:9090
  - Via alias: http://prometheus.local.info (requires `/etc/hosts` entry and nginx proxy)
- **Config**: `../prometheus/prometheus.yml`
- **Data**: Stored in Docker volume `prometheus-data`

### MLflow
- **Port**: 5000 (exposed as 55000)
- **URL**: 
  - Direct: http://localhost:55000
  - Via alias: http://mlflow.local.info (requires `/etc/hosts` entry and nginx proxy)
- **Backend**: SQLite (default) or PostgreSQL (configurable)
- **Data**: Stored in Docker volume `mlflow-data`

### Airflow
- **Port**: 8080 (dev: 8082, test: 8083, prod: 8084)
- **URL**: 
  - DEV: 
    - Direct: http://localhost:8082 (admin/2014)
    - Via alias: http://airflow.local.dev.info (requires `/etc/hosts` entry and nginx proxy)
  - TEST: 
    - Direct: http://localhost:8083 (admin/2014)
    - Via alias: http://airflow.local.test.info (requires `/etc/hosts` entry and nginx proxy)
  - PROD: 
    - Direct: http://localhost:8084 (admin/2014)
    - Via alias: http://airflow.local.prod.info (requires `/etc/hosts` entry and nginx proxy)
- **Home (in container)**: `/opt/airflow`
- **DAGs folder (in container)**: `/opt/airflow/dags` (mapped from `airflow/dags`)

See `airflow/QUICK_START.md` for Airflow environment variables, admin user, and authentication details.

### Kubernetes Dashboard
- **Part of infra-platform infrastructure** (managed via kind cluster)
- **URL**: 
  - Direct: Via `kubectl proxy` (typically http://localhost:8001)
  - Via alias: http://kubernetes-dashboard.local.info (requires `/etc/hosts` entry, nginx proxy, and `kubectl proxy --port=8001` running)
- **Setup**: Run `kubernetes/start-kubernetes.sh` to create kind cluster and install dashboard
- **Documentation**: See `kubernetes/DASHBOARD_ACCESS.md` for access details

### Kubeflow Pipelines UI
- **Part of infra-platform infrastructure** (managed via kind cluster)
- **URL**: 
  - Direct: Via `kubectl port-forward` (typically http://localhost:8081)
  - Via alias: http://kubeflow.local.info (requires `/etc/hosts` entry, nginx proxy, and `kubectl port-forward -n kubeflow svc/ml-pipeline-ui 8081:80` running)
- **Setup**: Install Kubeflow Pipelines in Kubernetes cluster (see `kubernetes/QUICK_START.md`)
- **Note**: Requires port-forward to be running for nginx proxy to work

### Portainer (Docker Management UI)
- **Port**: 9000
- **URL**: 
  - Direct: http://localhost:9000
  - Via alias: http://portainer.local.info (requires `/etc/hosts` entry and nginx proxy)
- **Credentials**: Set on first access
- **Features**: Web interface for managing Docker containers, images, volumes, networks, and stacks

### Jenkins
- **Port**: 8081 (direct access, routed via nginx on port 80)
- **URL**: 
  - Direct: http://localhost:8081
  - Via alias: http://jenkins.local.info (requires `/etc/hosts` entry and nginx proxy)
- **Credentials**: Configured in Jenkins UI
- **Has kubectl/kind tools** for Kubernetes cluster management

## Domain Name Setup

All services are accessible via domain names through nginx-proxy on port 80. To use domain names:

### 1. Add all domain URLs to `/etc/hosts`:

```bash
sudo sh -c 'cat >> /etc/hosts << EOF

# Infrastructure Platform Services
127.0.0.1 jenkins.local.info
127.0.0.1 airflow.local.dev.info airflow.local.test.info airflow.local.prod.info
127.0.0.1 grafana.local.info
127.0.0.1 prometheus.local.info
127.0.0.1 redisinsight.local.info
127.0.0.1 nats.local.info
127.0.0.1 mlflow.local.info
127.0.0.1 kubernetes-dashboard.local.info
127.0.0.1 kubeflow.local.info
127.0.0.1 portainer.local.info
EOF'
```

### 2. Flush DNS cache (macOS):

```bash
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
```

### 3. Start nginx proxy (if not already running):

```bash
cd docker
docker compose -f docker-compose.infra-platform.yml up -d nginx-proxy
```

### 4. Access services via domain names:

- `http://jenkins.local.info` → Jenkins
- `http://airflow.local.dev.info` → Airflow Dev
- `http://airflow.local.test.info` → Airflow Test
- `http://airflow.local.prod.info` → Airflow Prod
- `http://grafana.local.info` → Grafana
- `http://prometheus.local.info` → Prometheus
- `http://redisinsight.local.info` → RedisInsight (Redis web GUI)
- `http://nats.local.info` → NATS Server web GUI (monitoring endpoint with HTML views)
  - `/varz` - Server information and statistics
  - `/connz` - Active connections
  - `/subsz` - Subscriptions
  - `/routez` - Cluster routing (if clustered)
  - `/jsz` - JetStream statistics
  - `/healthz` - Health check
- `http://mlflow.local.info` → MLflow
- `http://kubernetes-dashboard.local.info` → Kubernetes Dashboard (requires `kubectl proxy --port=8001` running)
- `http://kubeflow.local.info` → Kubeflow Pipelines UI (requires `kubectl port-forward -n kubeflow svc/ml-pipeline-ui 8081:80` running)
- `http://portainer.local.info` → Portainer Docker Management UI

## Custom Configuration

### Using Override File

1. Copy the example:
   ```bash
   cp docker-compose.override.yml.example docker-compose.override.yml
   ```

2. Edit `docker-compose.override.yml` with your settings

3. Restart services:
   ```bash
   docker-compose down
   docker-compose up -d
   ```

### Common Customizations

**Change Grafana password:**
```yaml
# In docker-compose.infra-platform.yml
services:
  grafana:
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=your_password
```

**Use PostgreSQL for MLflow:**
```yaml
# In docker-compose.infra-platform.yml
services:
  mlflow:
    environment:
      - MLFLOW_BACKEND_STORE_URI=postgresql://user:pass@postgres:5432/mlflow
    depends_on:
      - postgres
  
  postgres:
    image: postgres:15
    environment:
      - POSTGRES_USER=mlflow
      - POSTGRES_PASSWORD=mlflow
      - POSTGRES_DB=mlflow
    volumes:
      - postgres-data:/var/lib/postgresql/data
```

## Path References

All paths in `docker-compose.infra-platform.yml` are relative to the `.ops/.docker/` folder:
- `../.prometheus/` → Points to `.ops/.prometheus/`
- `../.grafana/` → Points to `.ops/.grafana/`
- `../.grafana/dashboards/` → Points to `.ops/.grafana/dashboards/`
- `../../src` → Points to project `src/` directory (mounted in Airflow containers)

## Commands

All commands should be run from the `.ops/.docker/` directory:

```bash
cd .ops/.docker

# Start infrastructure services
docker-compose -f docker-compose.infra-platform.yml up -d

# Stop infrastructure services
docker-compose -f docker-compose.infra-platform.yml down

# View logs
docker-compose -f docker-compose.infra-platform.yml logs -f

# Restart a service
docker-compose -f docker-compose.infra-platform.yml restart grafana

# View service status
docker-compose -f docker-compose.infra-platform.yml ps

# Remove all data (fresh start)
docker-compose -f docker-compose.infra-platform.yml down -v
```

## Troubleshooting

See `DOCKER_SETUP.md` for detailed troubleshooting guide.

Common issues:
- Port conflicts: Change ports in `docker-compose.infra-platform.yml`
- Permission errors: Check Docker Desktop is running
- Volume mount errors: Verify paths are correct relative to `.ops/.docker/` folder

## Infrastructure vs Application Services

This directory contains two separate Docker Compose files:

1. **`docker-compose.infra-platform.yml`**: All infrastructure services
   - Airflow (dev, test, prod instances)
   - Grafana, Prometheus
   - PostgreSQL, Redis
   - Jenkins, MLflow, Feast
   - Managed by infrastructure pipeline (`Jenkinsfile.infra-platform`)

2. **`docker-compose.yml`**: Application services
   - For application-specific containers (future use)
   - Managed by application pipeline (`Jenkinsfile`)

This separation allows:
- Independent deployment of infrastructure and application
- Separate CI/CD pipelines
- Future migration of `.ops/` to a separate repository

