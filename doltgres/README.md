# Doltgres (version-controlled PostgreSQL)

[Doltgres](https://www.doltgres.com) runs in parallel to the existing PostgreSQL servers (`postgres-dev`, `postgres-test`, `postgres-prod`). Apps continue to use Postgres until you cut over.

## Services

| Env | Container | Direct port | Nginx port | Hostname |
|-----|-----------|-------------|------------|----------|
| dev | `doltgres-dev` | 54331 | 54334 | `doltgres.dev.local.info` |
| test | `doltgres-test` | 54332 | 54335 | `doltgres.test.local.info` |
| prod | `doltgres-prod` | 54333 | 54336 | `doltgres.prod.local.info` |

- **Image:** `dolthub/doltgresql:latest`
- **Database:** `datalake` (same schema layout as Postgres: `postgres`, `polymarket`, `edgar`, …)
- **Users:** `dev.user` / `test.user` / `prod.user` (password: `POSTGRES_PASSWORD`, default `2014`)
- **Data:** `storage-doltgres/{dev|test|prod}/` on the host

## Start

```bash
cd docker
docker compose -f docker-compose.infra-platform.yml up -d doltgres-dev doltgres-test doltgres-prod
```

Or bring up the full stack with `./start-all-services.sh`.

## Connect (dev example)

```bash
PGPASSWORD=2014 psql -h doltgres.dev.local.info -p 54334 -U dev.user -d datalake
```

Add to `/etc/hosts` (see `gateway/README.md`):

```text
127.0.0.1 doltgres.dev.local.info doltgres.test.local.info doltgres.prod.local.info
```

## Migration from PostgreSQL (later)

**Do not run migration while writers are active on Postgres.**

Logical copy script (reads Postgres only; writes Doltgres storage only):

```bash
./docker/migrate-postgres-to-doltgres.sh test
./docker/migrate-postgres-to-doltgres.sh all
```

Suggested high-level plan:

1. Stop writers / put apps in read-only or maintenance mode.
2. Run `migrate-postgres-to-doltgres.sh` per env, or dump/restore manually.
3. Validate schemas, row counts, and application smoke tests against Doltgres ports.
4. Update app `.env` / Airflow `SQL_ALCHEMY_CONN` / Prisma `DATABASE_URL` to point at Doltgres hostnames.
5. Cut over; keep Postgres containers stopped but data retained until rollback window ends.

Doltgres-specific features (branch/merge) are available after cutover via Doltgres SQL procedures.

## Init scripts

Bootstrap SQL is in `docker/init-doltgres-datalake-{dev|test|prod}.sql` (adapted from Postgres init: uses `DOLTGRES_DB=datalake`, no `CREATE DATABASE` / `\c`). App users are created in `docker/init-doltgres-bootstrap-{dev|test|prod}.sh` (Doltgres does not support `DO` blocks).
