# Postgres data storage (host filesystem)

PostgreSQL data for the six logical servers lives here **outside** Docker volumes. Each directory is bind-mounted into its container.

```
storage-postgresql/
├── pma/          # PredictionMarketsAgent
│   ├── dev/      → postgres-pma-dev
│   ├── test/     → postgres-pma-test
│   └── prod/     → postgres-pma-prod
└── ta/           # TradingAgent
    ├── dev/      → postgres-ta-dev
    ├── test/     → postgres-ta-test
    └── prod/     → postgres-ta-prod
```

Containers use these paths via `../storage-postgresql/...` in `docker/docker-compose.infra-platform.yml`. Do not remove these directories while Postgres containers are running.
