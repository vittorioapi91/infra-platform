# Nginx redirects (HTTP) + TCP proxies (Postgres/Doltgres)

All interactive services are routed through `nginx-proxy` on **host port `80`**.
Nginx vhost config files live in this folder and are mounted into:
`/etc/nginx/conf.d/*.conf`.

## Hostnames to add to `/etc/hosts` (macOS/Linux)

Use this exact snippet (includes MLflow dev/test/prod):

```bash
sudo sh -c 'cat >> /etc/hosts << EOF

# Infrastructure Platform Services
127.0.0.1 jenkins.local.info
127.0.0.1 airflow.local.dev.info airflow.local.test.info airflow.local.prod.info
127.0.0.1 grafana.local.info
127.0.0.1 prometheus.local.info
127.0.0.1 redisinsight.local.info
127.0.0.1 nats.local.info
127.0.0.1 openproject.local.info
127.0.0.1 mlflow.local.dev.info mlflow.local.test.info mlflow.local.prod.info
127.0.0.1 feast.local.dev.info feast.local.test.info feast.local.prod.info
127.0.0.1 dbt.local.dev.info dbt.local.test.info dbt.local.prod.info
127.0.0.1 prisma.postgres.dev prisma.postgres.test prisma.postgres.prod
127.0.0.1 kubernetes-dashboard.local.info
127.0.0.1 kubeflow.local.info
127.0.0.1 portainer.local.info
127.0.0.1 predictionmarketsagent.local.info
127.0.0.1 alertmanager.local.info

# PostgreSQL (TradingAgent dev/test/prod; stream proxy by port)
127.0.0.1 postgres.dev.local.info postgres.test.local.info postgres.prod.local.info

# Doltgres (stream proxy by port)
127.0.0.1 doltgres.dev.local.info doltgres.test.local.info doltgres.prod.local.info
EOF'
```

After changing hostnames, clear macOS DNS cache if needed:

```bash
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
```

## Architecture

Nginx routes all vhosts on the **`monitoring`** Docker network. Three backend patterns:

| Pattern | When | Nginx target | Examples |
|---|---|---|---|
| **Compose service** | App runs in this stack | `http://<service>:<port>` | jenkins, mlflow-dev, airflow-dev, grafana |
| **K8s port-forward sidecar** | App runs in kind | `*-port-forward:<port>` | kubernetes-dashboard, kubeflow |
| **Host bridge sidecar** | App runs on the Mac host | `*-proxy:<port>` | pma-dashboard-proxy |

**Sidecars are only needed when the app is outside the compose network** (Kubernetes or host). Jenkins, MLflow, Airflow, etc. are already compose services — nginx talks to them directly; adding proxy sidecars would be extra hops with no reliability gain.

All vhosts use Docker DNS (`resolver 127.0.0.11`) + dynamic `proxy_pass` so nginx can start before backends.

## HTTP redirects (nginx vhosts)

Each hostname corresponds to one `nginx-*.conf` file:

| Hostname | Config file | Backend (container) |
|---|---|---|
| `jenkins.local.info` | `nginx-jenkins.conf` | `jenkins:8080` |
| `airflow.local.dev.info` | `nginx-airflow.conf` | `airflow-dev:8080` |
| `airflow.local.test.info` | `nginx-airflow.conf` | `airflow-test:8080` |
| `airflow.local.prod.info` | `nginx-airflow.conf` | `airflow-prod:8080` |
| `grafana.local.info` | `nginx-grafana.conf` | `grafana:3000` |
| `prometheus.local.info` | `nginx-prometheus.conf` | `prometheus:9090` |
| `redisinsight.local.info` | `nginx-redisinsight.conf` | `redisinsight:5540` |
| `nats.local.info` | `nginx-nats.conf` | `nats:8222` (monitoring endpoints) |
| `openproject.local.info` | `nginx-openproject.conf` | `openproject:80` |
| `prisma.postgres.dev` | `nginx-prisma.conf` | `prisma-dev:5555` |
| `prisma.postgres.test` | `nginx-prisma.conf` | `prisma-test:5555` |
| `prisma.postgres.prod` | `nginx-prisma.conf` | `prisma-prod:5555` |
| `mlflow.local.dev.info` | `nginx-mlflow-dev.conf` | `mlflow-dev:5000` |
| `mlflow.local.test.info` | `nginx-mlflow-test.conf` | `mlflow-test:5000` |
| `mlflow.local.prod.info` | `nginx-mlflow-prod.conf` | `mlflow-prod:5000` |
| `feast.local.dev.info` | `nginx-feast.conf` | `feast-dev:8888` |
| `feast.local.test.info` | `nginx-feast.conf` | `feast-test:8888` |
| `feast.local.prod.info` | `nginx-feast.conf` | `feast-prod:8888` |
| `dbt.local.dev.info` | `nginx-dbt.conf` | `dbt-dev:8880` |
| `dbt.local.test.info` | `nginx-dbt.conf` | `dbt-test:8880` |
| `dbt.local.prod.info` | `nginx-dbt.conf` | `dbt-prod:8880` |
| `kubernetes-dashboard.local.info` | `nginx-kubernetes-dashboard.conf` | `kubernetes-dashboard-port-forward:8001` (HTTPS) |
| `kubeflow.local.info` | `nginx-kubeflow.conf` | `kubeflow-port-forward:8088` |
| `portainer.local.info` | `nginx-portainer.conf` | portainer |
| `predictionmarketsagent.local.info` | `nginx-pma-dashboard.conf` | `pma-dashboard-proxy:7567` → host app |
| `alertmanager.local.info` | `nginx-alertmanager.conf` | alertmanager |

## TCP proxies (Postgres + Doltgres)

These are configured under `gateway/nginx/nginx.conf` in the `stream {}` block, via:

- `nginx-postgres.stream.conf`  
  - `postgres.dev.local.info` → **54324** → `postgres-dev:5432`
  - `postgres.test.local.info` → **54325** → `postgres-test:5432`
  - `postgres.prod.local.info` → **54326** → `postgres-prod:5432`

- `nginx-doltgres.stream.conf`
  - `doltgres.dev.local.info` → **54334**
  - `doltgres.test.local.info` → **54335**
  - `doltgres.prod.local.info` → **54336**

## Verify

Example (MLflow):

```bash
curl -I http://mlflow.local.dev.info
```

Example (Airflow dev):

```bash
curl -I http://airflow.local.dev.info
```

Example (Feast dev):

```bash
curl -I http://feast.local.dev.info
# direct: http://localhost:8890
```

Example (dbt docs dev):

```bash
curl -I http://dbt.local.dev.info
# direct: http://localhost:8880
```

