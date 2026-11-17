# User and administrator roles

Roles are `USER` and `ADMIN`. Public registration always creates `USER`; a client-supplied role is ignored. Password hashing (scrypt), JWT signatures and active-token checks remain unchanged. Every authenticated request reloads the account from the database, so promotion applies to existing sessions and deleted accounts cannot use old tokens.

## Database rollout

For an existing database, apply `database/migrations/002_roles.sql` first. It adds the default `USER` role and a check constraint transactionally without changing existing accounts, flights, reservations or tokens. Reapplication preserves assigned roles. `database/schema.sql` includes roles for fresh databases; do not use the complete schema as an upgrade migration.

Then apply `database/migrations/003_admin_inicial.sql` only for the authorized initial account. Insert `SET LOCAL ape4.admin_inicial_id = '<authorized-account-uuid>';` immediately after its `BEGIN;` when executing the transaction. Use the exact account UUID explicitly authorized by the owner; never store that private value in source control. The script validates `current_setting('ape4.admin_inicial_id', true)` as a UUID and refuses missing, empty or malformed values. It locks the users table, requires exactly one account matching that UUID, and promotes only that account. If either assertion fails, the whole transaction aborts. Reapplication is safe while that account is still the sole user. After other users register, this bootstrap must fail; use the authenticated promotion endpoint instead. Never change the assertion to bypass a failed bootstrap without verifying and obtaining authorization for the changed state.

Deploy the updated backend only after the role migration succeeds. Keep the Supabase service key on the backend. No public or authenticated-client table grants or RLS policies are introduced. Verify login, current profile and protected actions after deployment. No migration or remote operation was executed as part of preparing these files.

## Endpoints

- `GET /api/auth/perfil`: authenticated, returns `{usuario}` with `id`, `nombre`, `correo`, `rol`.
- `GET /api/admin/usuarios`: ADMIN only, returns an array of public users; never includes password hashes or tokens.
- `POST /api/admin/usuarios/<usuario_id>/promover`: ADMIN only, promotes another existing account to fixed role `ADMIN` and returns `{usuario}`. Self-promotion is rejected; unknown accounts return 404. Repeating promotion of another administrator is harmless. There is no deletion or downgrade endpoint.
- `POST /api/vuelos`: ADMIN only, returns `{vuelo}` with status 201. Required fields: `origen`, `destino` (`City, Country`), ISO `fecha`, `hora_salida`, `hora_llegada` (`HH:MM` or `HH:MM:SS`), nonnegative finite `precio` with up to two decimal places, and positive integer `asientos_disponibles`. Overnight arrivals are allowed. Client IDs and unrelated fields are ignored.

Missing/invalid authentication returns 401; a current USER accessing administrator endpoints receives 403. Existing public flight search, per-user reservations, VAT/XML receipts and local/allowlisted CORS behavior are preserved.

## Checks

Run `uv run --with flask --with pyjwt --with python-dotenv --with pytest python -m pytest backend/tests -q -p no:cacheprovider`. SQL tests check additive structure and bootstrap guardrails only; they do not establish execution against PostgreSQL. Live migration and deployed smoke checks remain rollout responsibilities.
