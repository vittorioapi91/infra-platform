# DAG File Writing Patterns

## Overview

All Airflow DAGs that need to write files to disk should write to the **storage directory** (`storage-other-data/ta/{env}/` at repo root) via the mounted volume. This ensures files are persisted outside the container, organized by environment, and accessible from the host system.

## Mount Configuration

`storage-other-data` is mounted at `/workspace/storage-other-data` in each Airflow container. TA DAGs use `ta/{env}/` (see `trading_agent_dags`).

**Container path:** `/workspace/storage-other-data/ta/{env}/` (e.g. `/workspace/storage-other-data/ta/dev/`)  
**Host path:** `<repo>/storage-other-data/ta/{env}/` (e.g. `storage-other-data/ta/dev/`)

The storage path is set up in `trading_agent_dags` and is available via:
- Environment variable: `TRADING_AGENT_STORAGE`
- Module attribute: `trading_agent.STORAGE_PATH`

## Writing Pattern

DAGs should write files using `TRADING_AGENT_STORAGE` or `trading_agent.STORAGE_PATH`:

```python
import os
from pathlib import Path

# Get storage path (set by trading_agent_dags)
storage_path = os.getenv('TRADING_AGENT_STORAGE', '/workspace/storage-other-data/ta/dev')
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

storage_path = os.getenv('TRADING_AGENT_STORAGE', '/workspace/storage-other-data/ta/dev')
output_file = Path(storage_path) / "fundamentals" / "edgar" / "company_tickers.json"
output_file.parent.mkdir(parents=True, exist_ok=True)
# Writes to: storage-other-data/ta/{env}/fundamentals/edgar/company_tickers.json
```

### Macro Data
```python
import os
from pathlib import Path

storage_path = os.getenv('TRADING_AGENT_STORAGE', '/workspace/storage-other-data/ta/dev')
data_file = Path(storage_path) / "macro" / "fred" / "data.parquet"
data_file.parent.mkdir(parents=True, exist_ok=True)
# Writes to: storage-other-data/ta/{env}/macro/fred/data.parquet
```

### Markets Data
```python
import os
from pathlib import Path

storage_path = os.getenv('TRADING_AGENT_STORAGE', '/workspace/storage-other-data/ta/dev')
parquet_dir = Path(storage_path) / "markets" / "equities" / "yahoo_equities_parquet"
parquet_dir.mkdir(parents=True, exist_ok=True)
# Writes to: storage-other-data/ta/{env}/markets/equities/yahoo_equities_parquet/
```

## Benefits

1. **Persistence:** Files survive container restarts and recreations
2. **Accessibility:** Files are in `<repo>/storage-other-data/ta/{env}/` on the host
3. **Version Control:** Structure is tracked; contents can be gitignored
4. **Consistency:** All DAGs use the same pattern

## Important Notes

- **Never write to `/opt/airflow/` paths** – container-specific, not mounted
- **Use `TRADING_AGENT_STORAGE`** – ensures environment-specific storage
- **Organize by module/feature** – e.g. `ta/{env}/fundamentals/edgar/`, `ta/{env}/macro/fred/`
- **PMA** uses `storage-other-data/pma/{env}/`; no PMA DAGs yet.

## Verification

```bash
# From host
ls -la storage-other-data/ta/dev/fundamentals/edgar/company_tickers.json

# From container
docker exec airflow-dev ls -la /workspace/storage-other-data/ta/dev/fundamentals/edgar/company_tickers.json
```

Both should show the same file.
