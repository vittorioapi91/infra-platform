# Gateway Configuration

This folder contains gateway and reverse proxy configuration files.

## Structure

- `nginx/` - Nginx reverse proxy configuration files for routing traffic to infrastructure services via custom domain names

## Nginx Configuration Files

All nginx configuration files are in the `nginx/` subdirectory and follow the pattern `nginx-{service}.conf`:

- `nginx-jenkins.conf` - Routes `jenkins.local.info` to Jenkins
- `nginx-airflow.conf` - Routes `airflow.local.{env}.info` to Airflow environments
- `nginx-grafana.conf` - Routes `grafana.local.info` to Grafana
- `nginx-prometheus.conf` - Routes `prometheus.local.info` to Prometheus
- `nginx-redisinsight.conf` - Routes `redisinsight.local.info` to RedisInsight
- `nginx-nats.conf` - Routes `nats.local.info` to NATS monitoring endpoint
- `nginx-openproject.conf` - Routes `openproject.local.info` to OpenProject
- `nginx-mlflow.conf` - Routes `mlflow.local.info` to MLflow
- `nginx-kubernetes-dashboard.conf` - Routes `kubernetes-dashboard.local.info` to Kubernetes Dashboard
- `nginx-kubeflow.conf` - Routes `kubeflow.local.info` to Kubeflow Pipelines UI
- `nginx-portainer.conf` - Routes `portainer.local.info` to Portainer
- `nginx-pma-dashboard.conf` - PMA (PredictionMarketsAgent) dashboard; routes `predictionmarketsagent.local.info` to host.docker.internal:7567
- `nginx-postgres.stream.conf` - PostgreSQL TCP proxy (stream); included from `nginx.conf` **stream** block. **Six separate Postgres servers** – one per logical server. Each port proxies to its own container.

Use these hostnames + ports in your DB clients and `.env` files:

| Hostname | Port | Server | Use for |
|----------|------|--------|---------|
| `postgres.dev.predictionmarketsagent.local.info` | 54321 | postgres-pma-dev | PredictionMarketsAgent dev |
| `postgres.test.predictionmarketsagent.local.info` | 54322 | postgres-pma-test | PredictionMarketsAgent test |
| `postgres.prod.predictionmarketsagent.local.info` | 54323 | postgres-pma-prod | PredictionMarketsAgent prod |
| `postgres.dev.tradingagent.local.info` | 54324 | postgres-ta-dev | TradingAgent dev |
| `postgres.test.tradingagent.local.info` | 54325 | postgres-ta-test | TradingAgent test |
| `postgres.prod.tradingagent.local.info` | 54326 | postgres-ta-prod | TradingAgent prod |

Stream routing is **by port only** (hostname is ignored by Nginx). Each port proxies to a **different** Postgres container.

**DB client / IDE connection check** – use this matrix:

| Connection | Host | Port | Database | User |
|------------|------|------|----------|------|
| dev.predictionMarketsAgent | `postgres.dev.predictionmarketsagent.local.info` | **54321** | **polymarket** | postgres |
| dev.tradingAgent | `postgres.dev.tradingagent.local.info` | **54324** | **postgres** | dev.tradingAgent |

## Usage

These configuration files are mounted into the `nginx-proxy` container defined in `docker/docker-compose.infra-platform.yml`.

The nginx-proxy service:
- Listens on port 80 (HTTP) and 443 (HTTPS)
- Routes requests based on the `Host` header to the appropriate backend service
- Handles WebSocket upgrades for services that require them
- Provides graceful error handling when backend services are not yet available

## Domain Setup

To use these domain names, add entries to `/etc/hosts`:

```bash
127.0.0.1 jenkins.local.info
127.0.0.1 airflow.local.dev.info airflow.local.test.info airflow.local.prod.info
127.0.0.1 grafana.local.info
127.0.0.1 prometheus.local.info
127.0.0.1 redisinsight.local.info
127.0.0.1 nats.local.info
127.0.0.1 openproject.local.info
127.0.0.1 mlflow.local.info
127.0.0.1 kubernetes-dashboard.local.info
127.0.0.1 kubeflow.local.info
127.0.0.1 portainer.local.info
127.0.0.1 predictionmarketsagent.local.info

# PostgreSQL (one hostname per logical server; port in connection string)
127.0.0.1 postgres.dev.predictionmarketsagent.local.info postgres.test.predictionmarketsagent.local.info postgres.prod.predictionmarketsagent.local.info
127.0.0.1 postgres.dev.tradingagent.local.info postgres.test.tradingagent.local.info postgres.prod.tradingagent.local.info
```

See `docker/README.md` for complete setup instructions.

## Adding New Services

To add a new service:

1. Create a new `nginx-{service}.conf` file in the `nginx/` directory
2. Configure the `server_name` and `proxy_pass` directives
3. Add the volume mount to `docker/docker-compose.infra-platform.yml`:
   ```yaml
   - ../gateway/nginx/nginx-{service}.conf:/etc/nginx/conf.d/{service}.conf:ro
   ```
4. Add the domain to `/etc/hosts`
5. Restart the nginx-proxy container
