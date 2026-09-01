-- Run once, as doadmin, against the `hepta` database. See ../README.md.
--
-- The production counterpart of the application repo's docker/init.sql, minus
-- the parts Terraform already does: the database and the app_user role exist as
-- resources, and DigitalOcean generated the password.
--
-- The application's migrations (`sqlx migrate run`) create no extensions, so
-- without this they fail on the first table that uses `vector`.

CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Mirrors docker/init.sql. The migration Job creates tables as app_user, so it
-- needs CREATE on the schema, not only access to what already exists.
GRANT CONNECT ON DATABASE hepta TO app_user;
GRANT USAGE, CREATE ON SCHEMA public TO app_user;
GRANT ALL ON ALL TABLES IN SCHEMA public TO app_user;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO app_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO app_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO app_user;
