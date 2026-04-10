# Other storage (DAG file writes, etc.)

Canonical TA storage root is `/Volumes/storage-volume/storage/{env}` (configured via `TRADING_AGENT_STORAGE` in `.env.tradingAgent.{env}`).
The legacy bind mount at `/workspace/storage-other-data` is still present for compatibility.

Legacy layout (compatibility only):

```
storage-other-data/
├── ta/           # TradingAgent
│   ├── dev/
│   │   └── fundamentals/
│   │       └── edgar/
│   ├── test/
│   │   └── fundamentals/
│   │       └── edgar/
│   └── prod/
│       └── fundamentals/
│           └── edgar/
└── pma/          # PredictionMarketsAgent (no DAGs yet)
    ├── dev/
    ├── test/
    └── prod/
```

TA DAGs should read/write using `TRADING_AGENT_STORAGE` instead of hardcoding `/workspace/storage-other-data` paths.
Folder structure here is committed; contents are gitignored (see root `.gitignore`).
