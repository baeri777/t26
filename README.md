# TRP Platform Environment

This repository provides a modular Docker-based environment for the **TRP** stack. It bundles
PostgreSQL, Redis, a Node.js API, a Svelte web client, and PHP/Apache integration
so you can develop an offline-friendly, push-enabled platform with email-based authentication.

## Services & Ports

| Service      | Description                                                   | Port |
|--------------|---------------------------------------------------------------|------|
| postgres     | PostgreSQL 16 with initial RBAC schema                        | 5432 |
| redis        | Redis 7 with append-only persistence                          | 6379 |
| api          | Node.js + Express API with Socket.IO and config endpoints     | 3000 |
| web          | Svelte SPA served through Vite preview                        | 4173 |
| php          | PHP 8.3 + Apache for modular/legacy features                  | 8080 |
| pgadmin      | pgAdmin 4 for database administration                         | 5050 |

All services communicate through the `trp_net` Docker network, and persistent volumes are defined for
PostgreSQL, Redis, and Node.js dependencies.

## Getting Started

1. Copy `.env.example` to `.env` and populate the Google OAuth credentials that Gmail requires for
   sending transactional emails on your behalf.
2. Build and start the stack:

   ```bash
   ./build.sh
   ```

   The script reports container status and useful URLs once everything is up. For
   interactive log analysis, run `./debug.sh` (optionally with service names).

3. Open the services in your browser:
   - API health check: <http://localhost:3000/healthz>
   - Web client: <http://localhost:4173>
   - pgAdmin: <http://localhost:5050>
   - PHP module host: <http://localhost:8080>

The API exposes `/auth/email`, `/auth/verify`, and `/config` endpoints. It stores short-lived tokens
in Redis, persists users, roles, and configuration entries in PostgreSQL, and emits Socket.IO notifications
every 15 seconds.

### Configuration access

- A default configuration administrator is seeded during database initialization with the credentials
  `admin@example.com` / `ChangeMeNow!`. Use these credentials to authenticate when opening the Config tab
  in the Svelte client or when calling the `/config` endpoints directly.
- **Change the password immediately** once the stack is running. You can update it through `psql` using
  `UPDATE core.users SET password_hash = crypt('your-new-password', gen_salt('bf')) WHERE email = 'admin@example.com';`.
- Configuration requests use HTTP Basic authentication. The Svelte client stores the credentials only in
  memory for the active browser session and prompts again after signing out or when the credentials fail.

## Development Notes

- The API container mounts the local `api/` directory and runs in watch mode for a tight feedback loop.
- Extend `postgres/init.sql` with additional schemas, tables, or seed data required by your modules.
- The Svelte client is a lightweight shell you can expand into a modular application with offline caches
  and background synchronization strategies.
- Use the built-in configuration endpoint and the Config page in the Svelte client to manage dynamic
  settings such as Google mailbox credentials.

With this foundation you can focus on building TRP-specific features—role management, offline sync,
Google OAuth token refresh flows, and rich push notifications—while the infrastructure pieces are ready to go.
