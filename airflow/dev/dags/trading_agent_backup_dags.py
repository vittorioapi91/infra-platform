#!/usr/bin/env python3
"""
Trading Agent Database Backup DAG

Cascades database backups from prod → test → dev:
- Daily: prod → dev (full replacement)
- Weekly: prod → test (full replacement)

This DAG backs up specific databases from prod and restores them to test/dev environments.
"""

from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator
import os
import subprocess
import logging
import shutil

logger = logging.getLogger(__name__)

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

# Database connection details
DB_CONFIG = {
    'prod': {
        'host': 'postgres-ta-prod',
        'user': 'prod.tradingAgent',
        'port': '5432',
    },
    'test': {
        'host': 'postgres-ta-test',
        'user': 'test.tradingAgent',
        'port': '5432',
    },
    'dev': {
        'host': 'postgres-ta-dev',
        'user': 'dev.tradingAgent',
        'port': '5432',
    },
}


def backup_and_restore_database(source_env: str, target_env: str, db_name: str, **context):
    """
    Backup a single database from source environment and restore to target environment.
    
    Args:
        source_env: Source environment ('prod')
        target_env: Target environment ('test' or 'dev')
        db_name: Name of the database to backup/restore
    """
    source_config = DB_CONFIG[source_env]
    target_config = DB_CONFIG[target_env]
    
    # Create temporary directory for backup
    backup_dir = f"/tmp/postgres_backup_{source_env}_to_{target_env}_{context['ds']}"
    os.makedirs(backup_dir, exist_ok=True)
    backup_file = f"{backup_dir}/{db_name}.dump"
    
    logger.info(f"Starting backup of '{db_name}' from {source_env} to {target_env}")
    logger.info(f"Backup file: {backup_file}")
    
    try:
        # Backup from source
        logger.info(f"Backing up database '{db_name}' from {source_env}...")
        backup_cmd = [
            'pg_dump',
            '-Fc',  # Custom format (compressed, allows parallel restore)
            '-h', source_config['host'],
            '-p', source_config['port'],
            '-U', source_config['user'],
            '-d', db_name,
            '-f', backup_file,
        ]
        
        subprocess.run(
            backup_cmd,
            check=True,
            env={'PGPASSWORD': POSTGRES_PASSWORD},
            capture_output=True,
            text=True
        )
        logger.info(f"Backed up '{db_name}' to {backup_file}")
        
        # Drop and recreate database in target (if exists)
        logger.info(f"Dropping and recreating database '{db_name}' in {target_env}...")
        
        # First, terminate all connections to the database
        terminate_cmd = [
            'psql',
            f"postgresql://{target_config['user']}:{POSTGRES_PASSWORD}@{target_config['host']}:{target_config['port']}/postgres",
            '-c', f"SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '{db_name}' AND pid <> pg_backend_pid();"
        ]
        subprocess.run(
            terminate_cmd,
            env={'PGPASSWORD': POSTGRES_PASSWORD},
            capture_output=True,
            text=True
        )
        
        # Drop and recreate
        drop_cmd = [
            'psql',
            f"postgresql://{target_config['user']}:{POSTGRES_PASSWORD}@{target_config['host']}:{target_config['port']}/postgres",
            '-c', f"DROP DATABASE IF EXISTS \"{db_name}\";",
            '-c', f"CREATE DATABASE \"{db_name}\" OWNER \"{target_config['user']}\";"
        ]
        
        subprocess.run(
            drop_cmd,
            check=True,
            env={'PGPASSWORD': POSTGRES_PASSWORD},
            capture_output=True,
            text=True
        )
        logger.info(f"Recreated database '{db_name}' in {target_env}")
        
        # Restore to target
        logger.info(f"Restoring database '{db_name}' to {target_env}...")
        restore_cmd = [
            'pg_restore',
            '-Fc',  # Custom format
            '-h', target_config['host'],
            '-p', target_config['port'],
            '-U', target_config['user'],
            '-d', db_name,
            '--no-owner',  # Don't try to set ownership (permissions)
            '--no-acl',    # Don't restore access privileges
            backup_file,
        ]
        
        result = subprocess.run(
            restore_cmd,
            env={'PGPASSWORD': POSTGRES_PASSWORD},
            capture_output=True,
            text=True
        )
        
        # pg_restore returns 1 for warnings, 0 for success
        if result.returncode not in [0, 1]:
            logger.error(f"Failed to restore '{db_name}': {result.stderr}")
            raise subprocess.CalledProcessError(result.returncode, restore_cmd, result.stderr)
        
        logger.info(f"Successfully restored '{db_name}' to {target_env}")
        
    except FileNotFoundError as e:
        logger.error(f"PostgreSQL client tools not found: {e}")
        raise
    except subprocess.CalledProcessError as e:
        logger.error(f"Error processing database '{db_name}': {e.stderr}")
        raise
    finally:
        # Cleanup backup directory
        if os.path.exists(backup_dir):
            shutil.rmtree(backup_dir, ignore_errors=True)
            logger.info(f"Cleaned up backup directory: {backup_dir}")


# Wrapper functions for specific databases
def backup_edgar_prod_to_dev(**context):
    """Wrapper: Backup edgar database from prod to dev"""
    backup_and_restore_database('prod', 'dev', 'edgar', **context)


def backup_edgar_prod_to_test(**context):
    """Wrapper: Backup edgar database from prod to test"""
    backup_and_restore_database('prod', 'test', 'edgar', **context)


# Create DAG for daily dev backup (prod → dev)
dag_dev = DAG(
    'database_backup_prod_to_dev',
    default_args=default_args,
    description='Daily backup: Restore dev databases from prod',
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
    description='Weekly backup: Restore test databases from prod',
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
