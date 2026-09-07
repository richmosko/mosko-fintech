# Sec (instance 2) — SELF-349 / A5 joint review at `0c5f54a` (PR #638)

Verdict: **AMBER**. No veto. Nothing in this branch weakens the §10 ledger, overlaps the
secrets stores, gives the PDF worker DB reach, adds a SECURITY DEFINER function, touches the
Decision-3 family, or weakens a CI fence or `TenantBoundConnection`.

**Not executed.** `api/node_modules` is absent in this worktree and `npm ci` is a mutating
command outside my fence, so the battery was reviewed **by reading, not by running**. The
brief's method for item 2 — strike each control on a scratch copy and confirm only its own leg
reds — was **NOT performed by me**. It is handed to QA below as an explicit obligation; treat
every leg-quality finding here as static analysis, not as an inversion result.

---

## F-1 (flag) — the response body is read OUTSIDE the abort window and outside the error guard

`api/src/lib/server/pdf/renderClient.ts`, `renderReportHtml`:

- `clearTimeout(timer)` sits in the `finally` of the `try` that wraps only `fetch(...)`. `fetch`
  resolves when **response headers** arrive. `await res.arrayBuffer()` — the whole PDF download —
  therefore runs with the timer already cleared and the `AbortController` no longer armed. A
  worker (or an intermediary, or an ordinary stalled TCP connection) that dribbles the body holds
  the app request open **indefinitely**. `TIMEOUT_MS = 30_000` bounds the header phase only.
- The same placement puts `await res.arrayBuffer()` outside the `catch`. A mid-body network error
  **throws out of `renderReportHtml`**, contradicting the function's own contract three lines
  above it: *"Returns `{ ok:false, status }` on ANY non-200 … rather than throwing."* P6 and A7
  both branch on the discriminated result and will not have a `try` around the call.

The module states it "Mirrors plaid/admissionClient.ts's shape deliberately". It does not, on
exactly this point: `admissionClient.ts` `callWorker()` reads its body (`await res.json()`)
**inside** the same `try`, with `clearTimeout` in a `finally` that covers the body read. This is a
divergence from the house convention the header claims to follow, not a house-wide gap.

Fix (Backend): move the body read inside the guarded region and clear the timer after it.

```ts
	let res: Response;
	let pdfBytes: Uint8Array;
	try {
		res = await fetch(`${baseUrl}${RENDER_PATH}`, { /* unchanged */ });
		if (res.status !== 200) {
			// (g)'s app-side half — status ONLY, never the body.
			console.error(`[pdf-render] worker returned ${res.status}`);
			return { ok: false, status: res.status };
		}
		pdfBytes = new Uint8Array(await res.arrayBuffer());
	} catch {
		console.error('[pdf-render] worker unreachable (transport failure)');
		return { ok: false, status: 502 };
	} finally {
		clearTimeout(timer);
	}
	return { ok: true, pdfBytes };
```

Catch criterion for the paired legs (QA): (1) a `fetch` stub whose `arrayBuffer()` rejects must
yield `{ ok:false, status:502 }`, never a thrown error; (2) a stub whose `arrayBuffer()` never
settles must be aborted by `TIMEOUT_MS` rather than hanging the spec.

## F-2 (flag) — no leg watches the token's claim SET, which is where the `data_as_of` prohibition lives

