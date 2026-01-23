# DAG File Writing Patterns

## Overview

All Airflow DAGs that need to write files to disk should write to the **storage directory** (`TradingPythonAgent/storage/{env}/`) via the mounted volume. This ensures files are persisted outside the container, organized by environment, and accessible from the host system.

## Mount Configuration

The storage directory is mounted at `/workspace/storage/{env}/` in each Airflow container and is **writable** by default.

**Container path:** `/workspace/storage/{env}/` (e.g., `/workspace/storage/dev/`)  
**Host path:** `TradingPythonAgent/storage/{env}/` (e.g., `TradingPythonAgent/storage/dev/`)

The storage path is automatically set up when DAGs are imported and is available via:
- Environment variable: `TRADING_AGENT_STORAGE`
- Module attribute: `trading_agent.STORAGE_PATH`

## Writing Pattern

DAGs should write files to the storage directory using the `TRADING_AGENT_STORAGE` environment variable or `trading_agent.STORAGE_PATH`:

```python
import os
from pathlib import Path

# Get storage path (automatically set by DAG import script)
storage_path = os.getenv('TRADING_AGENT_STORAGE', '/workspace/storage/dev')
# Or use: from trading_agent import STORAGE_PATH

# Write files to storage directory, organized by module/feature
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

storage_path = os.getenv('TRADING_AGENT_STORAGE', '/workspace/storage/dev')
output_file = Path(storage_path) / "fundamentals" / "edgar" / "company_tickers.json"
output_file.parent.mkdir(parents=True, exist_ok=True)
# Writes to: TradingPythonAgent/storage/{env}/fundamentals/edgar/company_tickers.json
```

### Macro Data
```python
import os
from pathlib import Path

storage_path = os.getenv('TRADING_AGENT_STORAGE', '/workspace/storage/dev')
data_file = Path(storage_path) / "macro" / "fred" / "data.parquet"
data_file.parent.mkdir(parents=True, exist_ok=True)
# Writes to: TradingPythonAgent/storage/{env}/macro/fred/data.parquet
```

### Markets Data
```python
import os
from pathlib import Path

storage_path = os.getenv('TRADING_AGENT_STORAGE', '/workspace/storage/dev')
parquet_dir = Path(storage_path) / "markets" / "equities" / "yahoo_equities_parquet"
parquet_dir.mkdir(parents=True, exist_ok=True)
# Writes to: TradingPythonAgent/storage/{env}/markets/equities/yahoo_equities_parquet/
```

## Benefits

1. **Persistence:** Files survive container restarts and recreations
2. **Accessibility:** Files are directly accessible from the host system
3. **Version Control:** Files can be committed to git if needed
4. **Consistency:** All DAGs follow the same pattern

## Important Notes

- **Never write to `/opt/airflow/` paths** - these are container-specific and not mounted
- **Always use `TRADING_AGENT_STORAGE` environment variable** - ensures files are written to the correct environment-specific storage
- **The storage mount is writable by default** - no special configuration needed
- **Files written to `/workspace/storage/{env}/`** automatically appear in `TradingPythonAgent/storage/{env}/` on the host
- **Storage is environment-specific** - dev, test, and prod each have their own storage directory
- **Organize files by module/feature** - e.g., `storage/{env}/fundamentals/edgar/`, `storage/{env}/macro/fred/`

## Verification

To verify a file was written correctly:

```bash
# From host
ls -la TradingPythonAgent/storage/dev/fundamentals/edgar/company_tickers.json

# From container
docker exec airflow-dev ls -la /workspace/storage/dev/fundamentals/edgar/company_tickers.json
```

Both commands should show the same file.
