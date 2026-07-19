// admissionFenceGoldens.qa.test.ts — QA CROSS-CHECK of the C6-1 limb-(b) fence goldens.
//
// SCOPE (QA cross-check, NOT re-authorship): DevOps owns scripts/ci/fence-admission-private-bind.sh
// + the 3 exposure-vector goldens + the negative control; they are wired run-always in
// security-scan.yml (job fence-admission-bind, per Sec F-2). QA independently CONFIRMS the fence
// artifacts exist and TRIP as claimed — my standing discipline: "a fence without a failing golden
// test is theater." This spec shells the fence over each fixture and asserts the exit code, so a
// silently-weakened fence or a golden that stops tripping is caught at the vitest tier too, not
// only inside the CI job definition.
//
// Deterministic: pure filesystem + a bash subprocess; no network, no DB, no sleeps.
//
// Grounding: temp/self212-sec-c6-review.md (C6-1 limb (b), CA-3/CA-5, F-2/F-3) ·
// scripts/ci/fence-admission-private-bind.sh · .github/workflows/security-scan.yml.

import { describe, it, expect } from 'vitest';
import { execFileSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

// tests/ → workers/provider-sync → workers → REPO ROOT
const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');
const FENCE = resolve(REPO_ROOT, 'scripts/ci/fence-admission-private-bind.sh');
const REAL_COMPOSE = resolve(REPO_ROOT, 'workers/provider-sync/docker-compose.yaml');
const FIX = (name: string) => resolve(REPO_ROOT, 'tests/fixtures/ci', name);

const NEGATIVE_CONTROL = FIX('admission-bind-private.compose.yaml');
const GOLDEN_PUBLIC_PORTS = FIX('admission-bind-public-ports.compose.yaml');
const GOLDEN_PUBLIC_DOMAIN = FIX('admission-bind-public-domain.compose.yaml');
const GOLDEN_HOST_NETWORK = FIX('admission-bind-host-network.compose.yaml');

/** Run the fence over a target; return its exit code (0 clean / 1 violation / 2 structural). */
function fenceExit(target: string): number {
	try {
		execFileSync('bash', [FENCE, target], { stdio: 'pipe' });
		return 0;
	} catch (err) {
		const status = (err as { status?: number }).status;
		return typeof status === 'number' ? status : -1;
	}
}

describe('C6-1 fence artifacts exist (QA cross-check)', () => {
	it('the fence script + real compose + all 3 goldens + negative control are present', () => {
		for (const p of [FENCE, REAL_COMPOSE, NEGATIVE_CONTROL, GOLDEN_PUBLIC_PORTS, GOLDEN_PUBLIC_DOMAIN, GOLDEN_HOST_NETWORK]) {
			expect(existsSync(p), `missing fence artifact: ${p}`).toBe(true);
		}
	});
});

describe('C6-1 fence trips as claimed (QA cross-check — exit-code assertions)', () => {
	it('real committed compose → internal-only → PASS (exit 0)', () => {
		expect(fenceExit(REAL_COMPOSE)).toBe(0);
	});

	it('negative-control fixture (correct config) → PASS (exit 0)', () => {
		expect(fenceExit(NEGATIVE_CONTROL)).toBe(0);
	});

	it('golden 1 — published host ports → VIOLATION (exit 1)', () => {
		expect(fenceExit(GOLDEN_PUBLIC_PORTS)).toBe(1);
	});

	it('golden 2 — proxy Domain / Traefik Host() label → VIOLATION (exit 1)', () => {
		expect(fenceExit(GOLDEN_PUBLIC_DOMAIN)).toBe(1);
	});

	it('golden 3 — network_mode: host → VIOLATION (exit 1)', () => {
		expect(fenceExit(GOLDEN_HOST_NETWORK)).toBe(1);
	});
});
