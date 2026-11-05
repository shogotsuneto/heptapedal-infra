-- Run once, as doadmin, against the `hepta` database — the same connection as
-- bootstrap.sql and agent-auth.sql. See ../README.md.
--
-- orderassist's database and role exist as Terraform resources; what they lack
-- is what only doadmin can grant. The database is doadmin's, and PostgreSQL 15+
-- gives non-owners no CREATE on `public`, so without this the core cannot run
-- its migrations. No extensions: its migrations use none.
--
-- It also closes CONNECT to PUBLIC on the new database, so no other
-- application's role can reach it, as agent-auth.sql does for the others.
--
-- Idempotent, like the other two.

REVOKE CONNECT ON DATABASE orderassist FROM PUBLIC;
GRANT CONNECT ON DATABASE orderassist TO orderassist_user;

-- Schema privileges are per database, so the rest has to run inside it.
\connect orderassist

-- The core creates every table itself and so owns them; no table or sequence
-- grants are needed.
GRANT USAGE, CREATE ON SCHEMA public TO orderassist_user;
