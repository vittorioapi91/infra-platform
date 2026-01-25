# Infra service data (bind-mounted, outside Docker images)

Lives **on the host** at `<repo>/storage-infra`. All data here is bind-mounted into containers; nothing is stored in Docker images. Most components use a `data/` subdir (e.g. `jenkins/data`); Airflow uses `airflow/{dev,test,prod}/` directly (db, wheels, workspace/package_root, logs).

| Directory | Service | Container path |
|-----------|---------|----------------|
| `prometheus/data/` | Prometheus | `/prometheus` |
| `grafana/data/` | Grafana | `/var/lib/grafana` |
| `mlflow/data/` | MLflow | `/mlflow` |
| `redisinsight/data/` | RedisInsight | `/data` |
| `nats/data/` | NATS | `/data` |
| `openproject/data/` | OpenProject | `/var/openproject/assets` |
| `openproject-postgres/data/` | OpenProject Postgres | `/var/lib/postgresql/data` |
| `registry/data/` | Docker Registry | `/var/lib/registry` |
| `portainer/data/` | Portainer | `/data` |
| `jenkins/data/` | Jenkins | `/var/jenkins_home` |
| `airflow/{dev,test,prod}/` | Airflow | db (home), wheels, workspace/package_root, logs |

**Airflow:** `airflow/{env}/db` (Airflow home, bind-mounted as `/opt/airflow`), plus `wheels`, `workspace` (dev) or `package_root` (test/prod), and `logs`. DAGs stay versioned in `airflow/{env}/dags/`.

Folder structure is committed; contents are gitignored (see root `.gitignore`).

**Migration from old locations:**
- **Jenkins**: If you had `jenkins/data`, copy to `storage-infra/jenkins/data` before switching:  
  `cp -a jenkins/data/. storage-infra/jenkins/data/`
- **Airflow**: If you had `airflow/{env}/wheels`, `workspace`, `logs`, or (test/prod) package contents, copy to `storage-infra/airflow/{env}/`:
  ```bash
  cp -a airflow/dev/wheels/. storage-infra/airflow/dev/wheels/
  cp -a airflow/dev/workspace/. storage-infra/airflow/dev/workspace/
  cp -a airflow/dev/logs/. storage-infra/airflow/dev/logs/
  # test/prod: wheels, package_root (exclude dags), logs
  ```
- **Airflow db**: Previously used Docker named volumes `airflow-db-dev`, `airflow-db-test`, `airflow-db-prod`. To migrate, copy from a temporary container, e.g.  
  `docker run --rm -v airflow-db-dev:/src -v $(pwd)/storage-infra/airflow/dev/db:/dst alpine sh -c "cp -a /src/. /dst/"`  
  (same for `airflow-db-test` → `storage-infra/airflow/test/db`, `airflow-db-prod` → `storage-infra/airflow/prod/db`).
- **Others**: Previous data was in Docker named volumes. To migrate, copy from a temporary container that mounts the old volume, or start fresh.
