# DAG File Writing Patterns

## Overview

All Airflow DAGs that need to write files to disk should write to `TRADING_AGENT_STORAGE` (canonical root: `/Volumes/storage-volume/storage/{env}` from `.env.tradingAgent.{env}`).
This ensures files are persisted on the host in an environment-specific path.

## Mount Configuration

`TRADING_AGENT_STORAGE` is loaded from `.env.tradingAgent.{env}` and set in DAG bootstrap code.
Legacy compatibility mount: `storage-other-data` at `/workspace/storage-other-data`.

**Canonical path:** `/Volumes/storage-volume/storage/{env}/` (e.g. `/Volumes/storage-volume/storage/dev/`)

The storage path is set up in `trading_agent_dags` and is available via:
- Environment variable: `TRADING_AGENT_STORAGE`
- Module attribute: `trading_agent.STORAGE_PATH`

## Writing Pattern

DAGs should write files using `TRADING_AGENT_STORAGE` or `trading_agent.STORAGE_PATH`:

```python
import os
from pathlib import Path

# Get storage path (set from .env.tradingAgent.{env})
storage_path = os.getenv('TRADING_AGENT_STORAGE', '/Volumes/storage-volume/storage/dev')
# Or use: from trading_agent import STORAGE_PATH

# Write files, organized by module/feature
output_file = Path(storage_path) / "fundamentals" / "edgar" / "company_tickers.json"
output_file.parent.mkdir(parents=True, exist_ok=True)
with open(output_file, 'w') as f:
    f.write(data)
```

## Examples

### EDGAR Fundamentals
```python
import os
from pathlib import Path

storage_path = os.getenv('TRADING_AGENT_STORAGE', '/Volumes/storage-volume/storage/dev')
output_file = Path(storage_path) / "fundamentals" / "edgar" / "company_tickers.json"
output_file.parent.mkdir(parents=True, exist_ok=True)
# Writes to: /Volumes/storage-volume/storage/{env}/fundamentals/edgar/company_tickers.json
```

### Macro Data
```python
import os
from pathlib import Path

storage_path = os.getenv('TRADING_AGENT_STORAGE', '/Volumes/storage-volume/storage/dev')
data_file = Path(storage_path) / "macro" / "fred" / "data.parquet"
data_file.parent.mkdir(parents=True, exist_ok=True)
# Writes to: /Volumes/storage-volume/storage/{env}/macro/fred/data.parquet
```

### Markets Data
```python
import os
from pathlib import Path

storage_path = os.getenv('TRADING_AGENT_STORAGE', '/Volumes/storage-volume/storage/dev')
parquet_dir = Path(storage_path) / "markets" / "equities" / "yahoo_equities_parquet"
parquet_dir.mkdir(parents=True, exist_ok=True)
# Writes to: /Volumes/storage-volume/storage/{env}/markets/equities/yahoo_equities_parquet/
```

## Benefits

1. **Persistence:** Files survive container restarts and recreations
2. **Accessibility:** Files are in `/Volumes/storage-volume/storage/{env}/` on the host
3. **Version Control:** Structure is tracked; contents can be gitignored
4. **Consistency:** All DAGs use the same pattern

## Important Notes

- **Never write to `/opt/airflow/` paths** – container-specific, not mounted
- **Use `TRADING_AGENT_STORAGE`** – ensures environment-specific storage
- **Organize by module/feature** – e.g. `{env}/fundamentals/edgar/`, `{env}/macro/fred/`
- **PMA** path is separate; no PMA DAGs yet.

## Verification

```bash
# From host
ls -la /Volumes/storage-volume/storage/dev/fundamentals/edgar/company_tickers.json

# From container
docker exec airflow-dev ls -la /Volumes/storage-volume/storage/dev/fundamentals/edgar/company_tickers.json
```

Both should show the same file.
