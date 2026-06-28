# Doltgres data storage (host filesystem)

**Three** Doltgres instances (dev, test, prod), parallel to PostgreSQL. Data lives **outside** Docker images.

**Default paths** (used by compose and scripts):

```
storage-doltgres/
├── dev/      → doltgres-dev (direct port 54331, nginx 54334)
├── test/     → doltgres-test (direct port 54332, nginx 54335)
└── prod/     → doltgres-prod (direct port 54333, nginx 54336)
```

Each of `dev`, `test`, `prod` may be a **symlink** to data on another volume (same pattern as `storage-postgresql/`). Compose mounts `../storage-doltgres/{dev|test|prod}` to `/var/lib/doltgres` in `docker/docker-compose.infra-platform.yml`.

Do not remove these directories (or break symlinks) while Doltgres containers are running.

Migration from PostgreSQL is documented in [`doltgres/README.md`](../doltgres/README.md). **Do not migrate while applications are actively writing to Postgres.**