SD-20 verbatim: *"V1 app signs short-lived (60s freshness) JWT containing `users_id` claim ONLY
(no `service_role` escalation; no `data_as_of` claim per ADR-011 Decision 19 / Lock 15 mod #7b);
PDF worker verifies signature + freshness + nonce."*

The battery asserts `users_id` present, `exp` undefined, `aud`/`iss` undefined. Nothing asserts
the **exhaustive** key set, so the one prohibition SD-20 names explicitly — a `data_as_of` claim —
has no watcher on either side (the worker ignores unknown claims by construction). The module's
own RT-25 paragraph rests on "no as-of parameter crosses this call"; that is true of the
signature today and untested against tomorrow.

Fix (Backend or QA — one leg):

```ts
	it('the claim set is EXACTLY { users_id, nonce, iat } — no data_as_of claim (SD-20 verbatim; ADR-011 Decision 19 / Lock 15 mod #7b), no silent additions', async () => {
		const token = await mintRenderToken(USERS_ID);
		expect(Object.keys(decodeJwt(token)).sort()).toEqual(['iat', 'nonce', 'users_id']);
	});
```

This subsumes the existing `aud`/`iss` leg's catch and is the leg that makes the module's RT-25
"does not apply" claim durable. I do NOT ask for the `aud`/`iss` leg to be removed — it carries
the *declined-by-design* label and that label is the thing worth keeping.

## F-3 (flag) — three battery legs are weaker than their labels

- **(a)** `expect(importLines).not.toMatch(/supabase/i)` filters lines by `/^\s*import\b/`. A
  **wrapped** import — `import {\n  createServerClient\n} from '@supabase/ssr';` — puts the
  specifier on a line that does not start with `import`, so it passes. `await import('…')` and a
  bare `require` also pass. Fix: match the whole source for
  `/from\s+['"][^'"]*supabase|import\s*\(\s*['"][^'"]*supabase/i`.
  ⚠ Also note the AC's own words for (a): *"deleting it removes the assertion that a
  Supabase-issued token cannot drive a render."* The leg as built does not carry that assertion —
  it asserts this module imports no Supabase client. The named assertion is worker-side and IS
  covered at A4 (`workers/pdf-render/test/auth.test.js`: *"a wrong-key signature is rejected and
  counted under signature_verification_failed"*). Recommend the (a) block cite that leg the way
  (e) cites RT-22, so the AC's assertion has a stated home.
- **(b)** second leg ("the SAME token does NOT verify under a different key") cannot fail for any
  defect of this module — it is a property of HMAC. Keep it if you like, but label it a
  documentation leg like (e)'s citation leg, so a future reader does not count it as coverage.
- **(e)** second leg is `expect(true).toBe(true)`. It is honestly commented, but it counts toward
  a green figure and toward RT-21 coverage. A real app-side leg is available and directly
  discharges the brief's RT-26 question:

```ts
	it('holds no Supabase credential reach: the module source names no SUPABASE_* env var and no service_role', () => {
		const src = readFileSync(fileURLToPath(new URL('./renderClient.ts', import.meta.url)), 'utf8');
		const code = src.split('\n').filter((l) => !/^\s*(\/\/|\*|\/\*)/.test(l)).join('\n');
		expect(code).not.toMatch(/SUPABASE_[A-Z_]+/);
		expect(code).not.toMatch(/service_role/);
	});
```

- **Missing:** no leg asserts the POSTed body is `html` byte-for-byte. The header's negative
  assertion ("constructs no markup and interpolates nothing into it") is the app-side mirror of
  A4 item 4b and has no watcher. One line: `expect(call[1].body).toBe(html)`.
- **Missing:** no leg asserts the header value matches the worker's `/^Bearer\s+(\S+)$/`. The (d)
  legs read `headers['authorization']` and compare two values without asserting the prefix.

## F-4 (flag) — the module's `FRESHNESS_WINDOW_SECONDS` is declared, never used, and its comment overstates who enforces it

Measured: `grep -rn 'FRESHNESS_WINDOW_SECONDS' api/src/` returns three hits in
`renderClient.ts` — two comments and the declaration at line 123. **Zero uses.** The minting path
sets `iat` only; the 60 s window is enforced entirely worker-side.

The comment above it reads *"MUST match workers/pdf-render/src/auth.js's FRESHNESS_WINDOW_SECONDS
exactly … A mismatch would not fail loudly; it would silently widen or narrow the window on
whichever side is stale."* On the code as written, **nothing app-side can diverge**, because
nothing app-side reads the constant. The comment asserts a cross-file invariant that (a) is not
this file's to hold and (b) has no watcher anywhere.

Preferred fix (Backend): **delete the constant** and reword header letter (c) to state that the
window is minted-as-`iat` here and enforced solely at `workers/pdf-render/src/auth.js`. That
removes a false impression rather than adding a watcher for a value that does nothing.
If the team prefers to keep the cross-file pin, it needs a real watcher (a leg that reads the
worker file and asserts the same numeral) — but I do not require one, because the app side has no
behaviour to protect.

## F-5 (flag) — two claims about the tree are false at the review sha

Both were true when authored and are false at `0c5f54a`, which merged `origin/main` (`bde35a7`,
A4). Measured: `git cat-file -e 0c5f54a:workers/pdf-render/src/auth.js` succeeds; `_rejected`
occurs 14× in that blob.

1. `renderClient.ts` header, letter (g): *"a follow-up commit on feature/self-348, not this
   branch, since that file doesn't exist on `main` yet — A4 hasn't merged"*.
2. `renderClient.test.ts` (e) second leg comment: *"against files that don't exist on THIS branch
   (A4 hasn't merged)"*.

The pointer is right and the extent claim is wrong. Fix: strike both parentheticals; A4 is on
`main` at `bde35a7`. (2) also removes the stated reason the leg is vacuous — which is why F-3
proposes a real leg in its place.

## F-6 (flag) — "this module's OWN half of (g)" is the framing ADR-050 D6's annotation forbids

ADR-050 Decision 6, annotation of 2026-09-05 (Sec R-6, ruled E28), binding constraint (2),
verbatim: *"An app-side rejection counter is **NOT a substitute and must not be recorded as one**:
it measures a DIFFERENT POPULATION. The app is the only legitimate caller … an attacker on the
private network who is not the app produces rejections the app never sees."*

The module adds **no counter** — measured, and I confirm that half is clean. What it does is call
its `console.error(...worker returned <status>)` line *"This module's OWN half of (g)"*. (g) has
no app-side half; recording one is the accounting R-6 barred. Commit-ready replacement for that
sentence:

> This module's app-side conduct on a rejection is REDACTION ONLY, and is **not** part of (g)'s
> discharge: a non-2xx response is logged as a STATUS ONLY (`[pdf-render] worker returned
> <status>`), never the body, the token, or the signing key — see REDACTION below. Per
> [ADR-050](../../../../../../DECISIONS.md#adr-050) Decision 6's 2026-09-05 annotation (Sec R-6,
> E28), an app-side rejection signal measures a different population than (g) and is not a
> substitute for it; (g) is discharged wholly at the worker.

(Backend: fix the relative depth of the link to match the file's own convention — the module
currently uses no `DECISIONS.md` link, so a bare "ADR-050 Decision 6" reference is also fine.)

## F-7 (flag, cross-PR) — SECURITY RT-21's row still describes the retired direction

Measured on this branch: `docs/SECURITY/index.html` line 592 still opens *"V1 app
`/internal/pdf-render` endpoint verifies inbound JWT from PDF worker"*. ARCH §3.2 has already been
amended (`grep -c 'PDF worker mints a custom JWT' docs/ARCH/index.html` → 0). The RT-21 rewrite is
on the sibling's unit PR (#636).

If #638 merges first, `main` carries a shipped control whose canonical catalog row states the
opposite direction. **Merge-order condition:** #636's RT-21 rewrite lands before or with #638. I
am not asking Backend to touch SECURITY — that row is the sibling Sec's and PR #636's.

## F-8 (flag, routed to DevOps + Architect) — no entropy floor on `PDF_WORKER_SIGNING_KEY`

Neither side asserts a minimum length. `renderConfig()` accepts any non-empty string;
`jose` (app) and `jsonwebtoken` (worker) both accept a short HMAC secret without complaint. Under
R2 (C) this single shared secret is the **entire** admission perimeter for "make headless Chrome
render arbitrary bytes" — there is no second factor. SD-20 says *"Rotation Phase 3+; rotation
mechanism TBD per Phase 3 ARCH"* and specifies no entropy.

Realistic vector is narrow (private container network; the token never appears in any log on
either side — verified). Cheap fix, and I recommend both halves: a `secret.length < 32` fail-loud
in `renderConfig()` (Backend, one branch on the existing throw), and a generation note beside the
`production_only` entry in `secrets-manifest.yml` (DevOps). Not blocking.

---

## Notes (no action required now)

- **N-1 Rotation.** `cfg` is memoized for the process lifetime, so the app cannot pick up a
  rotated key without a restart, and there is no dual-key acceptance window on either side. A
  rotation is a hard cutover: both containers restart, in-flight renders 401 until both are up.
  Fail-closed, availability-only. Belongs in the DevOps rotation runbook when SD-20's "rotation
  mechanism TBD" is resolved; I am not asking for a dual-key window at V1.
- **N-2 Redirects.** `fetch` defaults to `redirect: 'follow'`. Node strips `Authorization`
  cross-origin, but a 307/308 from the worker would re-send the finished report HTML to the
  redirect target and a subsequent 200 would be read as success. Requires a compromised or
  misconfigured worker, which already holds the HTML — marginal. `redirect: 'error'` is a
  one-word hardening if Backend is touching the block for F-1 anyway.
- **N-3 Response shape.** No cap on the response body and no check that the bytes are a PDF. The
  inbound direction is capped worker-side (`MAX_BODY_BYTES = 25 * 1024 * 1024` at
  `workers/pdf-render/src/server.js`); the return direction is not. **Carry-forward requirement
  for P6/A7, not for A5:** the route that consumes `pdfBytes` must set `Content-Type:
  application/pdf` itself and must never echo worker bytes under a worker-supplied content type,
  and should map every `ok:false` to a uniform client-facing status rather than passing the
  worker's status through.
- **N-4 Manifest hygiene.** `secrets-manifest.yml` declares `PDF_WORKER_SIGNING_KEY_TEST` under
  `ci_only`; the battery hardcodes a literal instead. Measured: `grep -rn
  'PDF_WORKER_SIGNING_KEY' .github/workflows/` returns nothing, so **no CI store holds a
  production name and the two sets stay disjoint** — this is hygiene, not a violation. Either wire
  the battery to `_TEST` or let DevOps retire the entry when nothing claims it.

## Non-objections, stated

- I do **NOT** require an app-side (g) counter, signal, or store. R-6 forbids it; none is present.
- I do **NOT** require an SD-20 edit, an RT-21 claim-set edit, or a worker change for the
  ⟨OPEN⟩ (see the ruling in the report).
- I do **NOT** require an RT-26 allowlist entry. Measured: `grep -n
  'SUPABASE\|service_role\|supabase'` over both files returns only comment/assertion text; the
  module reads exactly two env names (`PDF_WORKER_SIGNING_KEY`, `PDF_RENDER_WORKER_URL`) and lives
  under `src/lib/server/`, so SvelteKit's server-only enforcement plus `$env/dynamic/private`
  already fence client reach.
- I do **NOT** require `aud`/`iss` claims. The declined-and-tested disposition is correct on this
  boundary and the leg that catches a silent add is the right control.
- I do **NOT** object to `__resetConfigForTests` shipping in production source — it clears a
  memoized config and matches `admissionClient.ts`.
- I do **NOT** object to the outbound URL construction. `PDF_RENDER_WORKER_URL` is env-sourced,
  trailing slashes are stripped, `RENDER_PATH` is a constant, and no caller-supplied value reaches
  the URL. Exactly one outbound `fetch` per render, asserted by a leg that can fail.
- I do **NOT** require an RT-25 leg. No `as_of` / `data_as_of` value crosses this boundary in any
  form; F-2's claim-set leg is what keeps that true.

## Verify-hook results

- **SD-20** read verbatim at `docs/SECURITY/index.html#sd-20`. The shipped direction matches it
  exactly (app signs, worker verifies signature + freshness + nonce). The literal reading of
  *"`users_id` claim ONLY"* is scoped by the same sentence's *"verifies signature + freshness +
  nonce"*, so `{users_id, nonce, iat}` is the ratified set and the nonce is not an excess claim.
- **RT-21** read verbatim (row at line 589–596): still written over the retired app-inbound
  direction — F-7.
- **ADR-011 Decision 4** read **live** at this session. §10 catalogued-instance ledger = **3**,
  RT-22 first / RT-26 second / RT-27 third. This PR adds, removes, reorders and renumbers nothing;
  no layer attribution moves; no surface becomes "four-layer".
  - **(i) instance-numbering — CLEAN.** The module cites no §10 ordinal at all.
  - **(ii) layer-attribution — CLEAN.** The module makes no layer claim. Its one infrastructure
    claim — *"RT-22 + the RT-22-manifest fence audit both on every PR"* — is **accurate**:
    `.github/workflows/security-scan.yml` runs both jobs with **no `paths:` filter** (line 36:
    *"No `paths:` filter — all fences + scanners run on every PR/push"*).
  - **(iii) verbatim-vs-paraphrase — ONE drift, F-9 below.** The one string presented as a quote,
    *"no tenant or money knowledge"*, is verbatim from
    `docs/records/v15-preflight/sitting-log.md` line 38.
- ⚠ The §10 **catalogued** set (RT-22 / RT-26 / RT-27) and the **CI-fenced** set — measured
  `grep -rhoE 'RT-[0-9]{2}' .github/workflows/` → RT-05, RT-22, RT-26, RT-27, RT-30 — are
  **different sets** and are not reconciled here.
- **(e)'s citation of A4's fences, checked at `bde35a7` — ACCURATE.**
  `workers/pdf-render/.env.example` carries exactly one variable, `PDF_WORKER_SIGNING_KEY`; the
  Dockerfile installs no Postgres client (every `postgres`/`pg` occurrence is a prohibition
  comment); both RT-22 jobs are run-always with inversion-mode golden fixtures.

## F-9 (flag) — wrong-pointer citation in the ⟨OPEN⟩

The module attributes capability-over-discipline reasoning to *"ADR-011 Decision 1's own
reasoning about capability-vs-discipline"*. ADR-011 Decision 1 read verbatim is the four-clause
**privileged-context-write discipline** (ingress under no JWT / writes under `service_role` /
tenant correctness derives from **code, not RLS** / explicit audit log). It contains no
capability-vs-discipline argument, and clause (c) runs the other way — it accepts a
discipline-based control precisely because the capability-based one cannot reach.

This is the *right content, wrong pointer* class ADR-011 Decision 4's own CHANGELOG records at
PR #476 (2): the ruling is real and the pairing is not, which is why it survives a spot-check.
Fix: drop the ADR pointer and state the principle unattributed, or have Architect supply the
decision that actually holds it. Do not leave the pointer as-is.

## Handed to QA

The brief's method for item 2 — strike each control on a scratch copy and confirm **only** its own
leg reds — was not run here. Strike list, one control per run, with the leg that must be the sole
RED: `alg: 'HS256'` → (b)-1; `env.PDF_WORKER_SIGNING_KEY` → (b)-1 and config-1; `setIssuedAt()` →
(c); `randomUUID()` → fixed string → (d)-1 and (d)-2; `RENDER_PATH` → (f); the `res.status !== 200`
branch → (g)-1; the `console.error` status-only line → (g)-2. Legs expected NOT to move under any
strike (and therefore not coverage): (b)-2, (e)-2.
