# Release Notes v1.6.0

## PostgreSQL 18 + pgvector migration

### Main features

#### Datalake Postgres (`postgres-dev`, `postgres-test`, `postgres-prod`)
- **Image:** `pgvector/pgvector:pg18` for all three datalake instances.
- **pgvector:** `CREATE EXTENSION vector` in init SQL and provisioning; available on fresh installs and restored databases.
- **Storage layout:** PG18 cluster data under `storage-postgresql/{env}/18/docker/` (mount `/var/lib/postgresql` in compose).
- **Migration:** Logical dump/restore via `docker/upgrade-postgres-to-18.sh` (PG15 backups as `*.pg15-backup-<timestamp>` during upgrade).
- **Ops tooling:**
  - `docker/watch-postgres-upgrade.sh` — live progress during long upgrades
  - `docker/verify-postgres-upgrade.sh` — catalog, partitions, views, and row-count parity check
  - `docker/cleanup-postgres-pg15-backups.sh` — remove PG15 sidecars/backups after verification
  - `docker/install-pgvector.sh` — enable vector extension on running instances
- **Downstream consumers:** Airflow metadata ( `postgres` schema in `datalake` ), dbt, Feast, Prisma, and pipelines use the same upgraded servers — no separate Airflow Postgres container.

#### OpenProject Postgres (`openproject-postgres`)
- **Image:** `postgres:18` (no pgvector required).
- **Storage layout:** `storage-infra/openproject-postgres/data` mounted at `/var/lib/postgresql`.
- **Migration:** `docker/upgrade-openproject-postgres-to-18.sh` with `docker/verify-openproject-postgres-upgrade.sh`.

#### Doltgres (unchanged runtime)
- Still `dolthub/doltgresql:latest` (Doltgres 0.56.x — **not** a PostgreSQL major version).
- SQL compatibility remains ~PostgreSQL 15; pgvector not supported in Doltgres today.
- Documented in `doltgres/README.md`.

### dbt / Feast / MLflow (incremental on v1.5.0)

> **Note:** dbt containers and the `dbt/feast_features` project were introduced in **v1.5.0**. This release extends that work; it does not add dbt from scratch.

- **dbt:** HP decomposition models, FRED staging/intermediate layers, Feast schema provisioning scripts, and `install-trading-agent.sh` for container bootstrap.
- **Feast:** Updated `feast_repo/definitions.py` for feature store alignment with new dbt outputs.
- **MLflow:** Enhanced `mlflow_tracking.py` for HP feature / training run tracking.

### Migration notes

#### Datalake PG15 → PG18
1. Back up or let the upgrade script snapshot PG15 data (`*.pg15-backup-<timestamp>`).
2. Run `./docker/upgrade-postgres-to-18.sh {dev|test|prod}` (dev can take many hours for large datalakes).
3. Verify: `./docker/verify-postgres-upgrade.sh <env> /path/to/backup`
4. Cleanup PG15 artifacts: `./docker/cleanup-postgres-pg15-backups.sh --confirm`
5. Restart nginx-proxy if gateway connections fail.

#### OpenProject PG15 → PG18
1. `./docker/upgrade-openproject-postgres-to-18.sh`
2. `./docker/verify-openproject-postgres-upgrade.sh /path/to/data.pg15-backup-<ts>`
3. Remove PG15 backup when satisfied.

### Breaking changes

- Compose volume mounts for Postgres 18+ use `/var/lib/postgresql` (not `/var/lib/postgresql/data`).
- PG15 backup directories must be kept until verification passes; cleanup is manual via script.

### Files added / changed (high level)

- `docker/docker-compose.infra-platform.yml` — PG18 images and volume mounts
- `docker/upgrade-postgres-to-18.sh`, `verify-postgres-upgrade.sh`, `cleanup-postgres-pg15-backups.sh`, `watch-postgres-upgrade.sh`, `install-pgvector.sh`
- `docker/upgrade-openproject-postgres-to-18.sh`, `verify-openproject-postgres-upgrade.sh`
- `docker/init-pg-datalake-*.sql`, `storage-postgresql/README.md`, `storage-infra/README.md`
- `dbt/feast_features/` — HP models, staging, macros, scripts
- `feast/feast_repo/definitions.py`, `mlflow/mlflow_tracking.py`

---

**Tag:** v1.6.0  
**Date:** 2026-07-02  
**Branch:** main
