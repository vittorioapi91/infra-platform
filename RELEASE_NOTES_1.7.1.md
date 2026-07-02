# Release Notes v1.7.1

## Feast UI, dbt docs, and Kubernetes gateway hardening

### Main features

#### Feast UI and dbt docs (per environment)
- `feast-{env}` sidecars run `feast ui` (ports `8890`/`8891`/`8892` on host).
- `dbt-{env}` sidecars serve `dbt docs` (ports `8880`/`8881`/`8882` on host).
- Nginx vhosts: `feast.local.{dev,test,prod}.info`, `dbt.local.{dev,test,prod}.info`.
- Entrypoints: `docker/feast-ui-entrypoint.sh`, `docker/dbt-docs-entrypoint.sh`.

#### Reliable nginx → Kubernetes routing
- Compose sidecars replace host `kubectl port-forward` for **Kubernetes Dashboard** and **Kubeflow Pipelines** (`kubernetes-dashboard-port-forward`, `kubeflow-port-forward`).
- Shared kubeconfig init: `docker/k8s-kubeconfig-init.sh`.
- Unavailable fallback pages when K8s backends are down.
- PMA dashboard uses host bridge sidecar (`pma-dashboard-proxy`).

#### Kubeflow Pipelines (local kind)
- Install script: `kubernetes/install-kubeflow-pipelines.sh` (KFP 2.16.1).
- Image pre-pull for arm64/amd64: `kubernetes/prepull-kubeflow-images.sh`.
- Pipeline runner image and deploy scripts under `kubernetes/`.
- Macro ML pipeline compile/submit docs in `kubeflow/README.md`.

#### Kubernetes Dashboard RBAC (local dev)
- `kubernetes/kubernetes-dashboard-rbac.yaml` binds skip-login SA to `cluster-admin` for local use.
- Applied from `start-kubernetes.sh` and `start-all-services.sh`.

#### dbt schema fix
- Removed redundant `+schema: feast` from `dbt_project.yml` (was creating `feast_feast` in docs/Postgres).
- Deduplicated `feast_engineered` source definitions (`schema.yml` vs `sources.yml`).

### Migration notes

1. **Hosts:** add to `/etc/hosts` (see `gateway/nginx/redirects.md`):
   ```
   127.0.0.1 feast.local.dev.info feast.local.test.info feast.local.prod.info
   127.0.0.1 dbt.local.dev.info dbt.local.test.info dbt.local.prod.info
   ```
2. **Restart:** `docker compose -f docker/docker-compose.infra-platform.yml up -d feast-dev feast-test feast-prod dbt-dev dbt-test dbt-prod nginx-proxy kubernetes-dashboard-port-forward kubeflow-port-forward`
3. **First boot:** dbt/Feast sidecars install Python deps on startup; docs/UI may take a few minutes.
4. **Feast UI:** uses `feast[grpcio]` (Feast 0.64+ no longer ships gRPC in the `local` extra).

### Breaking changes

- None for data paths. Deprecated: `kubernetes/k8s-port-forward-supervisor.sh` (replaced by compose sidecars).

### Files added / changed (high level)

- `docker/docker-compose.infra-platform.yml` — Feast/dbt UI services, K8s port-forward sidecars
- `gateway/nginx/nginx-feast.conf`, `nginx-dbt.conf`, updated dashboard/kubeflow/pma configs
- `docker/feast-ui-entrypoint.sh`, `docker/dbt-docs-entrypoint.sh`
- `kubernetes/install-kubeflow-pipelines.sh`, `prepull-kubeflow-images.sh`, `kubernetes-dashboard-rbac.yaml`
- `dbt/feast_features/dbt_project.yml`, `models/schema.yml`, `models/sources.yml`
- `start-all-services.sh`, `gateway/nginx/redirects.md`, `feast/README.md`, `dbt/README.md`

---

**Tag:** v1.7.1  
**Date:** 2026-07-02  
**Branch:** main
