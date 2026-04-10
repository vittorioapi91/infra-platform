#!/usr/bin/env bash
# Run Prisma Studio for a database. Usage: ./run-studio.sh [dev|test|prod]
set -e
CONTAINER="${1:-dev}"
PASSWORD="${POSTGRES_PASSWORD:-2014}"

case "$CONTAINER" in
  dev)
    URL="postgresql://dev.user:${PASSWORD}@postgres-dev:5432/datalake?options=-c%20search_path%3Dpostgres"
    PRISMA_CONTAINER="prisma-ta-dev"
    HOST_PORT=5555
    ;;
  test)
    URL="postgresql://test.user:${PASSWORD}@postgres-test:5432/datalake?options=-c%20search_path%3Dpostgres"
    PRISMA_CONTAINER="prisma-ta-test"
    HOST_PORT=5556
    ;;
  prod)
    URL="postgresql://prod.user:${PASSWORD}@postgres-prod:5432/datalake?options=-c%20search_path%3Dpostgres"
    PRISMA_CONTAINER="prisma-ta-prod"
    HOST_PORT=5557
    ;;
  *)
    echo "Usage: $0 [dev|test|prod]"
    echo "  dev  -> http://localhost:5555"
    echo "  test -> http://localhost:5556"
    echo "  prod -> http://localhost:5557"
    exit 1
    ;;
esac

echo "Starting Prisma Studio for $CONTAINER..."
echo "Open: http://localhost:$HOST_PORT"
docker exec -it -e HOST_PORT="$HOST_PORT" "$PRISMA_CONTAINER" sh -c 'cd /workspace/prisma && npx prisma studio --port 5555 --browser none --url "'"$URL"'" 2>&1 | sed "s|localhost:5555|localhost:$HOST_PORT|g"'
