-- Explicit feast schema for feature engineering (dbt + HP filter).
-- Run manually when provisioning an existing datalake (not at app startup).
-- New Postgres instances: also added in docker/init-pg-datalake-*.sql

CREATE SCHEMA IF NOT EXISTS feast;

GRANT USAGE ON SCHEMA feast TO postgres;
GRANT CREATE ON SCHEMA feast TO postgres;
GRANT ALL ON ALL TABLES IN SCHEMA feast TO postgres;
GRANT ALL ON ALL SEQUENCES IN SCHEMA feast TO postgres;

-- Repeat for env users as needed, e.g. dev.user:
-- GRANT USAGE ON SCHEMA feast TO "dev.user";
-- GRANT ALL ON ALL TABLES IN SCHEMA feast TO "dev.user";
