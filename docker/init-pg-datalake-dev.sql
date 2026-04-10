-- Create datalake database and dev structure (TA + PMA dev).
-- Runs as bootstrap superuser when PGDATA is empty (first start).

-- App user for connections (gateway/README: dev.user, password 2014)
CREATE USER "dev.user" WITH PASSWORD '2014' LOGIN CREATEDB;

CREATE DATABASE datalake OWNER "dev.user";

\c datalake

-- Schemas: TA/PMA + data sources + public (Prisma/ad-hoc)
CREATE SCHEMA IF NOT EXISTS postgres;
CREATE SCHEMA IF NOT EXISTS polymarket;
CREATE SCHEMA IF NOT EXISTS edgar;
CREATE SCHEMA IF NOT EXISTS nasdaqtrader;
CREATE SCHEMA IF NOT EXISTS ishares;
CREATE SCHEMA IF NOT EXISTS fred;
CREATE SCHEMA IF NOT EXISTS bls;
CREATE SCHEMA IF NOT EXISTS bis;
CREATE SCHEMA IF NOT EXISTS eurostat;
CREATE SCHEMA IF NOT EXISTS imf;
CREATE SCHEMA IF NOT EXISTS yfinance;
CREATE SCHEMA IF NOT EXISTS public;

-- Schema list used in GRANTs below (keep in sync with docker/provision-datalakes.sh SCHEMAS)
-- postgres, polymarket, edgar, nasdaqtrader, ishares, fred, bls, bis, eurostat, imf, yfinance, public

GRANT ALL ON DATABASE datalake TO postgres;
GRANT USAGE ON SCHEMA postgres, polymarket, edgar, nasdaqtrader, ishares, fred, bls, bis, eurostat, imf, yfinance, public TO postgres;
GRANT CREATE ON SCHEMA postgres, polymarket, edgar, nasdaqtrader, ishares, fred, bls, bis, eurostat, imf, yfinance, public TO postgres;
GRANT ALL ON ALL TABLES IN SCHEMA postgres, polymarket, edgar, nasdaqtrader, ishares, fred, bls, bis, eurostat, imf, yfinance, public TO postgres;
GRANT ALL ON ALL SEQUENCES IN SCHEMA postgres, polymarket, edgar, nasdaqtrader, ishares, fred, bls, bis, eurostat, imf, yfinance, public TO postgres;

GRANT USAGE ON SCHEMA postgres, polymarket, edgar, nasdaqtrader, ishares, fred, bls, bis, eurostat, imf, yfinance, public TO "dev.user";
GRANT CREATE ON SCHEMA postgres, polymarket, edgar, nasdaqtrader, ishares, fred, bls, bis, eurostat, imf, yfinance, public TO "dev.user";
GRANT ALL ON ALL TABLES IN SCHEMA postgres, polymarket, edgar, nasdaqtrader, ishares, fred, bls, bis, eurostat, imf, yfinance, public TO "dev.user";
GRANT ALL ON ALL SEQUENCES IN SCHEMA postgres, polymarket, edgar, nasdaqtrader, ishares, fred, bls, bis, eurostat, imf, yfinance, public TO "dev.user";

ALTER DEFAULT PRIVILEGES IN SCHEMA postgres GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES IN SCHEMA postgres GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES IN SCHEMA polymarket GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES IN SCHEMA polymarket GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES IN SCHEMA edgar GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES IN SCHEMA edgar GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES IN SCHEMA nasdaqtrader GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES IN SCHEMA nasdaqtrader GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES IN SCHEMA ishares GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES IN SCHEMA ishares GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES IN SCHEMA fred GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES IN SCHEMA fred GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES IN SCHEMA bls GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES IN SCHEMA bls GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES IN SCHEMA bis GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES IN SCHEMA bis GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES IN SCHEMA eurostat GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES IN SCHEMA eurostat GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES IN SCHEMA imf GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES IN SCHEMA imf GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES IN SCHEMA yfinance GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES IN SCHEMA yfinance GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;

ALTER DEFAULT PRIVILEGES IN SCHEMA postgres GRANT ALL ON TABLES TO "dev.user";
ALTER DEFAULT PRIVILEGES IN SCHEMA postgres GRANT ALL ON SEQUENCES TO "dev.user";
ALTER DEFAULT PRIVILEGES IN SCHEMA polymarket GRANT ALL ON TABLES TO "dev.user";
ALTER DEFAULT PRIVILEGES IN SCHEMA polymarket GRANT ALL ON SEQUENCES TO "dev.user";
ALTER DEFAULT PRIVILEGES IN SCHEMA edgar GRANT ALL ON TABLES TO "dev.user";
ALTER DEFAULT PRIVILEGES IN SCHEMA edgar GRANT ALL ON SEQUENCES TO "dev.user";
ALTER DEFAULT PRIVILEGES IN SCHEMA nasdaqtrader GRANT ALL ON TABLES TO "dev.user";
ALTER DEFAULT PRIVILEGES IN SCHEMA nasdaqtrader GRANT ALL ON SEQUENCES TO "dev.user";
ALTER DEFAULT PRIVILEGES IN SCHEMA ishares GRANT ALL ON TABLES TO "dev.user";
ALTER DEFAULT PRIVILEGES IN SCHEMA ishares GRANT ALL ON SEQUENCES TO "dev.user";
ALTER DEFAULT PRIVILEGES IN SCHEMA fred GRANT ALL ON TABLES TO "dev.user";
ALTER DEFAULT PRIVILEGES IN SCHEMA fred GRANT ALL ON SEQUENCES TO "dev.user";
ALTER DEFAULT PRIVILEGES IN SCHEMA bls GRANT ALL ON TABLES TO "dev.user";
ALTER DEFAULT PRIVILEGES IN SCHEMA bls GRANT ALL ON SEQUENCES TO "dev.user";
ALTER DEFAULT PRIVILEGES IN SCHEMA bis GRANT ALL ON TABLES TO "dev.user";
ALTER DEFAULT PRIVILEGES IN SCHEMA bis GRANT ALL ON SEQUENCES TO "dev.user";
ALTER DEFAULT PRIVILEGES IN SCHEMA eurostat GRANT ALL ON TABLES TO "dev.user";
ALTER DEFAULT PRIVILEGES IN SCHEMA eurostat GRANT ALL ON SEQUENCES TO "dev.user";
ALTER DEFAULT PRIVILEGES IN SCHEMA imf GRANT ALL ON TABLES TO "dev.user";
ALTER DEFAULT PRIVILEGES IN SCHEMA imf GRANT ALL ON SEQUENCES TO "dev.user";
ALTER DEFAULT PRIVILEGES IN SCHEMA yfinance GRANT ALL ON TABLES TO "dev.user";
ALTER DEFAULT PRIVILEGES IN SCHEMA yfinance GRANT ALL ON SEQUENCES TO "dev.user";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO "dev.user";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO "dev.user";

ALTER USER postgres SET search_path TO postgres;
ALTER USER "dev.user" SET search_path TO postgres;
