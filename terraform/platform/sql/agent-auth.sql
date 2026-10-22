-- Run once, as doadmin, against the `hepta` database — the same connection as
-- bootstrap.sql. See ../README.md.
--
-- agent-auth's database and role exist as Terraform resources; what they lack
-- is what only doadmin can grant. The database is doadmin's, and PostgreSQL 15+
-- gives non-owners no CREATE on `public`, so without this the agent-auth
-- migration Job cannot create a table. No extensions: its migrations use
-- gen_random_uuid(), which is core since PostgreSQL 13.
--
-- It also closes CONNECT to PUBLIC on both databases, so each role reaches only
-- its own. app_user already holds an explicit CONNECT on `hepta` from
-- bootstrap.sql, which is what makes revoking PUBLIC's safe there.
--
-- Idempotent, like bootstrap.sql.

REVOKE CONNECT ON DATABASE hepta FROM PUBLIC;
REVOKE CONNECT ON DATABASE agent_auth FROM PUBLIC;
GRANT CONNECT ON DATABASE agent_auth TO agent_auth_user;

-- Schema privileges are per database, so the rest has to run inside it.
-- \connect keeps the host, port, user, password and sslmode of the current
-- connection and changes only the database.
\connect agent_auth

-- agent_auth_user creates every table itself and so owns them; unlike
-- bootstrap.sql, no table or sequence grants are needed.
GRANT USAGE, CREATE ON SCHEMA public TO agent_auth_user;
