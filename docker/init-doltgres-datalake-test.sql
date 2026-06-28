-- Doltgres bootstrap for test (DOLTGRES_DB=datalake; no CREATE DATABASE or \c).
-- Runs as bootstrap superuser when PGDATA is empty (first start).
-- App user "test.user" is created in init-doltgres-bootstrap-test.sh (idempotent).

-- Schemas: TA/PMA + data sources + public (Prisma/ad-hoc)

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

GRANT ALL ON DATABASE datalake TO postgres;
GRANT USAGE ON SCHEMA postgres, polymarket, edgar, nasdaqtrader, ishares, fred, bls, bis, eurostat, imf, yfinance, public TO postgres;
GRANT CREATE ON SCHEMA postgres, polymarket, edgar, nasdaqtrader, ishares, fred, bls, bis, eurostat, imf, yfinance, public TO postgres;
GRANT ALL ON ALL TABLES IN SCHEMA postgres, polymarket, edgar, nasdaqtrader, ishares, fred, bls, bis, eurostat, imf, yfinance, public TO postgres;
GRANT ALL ON ALL SEQUENCES IN SCHEMA postgres, polymarket, edgar, nasdaqtrader, ishares, fred, bls, bis, eurostat, imf, yfinance, public TO postgres;

GRANT USAGE ON SCHEMA postgres, polymarket, edgar, nasdaqtrader, ishares, fred, bls, bis, eurostat, imf, yfinance, public TO "test.user";
GRANT CREATE ON SCHEMA postgres, polymarket, edgar, nasdaqtrader, ishares, fred, bls, bis, eurostat, imf, yfinance, public TO "test.user";
GRANT ALL ON ALL TABLES IN SCHEMA postgres, polymarket, edgar, nasdaqtrader, ishares, fred, bls, bis, eurostat, imf, yfinance, public TO "test.user";
GRANT ALL ON ALL SEQUENCES IN SCHEMA postgres, polymarket, edgar, nasdaqtrader, ishares, fred, bls, bis, eurostat, imf, yfinance, public TO "test.user";



