#!/bin/sh
set -eu

PGPASSWORD="${DOLTGRES_PASSWORD:-password}"
PSQL="psql -h 127.0.0.1 -U ${DOLTGRES_USER:-postgres} -d datalake -v ON_ERROR_STOP=1"

set +e
create_out=$(PGPASSWORD="$PGPASSWORD" $PSQL -c 'CREATE USER "dev.user" WITH PASSWORD '\''2014'\'' LOGIN CREATEDB;' 2>&1)
create_status=$?
set -e
if [ "$create_status" -ne 0 ]; then
  echo "$create_out" | grep -qi 'already exists' || {
    echo "$create_out" >&2
    exit 1
  }
fi

PGPASSWORD="$PGPASSWORD" $PSQL -f /opt/doltgres-init/datalake-dev.sql
