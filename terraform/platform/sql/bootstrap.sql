-- Run once, as doadmin, against the `hepta` database. See ../README.md.
--
-- The production counterpart of the application repo's docker/init.sql, minus
-- the parts Terraform already does: the database and the app_user role exist as
-- resources, and DigitalOcean generated the password.
--
-- The grants are the part that needs doadmin: app_user has no CREATE on the
-- schema or the database, cannot grant itself any, and DigitalOcean exposes no
-- API for it. Without them the migration Job cannot create a single table.
--
-- The extensions do not need doadmin — DigitalOcean's pgextwlist allowlist lets
-- app_user create all three — so they could live in the application's
-- migrations instead. They are here because this file has to exist for the
-- grants anyway, and splitting database preparation across two places to save
-- nothing is worse. See ../README.md.

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
