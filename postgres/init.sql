CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS core AUTHORIZATION trp_app;

CREATE TABLE IF NOT EXISTS core.users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  email TEXT NOT NULL UNIQUE,
  password_hash TEXT,
  display_name TEXT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  last_login TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS core.roles (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  description TEXT
);

CREATE TABLE IF NOT EXISTS core.user_roles (
  user_id UUID REFERENCES core.users(id) ON DELETE CASCADE,
  role_id INTEGER REFERENCES core.roles(id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, role_id)
);

CREATE TABLE IF NOT EXISTS core.config_entries (
  config_key TEXT PRIMARY KEY,
  config_value TEXT NOT NULL,
  description TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION core.touch_config_entries_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'set_config_entries_updated_at'
      AND tgrelid = 'core.config_entries'::regclass
  ) THEN
    CREATE TRIGGER set_config_entries_updated_at
    BEFORE INSERT OR UPDATE ON core.config_entries
    FOR EACH ROW EXECUTE FUNCTION core.touch_config_entries_updated_at();
  END IF;
END;
$$;

COMMENT ON TABLE core.users IS 'Base user table storing email-first identity data.';
COMMENT ON TABLE core.roles IS 'Role catalog for the RBAC system.';
COMMENT ON TABLE core.user_roles IS 'Join table allowing multiple roles per user.';
COMMENT ON TABLE core.config_entries IS 'Key/value configuration entries that drive dynamic runtime behavior.';

DO $$
DECLARE
  admin_email CONSTANT TEXT := 'admin@example.com';
  admin_password CONSTANT TEXT := 'ChangeMeNow!';
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM core.users WHERE email = admin_email
  ) THEN
    INSERT INTO core.users (email, display_name, password_hash)
    VALUES (
      admin_email,
      'Initial Config Administrator',
      crypt(admin_password, gen_salt('bf'))
    );
  END IF;
END;
$$;
