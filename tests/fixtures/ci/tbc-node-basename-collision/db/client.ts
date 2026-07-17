// tests/fixtures/ci/tbc-node-basename-collision/db/client.ts
//
// REGRESSION FIXTURE (Node) for the grep --exclude=<basename> false-negative Sec
// caught 2026-07-17. This file DECLARES `class TenantBoundClient` and legitimately
// constructs the raw postgres() client INSIDE the class — so a correct fence must
// treat THIS file's construction as allowed (full-path exclusion).
//
// The paired violator lives at ../adapters/client.ts — SAME BASENAME (client.ts),
// DIFFERENT directory. The bug: grep --exclude=client.ts would exclude BOTH files
// by basename, silently skipping the violator. The fix (full-path-only exclusion)
// must skip THIS file but CATCH ../adapters/client.ts.
//
// CI expectation: fence-tbc-node.sh run in PRODUCTION mode (class present, no
// --allow-missing-class) against this collision dir MUST exit 1 (the violator trips)
// — NOT exit 0. If it exits 0, the basename false-negative has regressed.
//
// Fixture path discipline: lives under tests/fixtures/ci/, excluded from all build
// contexts via .dockerignore `tests/`; never runtime-loadable. NOT a template.

import postgres from 'postgres';

export class TenantBoundClient {
  private sql;
  private usersId: string;
  constructor(usersId: string) {
    // Legitimate: the SOLE sanctioned raw-client construction, inside the class.
    this.sql = postgres(process.env.PFIN_DB_PASSWORD ?? '');
    this.usersId = usersId;
  }
}
