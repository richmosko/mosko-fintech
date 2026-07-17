// tests/fixtures/ci/tbc-node-basename-collision/adapters/client.ts
//
// The VIOLATOR half of the same-basename collision regression fixture. SAME
// BASENAME (client.ts) as the class file at ../db/client.ts, DIFFERENT directory.
// Constructs a raw node-postgres Pool OUTSIDE the TenantBoundClient class — a real
// Lock 13 mod #3 violation that a correct fence MUST catch.
//
// Under the buggy grep --exclude=client.ts pre-filter this line was silently
// skipped (excluded by basename). Full-path-only exclusion catches it because this
// file's full path (.../adapters/client.ts) does NOT match the allowed class file
// (.../db/client.ts). NOT a template.

import { Pool } from 'pg';

// VIOLATION: raw Pool construction outside TenantBoundClient.
const pool = new Pool({ host: 'localhost', database: 'pfin', user: 'service_role' });

export { pool };
