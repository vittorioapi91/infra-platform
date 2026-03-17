#!/usr/bin/env bash
# Run Prisma Studio for a database. Usage: ./run-studio.sh [ta-dev|ta-test|ta-prod|pma-dev|pma-test|pma-prod]
set -e
CONTAINER="${1:-ta-dev}"
PASSWORD="${POSTGRES_PASSWORD:-2014}"

case "$CONTAINER" in
  ta-dev)   URL="postgresql://dev.tradingAgent:${PASSWORD}@postgres-ta-dev:5432/postgres"   ; HOST_PORT=5555 ;;
  ta-test)  URL="postgresql://test.tradingAgent:${PASSWORD}@postgres-ta-test:5432/postgres" ; HOST_PORT=5556 ;;
  ta-prod)  URL="postgresql://prod.tradingAgent:${PASSWORD}@postgres-ta-prod:5432/postgres" ; HOST_PORT=5557 ;;
  pma-dev)  URL="postgresql://dev.user:${PASSWORD}@postgres-ta-dev:5432/datalake?options=-c%20search_path%3Dpolymarket" ; HOST_PORT=5558 ;;
  pma-test) URL="postgresql://test.user:${PASSWORD}@postgres-ta-test:5432/datalake?options=-c%20search_path%3Dtest.PredictionMarketsAgent" ; HOST_PORT=5559 ;;
  pma-prod) URL="postgresql://prod.user:${PASSWORD}@postgres-ta-prod:5432/datalake?options=-c%20search_path%3Dpostgres" ; HOST_PORT=5560 ;;
  *)
    echo "Usage: $0 [ta-dev|ta-test|ta-prod|pma-dev|pma-test|pma-prod]"
    echo "  ta-dev   -> http://localhost:5555"
    echo "  ta-test  -> http://localhost:5556"
    echo "  ta-prod  -> http://localhost:5557"
    echo "  pma-dev  -> http://localhost:5558"
    echo "  pma-test -> http://localhost:5559"
    echo "  pma-prod -> http://localhost:5560"
    exit 1
    ;;
esac

echo "Starting Prisma Studio for $CONTAINER..."
echo "Open: http://localhost:$HOST_PORT"
docker exec -it -e HOST_PORT="$HOST_PORT" "prisma-${CONTAINER}" sh -c 'cd /workspace/prisma && npx prisma studio --port 5555 --browser none --url "'"$URL"'" 2>&1 | sed "s|localhost:5555|localhost:$HOST_PORT|g"'
