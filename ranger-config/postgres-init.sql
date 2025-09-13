-- PostgreSQL initialization script for Apache Ranger

-- Create ranger database if not exists
SELECT 'CREATE DATABASE ranger'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'ranger');

-- Grant all privileges to ranger user
GRANT ALL PRIVILEGES ON DATABASE ranger TO ranger;

-- Connect to ranger database
\c ranger;

-- Create schema
CREATE SCHEMA IF NOT EXISTS ranger AUTHORIZATION ranger;

-- Set search path
ALTER DATABASE ranger SET search_path TO ranger, public;

-- Grant schema permissions
GRANT ALL ON SCHEMA ranger TO ranger;
GRANT ALL ON SCHEMA public TO ranger;

-- Create extension for UUID support (if needed)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Set default privileges for ranger user
ALTER DEFAULT PRIVILEGES IN SCHEMA ranger GRANT ALL ON TABLES TO ranger;
ALTER DEFAULT PRIVILEGES IN SCHEMA ranger GRANT ALL ON SEQUENCES TO ranger;
ALTER DEFAULT PRIVILEGES IN SCHEMA ranger GRANT ALL ON FUNCTIONS TO ranger;

-- Set timezone (optional, adjust as needed)
SET timezone = 'UTC';

-- Performance tuning for Ranger (optional)
ALTER SYSTEM SET max_connections = 200;
ALTER SYSTEM SET shared_buffers = '256MB';
ALTER SYSTEM SET effective_cache_size = '1GB';
ALTER SYSTEM SET maintenance_work_mem = '64MB';
ALTER SYSTEM SET checkpoint_completion_target = 0.9;
ALTER SYSTEM SET wal_buffers = '16MB';
ALTER SYSTEM SET default_statistics_target = 100;
ALTER SYSTEM SET random_page_cost = 1.1;
ALTER SYSTEM SET effective_io_concurrency = 200;
ALTER SYSTEM SET work_mem = '4MB';
ALTER SYSTEM SET min_wal_size = '1GB';
ALTER SYSTEM SET max_wal_size = '2GB';