// tests/fixtures/ci/tbc-node-violation.ts
//
// DELIBERATELY OUTSIDE TenantBoundClient — TBC-node golden-test fixture (Node/TS
// provider-sync analogue of tbc-violation.py). Covers both fence legs:
//   LEG 1 — raw-client construction outside the tenant-binding class:
//     (1) postgres.js factory  postgres();
//     (2) node-postgres        new Pool() / new Client();
//     (3) Supabase admin JS    createClient();  (BANNED in the worker entirely)
//     (4) Supabase client import  from '@supabase/supabase-js'.
//   LEG 2 — service-role-key absence tripwire (Sec condition):
//     (5) a literal service-role-key env reference (must be ABSENT).
// NOTE: this fixture deliberately keeps the literal key token to a SINGLE code line
// (the const below) and uses prose everywhere else — leg 2 is strict zero-hit with
// NO comment-skip, so it models the discipline it enforces (worker source must not
// spam the literal token even in comments).
// The TBC-node fence MUST report violation against this file at every CI invocation.
//
// CI inversion check: the fence script MUST flag this fixture at every run. If the
// fence reports clean, CI fails closed — the fence is broken.
//
// Fixture path discipline (mirrors tbc-violation.py): this file lives at
// tests/fixtures/ci/ — OUTSIDE every Coolify Base Directory (workers/provider-sync/
// et al.) by construction, and excluded from every production build context via the
// repo-root .dockerignore. It is NEVER runtime-loadable in any production container,
// so the raw connections below are inert. Without that isolation, fixture-as-attack-
// surface is exactly what this discipline prevents.
//
// Patterns are referenced VERBATIM (real driver/client names, not mock identifiers)
// so the fixture exercises the fence's actual regex, not a stand-in.
//
// DO NOT use this file as a template for any worker code; use the TenantBoundClient
// class (Backend-owned, workers/provider-sync/src/) instead.

// (1) postgres.js factory — porsager postgres.js. Bypasses TenantBoundClient's
//     users_id binding. Lock 13 mod #3 V1-SHIP-BLOCK.
import postgres from 'postgres';
const sql = postgres('postgresql://service_role:fake-fixture-password@localhost/pfin');

// (2) node-postgres — raw Pool + Client construction outside the class.
import { Pool, Client } from 'pg';
const pool = new Pool({ host: 'localhost', database: 'pfin', user: 'service_role' });
const client = new Client({ host: 'localhost', database: 'pfin', user: 'service_role' });

// (3) + (4) Supabase admin JS client — BANNED in the worker. Using it would pull
//     provider-sync onto the RT-26 service-role-key allowlist, which the
//     direct-Postgres transport decision explicitly avoids. The fence catches both
//     the import and the createClient() construction (LEG 1).
import { createClient } from '@supabase/supabase-js';
const admin = createClient('https://example.supabase.co', 'fake-fixture-service-role-key');

// (5) LEG 2 tripwire — the literal service-role-key env var must be ABSENT from
//     provider-sync source. This real env read exercises the absence tripwire (the
//     value is a fake fixture credential; the file is never runtime-loadable). Even
//     without the createClient() above, THIS line alone must trip the fence.
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

export { sql, pool, client, admin, serviceRoleKey };
