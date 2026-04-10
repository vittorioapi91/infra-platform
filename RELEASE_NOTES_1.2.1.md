# Release Notes v1.2.1

## Database Backup DAGs and Environment Configuration Improvements

### 🎯 Main Features

#### Database Backup System
- **New Backup DAGs**: Added automated database backup workflows
  - `database_backup_prod_to_dev`: Daily backup at 2 AM (prod → dev)
  - `database_backup_prod_to_test`: Weekly backup on Sundays at 3 AM (prod → test)
  - Currently configured for `edgar` database
  - Uses PostgreSQL `pg_dump` and `pg_restore` for efficient backups
  - Fully replaces target databases with production content

#### Environment Configuration
- **Fixed Environment Loading Warnings**
  - Removed unnecessary warnings when `.env` files are not found
  - Environment variables now properly loaded from `trading_agent_dags.py` before DAG imports
  - Cleaner logging output in Airflow DAG runs
  - Better error handling for missing configuration files

### 🔧 Infrastructure Improvements

- **PostgreSQL Client Tools**
  - Added automatic installation of PostgreSQL client tools (`pg_dump`, `pg_restore`, `psql`) to all Airflow containers
  - Tools are installed during container startup if not already present
  - Enables backup DAGs to function without manual setup

- **DAG Import Script Updates**
  - Improved `.env` file loading in `create-dag-imports.sh`
  - Better fallback handling for environment files
  - Cleaner error messages and logging

- **Gateway Configuration**
  - Enhanced nginx configuration for PostgreSQL streaming
  - Improved gateway documentation
  - Better separation of concerns for environment variables

### 📝 Technical Details

**Backup Process:**
1. Creates compressed backup using `pg_dump -Fc` (custom format)
2. Terminates existing connections to target database
3. Drops and recreates target database
4. Restores from backup using `pg_restore`
5. Cleans up temporary backup files

**Environment Loading:**
- Environment variables are now loaded once at the top level in `trading_agent_dags.py`
- All DAGs inherit these variables automatically
- No need for individual DAGs to load environment files
- Reduces duplicate code and warnings

### 🚀 Migration Notes

- **No breaking changes**
- Backup DAGs will appear automatically in Airflow after container restart
- Existing DAGs continue to work without modification
- PostgreSQL client tools are installed automatically on container startup

### 📦 Files Changed

- `airflow/dev/dags/trading_agent_backup_dags.py` (new)
- `airflow/dev/dags/trading_agent_dags.py` (updated)
- `airflow/create-dag-imports.sh` (updated)
- `docker/docker-compose.infra-platform.yml` (updated)

---

**Tag:** v1.2.1  
**Date:** 2024-01-26  
**Branch:** main
