#!/usr/bin/env node
// generate-import-hash-copy.mjs — emits the byte-identical, banner-marked copy of the canonical
// import_hash module into the SvelteKit tier (SELF-204 / ADR-034 D4; Location B, F/CTO-ratified).
//
// The canonical source of truth is workers/provider-sync/src/shared/importHash.ts. This script
// copies it verbatim (prepending a static GENERATED banner) to api/src/lib/server/dedup/
// importHash.ts so BOTH tiers import the SAME hash logic without a copy-paste that could drift.
//
// DETERMINISTIC BY CONTRACT (DevOps fence ask #1): the banner is static (no timestamps / no host
// paths / no argv echo), the body is the source file byte-for-byte, and the output is exactly
// `BANNER + sourceContent` (fixed ordering, LF newlines preserved from the source, single EOF).
// DevOps's CI fence runs this script then `git diff --exit-code <out>` — so the committed copy MUST
// equal this script's output exactly. Never hand-edit the copy: edit the canonical source and re-run.
//
// PARAMETERIZED INVOCATION (DevOps fence ask #2):
//   node scripts/generate-import-hash-copy.mjs [--source <path>] [--out <path>] [--stdout]
//     --source <path>   canonical source to copy   (default: workers/provider-sync/src/shared/importHash.ts)
//     --out <path>      destination for the copy    (default: api/src/lib/server/dedup/importHash.ts)
//     --stdout          write to stdout instead of --out (for golden comparison / piping)
//   Defaults reproduce the real canonical→copy generation. The flags let the inversion golden point
//   the generator at a golden source + golden out to prove the fence goes RED, without touching the
//   real copy. The static banner is NOT parameterized (output stays deterministic + path-stable).

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = new URL('../', import.meta.url); // repo root (this script lives in scripts/)
const DEFAULT_SRC = fileURLToPath(new URL('workers/provider-sync/src/shared/importHash.ts', root));
const DEFAULT_OUT = fileURLToPath(new URL('api/src/lib/server/dedup/importHash.ts', root));

/** Minimal, dependency-free flag parse: --source <p>, --out <p>, --stdout. */
function parseArgs(argv) {
	const opts = { source: DEFAULT_SRC, out: DEFAULT_OUT, stdout: false };
	for (let i = 0; i < argv.length; i++) {
		const a = argv[i];
		if (a === '--stdout') opts.stdout = true;
		else if (a === '--source') opts.source = argv[++i];
		else if (a === '--out') opts.out = argv[++i];
		else if (a.startsWith('--source=')) opts.source = a.slice('--source='.length);
		else if (a.startsWith('--out=')) opts.out = a.slice('--out='.length);
		else {
			console.error(`[generate-import-hash-copy] unknown argument: ${a}`);
			process.exit(2);
		}
	}
	if (!opts.source || (!opts.out && !opts.stdout)) {
		console.error('[generate-import-hash-copy] usage: [--source <path>] [--out <path>] [--stdout]');
		process.exit(2);
	}
	return opts;
}

const BANNER =
	'// GENERATED — DO NOT EDIT.\n' +
	'// Source of truth: workers/provider-sync/src/shared/importHash.ts\n' +
	'// Regenerate: node scripts/generate-import-hash-copy.mjs\n' +
	'// This byte-identical copy lets the SvelteKit tier import the SAME canonical import_hash as\n' +
	'// the provider-sync worker (SELF-204 / ADR-034 D4, Location B). A CI byte-equality fence\n' +
	'// fails on any drift. Edit the source, then regenerate — never hand-edit this file.\n' +
	'\n';

const opts = parseArgs(process.argv.slice(2));
const output = BANNER + readFileSync(opts.source, 'utf8');

if (opts.stdout) {
	process.stdout.write(output);
} else {
	mkdirSync(dirname(opts.out), { recursive: true });
	writeFileSync(opts.out, output, 'utf8');
	console.error(`[generate-import-hash-copy] wrote ${opts.out}\n  from ${opts.source}`);
}
