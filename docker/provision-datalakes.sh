#!/usr/bin/env bash
# Idempotently create database "datalake", app role, and TA/PMA schemas on each
# postgres-{dev,test,prod} instance. Safe to re-run (e.g. after empty volume or drift).
#
# Superuser: postgres / $POSTGRES_PASSWORD (default 2014) — matches docker-compose.
# App users: dev.user, test.user, prod.user — same password as POSTGRES_PASSWORD.
#
# Usage: from repo root or docker/:  ./docker/provision-datalakes.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-2014}"

# Keep in sync with docker/init-pg-datalake-{dev,test,prod}.sql
SCHEMAS=(
  postgres polymarket edgar nasdaqtrader ishares fred bls bis eurostat imf yfinance public
)

provision_instance() {
  local container="$1"
  local app_user="$2"

  if ! docker ps --format '{{.Names}}' | grep -qx "$container"; then
    echo "ERROR: container $container is not running. Start compose postgres services first." >&2
    return 1
  fi

  echo "=== $container (app user: $app_user) ==="

  docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$container" psql -U postgres -d postgres -v ON_ERROR_STOP=1 <<EOSQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$app_user') THEN
    CREATE ROLE "$app_user" LOGIN PASSWORD '$POSTGRES_PASSWORD' CREATEDB;
  ELSE
    ALTER ROLE "$app_user" LOGIN PASSWORD '$POSTGRES_PASSWORD';
  END IF;
END
\$\$;
EOSQL

  local exists
  exists="$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$container" psql -U postgres -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = 'datalake'")"
  if [ -z "${exists// /}" ]; then
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$container" psql -U postgres -d postgres -v ON_ERROR_STOP=1 -c "CREATE DATABASE datalake OWNER \"$app_user\";"
    echo "  created database datalake (owner $app_user)"
  else
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$container" psql -U postgres -d postgres -v ON_ERROR_STOP=1 -c "ALTER DATABASE datalake OWNER TO \"$app_user\";"
    echo "  database datalake already exists"
  fi

  local create_schemas=""
  for s in "${SCHEMAS[@]}"; do
    create_schemas+="CREATE SCHEMA IF NOT EXISTS $s; "
  done

  docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$container" psql -U postgres -d datalake -v ON_ERROR_STOP=1 <<EOSQL
$create_schemas
GRANT ALL ON DATABASE datalake TO postgres;
GRANT ALL ON DATABASE datalake TO "$app_user";
GRANT USAGE ON SCHEMA ${SCHEMAS[0]}$(printf ', %s' "${SCHEMAS[@]:1}") TO postgres;
GRANT USAGE ON SCHEMA ${SCHEMAS[0]}$(printf ', %s' "${SCHEMAS[@]:1}") TO "$app_user";
GRANT CREATE ON SCHEMA ${SCHEMAS[0]}$(printf ', %s' "${SCHEMAS[@]:1}") TO postgres;
GRANT CREATE ON SCHEMA ${SCHEMAS[0]}$(printf ', %s' "${SCHEMAS[@]:1}") TO "$app_user";
GRANT ALL ON ALL TABLES IN SCHEMA ${SCHEMAS[0]}$(printf ', %s' "${SCHEMAS[@]:1}") TO postgres;
GRANT ALL ON ALL TABLES IN SCHEMA ${SCHEMAS[0]}$(printf ', %s' "${SCHEMAS[@]:1}") TO "$app_user";
GRANT ALL ON ALL SEQUENCES IN SCHEMA ${SCHEMAS[0]}$(printf ', %s' "${SCHEMAS[@]:1}") TO postgres;
GRANT ALL ON ALL SEQUENCES IN SCHEMA ${SCHEMAS[0]}$(printf ', %s' "${SCHEMAS[@]:1}") TO "$app_user";
EOSQL

  for s in "${SCHEMAS[@]}"; do
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$container" psql -U postgres -d datalake -v ON_ERROR_STOP=1 -c "ALTER DEFAULT PRIVILEGES IN SCHEMA $s GRANT ALL ON TABLES TO postgres; ALTER DEFAULT PRIVILEGES IN SCHEMA $s GRANT ALL ON TABLES TO \"$app_user\"; ALTER DEFAULT PRIVILEGES IN SCHEMA $s GRANT ALL ON SEQUENCES TO postgres; ALTER DEFAULT PRIVILEGES IN SCHEMA $s GRANT ALL ON SEQUENCES TO \"$app_user\";" >/dev/null
  done

  docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$container" psql -U postgres -d postgres -v ON_ERROR_STOP=1 -c "ALTER USER postgres SET search_path TO postgres;" >/dev/null || true
  docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$container" psql -U postgres -d postgres -v ON_ERROR_STOP=1 -c "ALTER USER \"$app_user\" SET search_path TO postgres;" >/dev/null || true

  echo "  OK"
}

provision_instance postgres-dev dev.user
provision_instance postgres-test test.user
provision_instance postgres-prod prod.user

echo ""
echo "Done. Connect: database datalake, users dev.user / test.user / prod.user, password $POSTGRES_PASSWORD"
