#!/usr/bin/env python3
"""
Trading Agent Database Backup DAG

Cascades schema backups within the datalake database from prod → test → dev:
- Daily: prod → dev (full replacement of selected schemas)
- Weekly: prod → test (full replacement of selected schemas)

All environments use database "datalake" and credentials {env}.user. Schemas have the same
names as the previous database names (e.g. edgar, postgres).
"""

from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator
import os
import subprocess
import logging
import shutil

logger = logging.getLogger(__name__)

# Set up storage path for DAG file writes (TA)
# storage-other-data is mounted at /workspace/storage-other-data; TA uses ta/{env}/
airflow_env = os.getenv('AIRFLOW_ENV', 'dev')
storage_env = airflow_env
storage_root = f"/workspace/storage-other-data/ta/{storage_env}"
if os.path.exists(storage_root):
    # Set environment variable so DAGs can access storage path
    os.environ['TRADING_AGENT_STORAGE'] = storage_root

# These DAGs are only available in prod Airflow (backup prod DB to dev/test)
# When not prod, skip defining the DAGs entirely so they never appear in the UI
if airflow_env == 'prod':

    # Default arguments
    default_args = {
        'owner': 'admin',
        'depends_on_past': False,
        'email_on_failure': False,
        'email_on_retry': False,
        'retries': 1,
        'retry_delay': timedelta(minutes=5),
    }

    # Get database credentials from environment
    POSTGRES_PASSWORD = os.getenv('POSTGRES_PASSWORD', '2014')

    # Database: single "datalake" per env; credentials {env}.user
    DB_NAME = 'datalake'
    DB_CONFIG = {
        'prod': {
            'host': 'postgres-ta-prod',
            'user': 'prod.user',
            'port': '5432',
        },
        'test': {
            'host': 'postgres-ta-test',
            'user': 'test.user',
            'port': '5432',
        },
        'dev': {
            'host': 'postgres-ta-dev',
            'user': 'dev.user',
            'port': '5432',
        },
    }

    def backup_and_restore_schema(source_env: str, target_env: str, schema_name: str, **context):
        """
        Backup a single schema from datalake (source env) and restore into datalake (target env).

        Args:
            source_env: Source environment ('prod')
            target_env: Target environment ('test' or 'dev')
            schema_name: Name of the schema to backup/restore (e.g. 'edgar')
        """
        source_config = DB_CONFIG[source_env]
        target_config = DB_CONFIG[target_env]

        # Create temporary directory for backup
        backup_dir = f"/tmp/postgres_backup_{source_env}_to_{target_env}_{context['ds']}"
        os.makedirs(backup_dir, exist_ok=True)
        backup_file = f"{backup_dir}/{schema_name}.dump"

        logger.info(f"Starting backup of schema '{schema_name}' from {source_env} to {target_env}")
        logger.info(f"Backup file: {backup_file}")

        try:
            # Backup schema from source (datalake)
            logger.info(f"Backing up schema '{schema_name}' from {source_env}...")
            backup_cmd = [
                'pg_dump',
                '-Fc',
                '-h', source_config['host'],
                '-p', source_config['port'],
                '-U', source_config['user'],
                '-d', DB_NAME,
                '-n', schema_name,
                '-f', backup_file,
            ]

            subprocess.run(
                backup_cmd,
                check=True,
                env={'PGPASSWORD': POSTGRES_PASSWORD},
                capture_output=True,
                text=True
            )
            logger.info(f"Backed up schema '{schema_name}' to {backup_file}")

            # Drop and recreate schema in target (datalake)
            logger.info(f"Dropping and recreating schema '{schema_name}' in {target_env}...")
            conn_str = f"postgresql://{target_config['user']}:{POSTGRES_PASSWORD}@{target_config['host']}:{target_config['port']}/{DB_NAME}"

            drop_cmd = [
                'psql',
                conn_str,
                '-c', f'DROP SCHEMA IF EXISTS "{schema_name}" CASCADE;',
                '-c', f'CREATE SCHEMA "{schema_name}";'
            ]
            subprocess.run(
                drop_cmd,
                check=True,
                env={'PGPASSWORD': POSTGRES_PASSWORD},
                capture_output=True,
                text=True
            )
            logger.info(f"Recreated schema '{schema_name}' in {target_env}")

            # Restore schema to target
            logger.info(f"Restoring schema '{schema_name}' to {target_env}...")
            restore_cmd = [
                'pg_restore',
                '-Fc',
                '-h', target_config['host'],
                '-p', target_config['port'],
                '-U', target_config['user'],
                '-d', DB_NAME,
                '-n', schema_name,
                '--no-owner',
                '--no-acl',
                backup_file,
            ]

            result = subprocess.run(
                restore_cmd,
                env={'PGPASSWORD': POSTGRES_PASSWORD},
                capture_output=True,
                text=True
            )

            if result.returncode not in [0, 1]:
                logger.error(f"Failed to restore schema '{schema_name}': {result.stderr}")
                raise subprocess.CalledProcessError(result.returncode, restore_cmd, result.stderr)

            logger.info(f"Successfully restored schema '{schema_name}' to {target_env}")

        except FileNotFoundError as e:
            logger.error(f"PostgreSQL client tools not found: {e}")
            raise
        except subprocess.CalledProcessError as e:
            logger.error(f"Error processing schema '{schema_name}': {e.stderr}")
            raise
        finally:
            # Cleanup backup directory
            if os.path.exists(backup_dir):
                shutil.rmtree(backup_dir, ignore_errors=True)
                logger.info(f"Cleaned up backup directory: {backup_dir}")

    # Wrapper functions for specific schemas in datalake
    def backup_edgar_prod_to_dev(**context):
        """Wrapper: Backup edgar schema from prod to dev"""
        backup_and_restore_schema('prod', 'dev', 'edgar', **context)

    def backup_edgar_prod_to_test(**context):
        """Wrapper: Backup edgar schema from prod to test"""
        backup_and_restore_schema('prod', 'test', 'edgar', **context)

    # Create DAG for daily dev backup (prod → dev)
    dag_dev = DAG(
        'database_backup_prod_to_dev',
        default_args=default_args,
        description='Daily backup: Restore dev datalake schemas from prod',
        schedule_interval='0 2 * * *',  # Daily at 2 AM
        start_date=datetime(2024, 1, 1),
        catchup=False,
        tags=['backup', 'database', 'dev'],
    )

    backup_edgar_prod_to_dev_task = PythonOperator(
        task_id='backup_edgar_prod_to_dev',
        python_callable=backup_edgar_prod_to_dev,
        dag=dag_dev,
    )

    # Create DAG for weekly test backup (prod → test)
    dag_test = DAG(
        'database_backup_prod_to_test',
        default_args=default_args,
        description='Weekly backup: Restore test datalake schemas from prod',
        schedule_interval='0 3 * * 0',  # Weekly on Sunday at 3 AM
        start_date=datetime(2024, 1, 1),
        catchup=False,
        tags=['backup', 'database', 'test'],
    )

    backup_edgar_prod_to_test_task = PythonOperator(
        task_id='backup_edgar_prod_to_test',
        python_callable=backup_edgar_prod_to_test,
        dag=dag_test,
    )
