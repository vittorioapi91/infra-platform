# Postgres data storage (host filesystem)

**Three** Postgres instances (dev, test, prod). TA and PMA share them via the **datalake** database and schemas (`postgres`, `polymarket`, etc.). Data lives **outside** Docker volumes.

**Default paths** (used by compose and scripts):

```
storage-postgresql/
├── dev/      → postgres-ta-dev (port 54324)
├── test/     → postgres-ta-test (port 54325)
└── prod/     → postgres-ta-prod (port 54326)
```

Each of `dev`, `test`, `prod` may be a **symlink** to data on another volume (e.g. SSD at `/Volumes/storage-volume/storage-psql/dev` etc.). Compose uses `../storage-postgresql/{dev|test|prod}` in `docker/docker-compose.infra-platform.yml`. Do not remove these directories (or break the symlinks) while Postgres containers are running.
