# Release Notes v1.5.0

## Airflow v3, Doltgres, dbt, and ML platform updates

### Main features

#### Apache Airflow 3.2.2 upgrade
- **Image:** `apache/airflow:3.2.2` for dev, test, and prod environments.
- **Runtime:** Uses Airflow 3 components (`airflow db migrate`, `airflow api-server`, `airflow dag-processor`, `airflow triggerer`) instead of the v2 standalone/webserver pattern.
- **Auth:** FAB auth manager via `apache-airflow-providers-fab` with stable secret keys in compose.
- **Plugins:** Consolidated environment UI into `plugin_environment_info.py` (replaces `plugin_reboot`, `plugin_startup_animation`, `plugin_wheel_display`). Updated `idp_install_info.py` and environment banner templates for Airflow 3.
- **DAGs & operators:** Added `dag_compat.py`, `dag_task_groups.py`, and `trading_agent_dags.py` for v3-compatible DAG loading and task groups.
- **Gateway:** Updated `nginx-airflow.conf` for Airflow 3 API/UI routing.
- **CI:** Jenkinsfile validates against `apache-airflow>=3.2.0`.

#### Doltgres (version-controlled PostgreSQL)
- **Three parallel instances:** `doltgres-dev`, `doltgres-test`, `doltgres-prod` using `dolthub/doltgresql:latest`.
- **Ports:** Direct 54331–54333; nginx stream proxy 54334–54336 (`doltgres.{dev|test|prod}.local.info`).
- **Data:** `storage-doltgres/{dev|test|prod}/` (gitignored runtime data; structure versioned).
- **Init:** Bootstrap shell scripts + adapted SQL (no `DO` blocks; Doltgres-specific constraints).
- **Migration:** `docker/migrate-postgres-to-doltgres.sh` for logical Postgres → Doltgres copy (does not touch Postgres storage).
- **Postgres unchanged:** Applications continue using existing `postgres-*` servers until explicit cutover.

#### dbt (feature engineering for Feast)
- **Containers:** `dbt-dev`, `dbt-test`, `dbt-prod` on `python:3.11-slim`.
- **Project:** `dbt/feast_features/` materializes models into the **`feast`** schema on each env's `datalake` database.
- **Integration:** Documented Feast consumption path in `feast/README.md` and `dbt/README.md`.

### Infrastructure improvements

- **MLflow / Kubernetes:** Monitoring stack and MLflow README updates for model-training workflows (IFP-58).
- **Model-training image:** Dual-wheel support (idp + trading_agent) in Jenkins pipeline.
- **Startup:** `start-all-services.sh` logs Doltgres and dbt endpoints.
- **Gateway:** `nginx-doltgres.stream.conf` and `/etc/hosts` entries documented in `gateway/README.md`.

### Migration notes

#### Airflow v3
1. Restart all Airflow containers after pull: `docker compose -f docker/docker-compose.infra-platform.yml up -d airflow-dev airflow-test airflow-prod`
2. FAB login uses existing admin users; sessions persist via compose secret keys.
3. Custom plugins load from `airflow/plugins/environment_info/`; legacy reboot/animation plugins removed.

#### Doltgres
1. Start: `docker compose -f docker/docker-compose.infra-platform.yml up -d doltgres-dev doltgres-test doltgres-prod`
2. Add hosts: `doltgres.dev.local.info`, `doltgres.test.local.info`, `doltgres.prod.local.info`
3. **Do not migrate while writers are active on Postgres.** Use `migrate-postgres-to-doltgres.sh` during a maintenance window.

#### dbt
1. Containers install dbt on first start; run `docker exec -it dbt-dev dbt run` to materialize features.
2. Set `POSTGRES_PASSWORD` consistently with other utilities (default `2014`).

### Breaking changes

- Airflow 2.x DAG/plugin APIs removed; use v3-compatible operators and FastAPI plugin hooks.
- Removed standalone Airflow webserver command; use api-server + dag-processor layout.

### Files added / changed (high level)

- `docker/docker-compose.infra-platform.yml` – Airflow 3, Doltgres, dbt services
- `doltgres/README.md`, `storage-doltgres/README.md`
- `docker/init-doltgres-*`, `docker/migrate-postgres-to-doltgres.sh`
- `dbt/` – profiles, feast_features project
- `gateway/nginx/nginx-doltgres.stream.conf`, `nginx-airflow.conf`
- `airflow/plugins/environment_info/plugin_environment_info.py`
- `airflow/operators/dag_compat.py`, `dag_task_groups.py`
- `RELEASE_NOTES_1.5.0.md`

---

**Tag:** v1.5.0  
**Date:** 2026-06-05  
**Branch:** main
