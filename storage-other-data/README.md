# Other storage (DAG file writes, etc.)

Lives **on the host** at `<repo>/storage-other-data`, outside any Docker image. Bind-mounted into Airflow containers at `/workspace/storage-other-data`.

Layout:

```
storage-other-data/
├── ta/           # TradingAgent
│   ├── dev/
│   ├── test/
│   └── prod/
└── pma/          # PredictionMarketsAgent (no DAGs yet)
    ├── dev/
    ├── test/
    └── prod/
```

TA DAGs use `/workspace/storage-other-data/ta/{env}` (see `trading_agent_dags`).  
Folder structure is committed; contents are gitignored (see root `.gitignore`).
