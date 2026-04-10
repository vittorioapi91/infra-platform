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
- `nginx-prisma.conf` - Routes `prisma.postgres.{dev|test|prod}` to Prisma Studio. **Use http:// (not https)**. Run `npx prisma studio --port 5555` inside the container.
- `nginx-mlflow.conf` - Routes `mlflow.local.info` to MLflow
- `nginx-kubernetes-dashboard.conf` - Routes `kubernetes-dashboard.local.info` to Kubernetes Dashboard
- `nginx-kubeflow.conf` - Routes `kubeflow.local.info` to Kubeflow Pipelines UI
- `nginx-portainer.conf` - Routes `portainer.local.info` to Portainer
- `nginx-pma-dashboard.conf` - PMA (PredictionMarketsAgent) dashboard; routes `predictionmarketsagent.local.info` to host.docker.internal:7567
- `nginx-postgres.stream.conf` - PostgreSQL TCP proxy (stream); included from `nginx.conf` **stream** block. **Three TradingAgent Postgres servers** – dev, test, prod. Each port proxies to its own container.

Use these hostnames + ports in your DB clients and `.env` files:

| Hostname | Port | Server | Use for |
|----------|------|--------|---------|
| `postgres.dev.local.info` | 54324 | postgres-dev | TradingAgent & PredictionMarketsAgent dev |
| `postgres.test.local.info` | 54325 | postgres-test | TradingAgent & PredictionMarketsAgent test |
| `postgres.prod.local.info` | 54326 | postgres-prod | TradingAgent & PredictionMarketsAgent prod |

Stream routing is **by port only** (hostname is ignored by Nginx). Each port proxies to a **different** Postgres container. All apps use the single **datalake** database; previous DB names are now **schemas** (e.g. `postgres`, `polymarket`, `edgar`).

**DB client / IDE connection check** – use this matrix:

| Connection | Host | Port | Database | Schema | User |
|------------|------|------|----------|--------|------|
| dev (TA) | `postgres.dev.local.info` | **54324** | **datalake** | postgres | dev.user |
| test (TA) | `postgres.test.local.info` | **54325** | **datalake** | postgres | test.user |
| prod (TA) | `postgres.prod.local.info` | **54326** | **datalake** | postgres | prod.user |
| dev (PMA) | `postgres.dev.local.info` | **54324** | **datalake** | polymarket | dev.user |
| test (PMA) | `postgres.test.local.info` | **54325** | **datalake** | polymarket | test.user |
| prod (PMA) | `postgres.prod.local.info` | **54326** | **datalake** | postgres | prod.user |

Password for all: `2014`. Set **search_path** to the schema (e.g. `postgres`, `polymarket`) or use qualified names.

## Troubleshooting

### "Server closed the connection unexpectedly" or connection fails via nginx

Nginx **caches upstream IPs** at startup. When Postgres containers are restarted or recreated (e.g. after storage changes), they get new IPs and nginx keeps using stale ones.

**Fix:** Restart nginx so it re-resolves Postgres hostnames:
```bash
cd docker && docker compose -f docker-compose.infra-platform.yml restart nginx-proxy
```

### DataGrip / IntelliJ / other IDEs

- **Always set Database explicitly** to **datalake**. Set the default **schema** (e.g. `postgres` for TA, `polymarket` for PMA dev) in connection options or `search_path`.
- Use the **User** from the matrix above (**{env}.user**: dev.user, test.user, prod.user).
- If you see SSL or handshake errors, set **SSL mode** to `disable` in the connection options (e.g. Advanced → VM options or URL `?sslmode=disable`).

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
127.0.0.1 prisma.postgres.dev prisma.postgres.test prisma.postgres.prod
127.0.0.1 mlflow.local.info
127.0.0.1 kubernetes-dashboard.local.info
127.0.0.1 kubeflow.local.info
127.0.0.1 portainer.local.info
127.0.0.1 predictionmarketsagent.local.info

# PostgreSQL (TradingAgent dev/test/prod; port in connection string)
127.0.0.1 postgres.dev.local.info postgres.test.local.info postgres.prod.local.info
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
