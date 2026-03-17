#!/bin/sh
# Run Prisma Studio on port 5555 (must match nginx proxy)
# Usage: docker exec -it prisma-ta-dev sh /workspace/prisma/studio.sh
cd /workspace/prisma && npx prisma studio --port 5555
