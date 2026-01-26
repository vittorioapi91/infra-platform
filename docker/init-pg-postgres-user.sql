-- Ensure postgres user exists with password 2014 (for PredictionMarketsAgent etc.)
-- When POSTGRES_USER is set, the default "postgres" role is not created.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'postgres') THEN
    CREATE USER postgres WITH PASSWORD '2014' SUPERUSER;
  ELSE
    ALTER USER postgres WITH PASSWORD '2014';
  END IF;
END
$$;
