# Postgres data storage (host filesystem)

**Three** Postgres instances (dev, test, prod). TA and PMA share them via the **datalake** database and schemas (`postgres`, `polymarket`, etc.). Data lives **outside** Docker volumes.

**Default paths** (used by compose and scripts):

```
storage-postgresql/
├── dev/      → postgres-dev (port 54324)
├── test/     → postgres-test (port 54325)
└── prod/     → postgres-prod (port 54326)
```

Each of `dev`, `test`, `prod` may be a **symlink** to data on another volume (e.g. SSD at `/Volumes/storage-volume/storage-psql/dev` etc.). Compose mounts `../storage-postgresql/{dev|test|prod}` to `/var/lib/postgresql` in `docker/docker-compose.infra-platform.yml` (PostgreSQL **18+** stores data under `18/docker/` inside that mount). Do not remove these directories (or break the symlinks) while Postgres containers are running.

Major-version upgrades: `docker/upgrade-postgres-to-18.sh` (PG15 backups are kept as `*.pg15-backup-<timestamp>` next to each data dir during upgrade). Verify with `docker/verify-postgres-upgrade.sh`; remove backups with `docker/cleanup-postgres-pg15-backups.sh --confirm`.
