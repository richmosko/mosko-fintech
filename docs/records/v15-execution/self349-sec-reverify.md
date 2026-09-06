# Sec (instance 2) — A5 re-verify at `e037776` (PR #638)

Read both files from the ref (`git show e037776:<path>`), not from a worktree. Diff vs the first
review sha: 2 files, +178 / −61.

**Verdict: GREEN, conditional on two comment-only string corrections (R-1, R-2) landing in this
PR.** No further Sec pass required — team-lead can confirm the two strings itself. F-7's merge
order still applies and is not Backend's to close.

## Per-finding re-verdict

| | verdict at `e037776` |
|---|---|
| F-1 body read inside the guarded region | **FIXED.** `res.arrayBuffer()` is inside the same `try`; `clearTimeout` is the sole `finally`; the `catch` comment now names mid-body failure and refused redirect. N-2 taken: `redirect: 'error'` with an accurate rationale. Criterion (1) leg is real (`ReadableStream` that `controller.error()`s) and would reject under the pre-fix shape. Criterion (2) deferred — ruled below. |
| F-2 exhaustive claim set | **FIXED.** `Object.keys(decodeJwt(token)).sort()` → `['iat','nonce','users_id']`, in its own describe naming SD-20 + Lock 15 mod #7b. |
| F-3 (a) regex | **FIXED.** Comments stripped, whole-source match on `from '…supabase'` / `import('…supabase')`. Wrapped and dynamic imports are now caught. The comment-strip filter is line-anchored, so a trailing `// … supabase` on a code line could produce a false RED — wrong direction only, acceptable. |
| F-3 (a) AC assertion | **FIXED.** Cites `workers/pdf-render/test/auth.test.js` — *"a wrong-key signature is rejected and counted under signature_verification_failed"*. **Verified verbatim at `bde35a7`** (that file, line 48). |
| F-3 (b)-2 | **FIXED.** Labelled DOCUMENTATION LEG in the `it()` title, so the label shows in test output, not only in source. |
| F-3 (e)-2 | **FIXED.** `expect(true).toBe(true)` replaced by a failable source assertion: no `SUPABASE_[A-Z_]+`, no `service_role` in comment-stripped source. This is also the app-side discharge of the brief's RT-26 no-reach question. |
| F-3 body passthrough | **FIXED.** `expect(call[1].body).toBe(html)` with a randomised marker. |
| F-3 Bearer prefix | **FIXED**, and better than asked: asserts `/^Bearer\s+(\S+)$/` (the worker's own parse) **and** that the captured token has three dot-separated segments, so an empty-token pass is impossible. |
| F-4 dead constant | **FIXED.** Constant deleted; letter (c) now states the window is enforced entirely worker-side and that this module holds no numeral that could diverge. The comment now matches the code. |
| F-5 false tree claims | **FIXED** at both sites; both now read *"merged to `main` at `bde35a7`"*, which is true. |
| F-6 (g) framing | **PARTIAL → R-1.** Header corrected exactly as supplied. The **inline comment at the call site was not propagated** and still reads `// (g)'s app-side half — status ONLY, never the body.` |
| F-7 RT-21 row direction | **OPEN, not Backend's.** Merge-order condition stands. |
| F-8 entropy floor | **FIXED.** `MIN_SIGNING_KEY_LENGTH = 32`, fail-loud before any signing call, with an honest comment that length is not entropy. Two legs. Fixtures widened past the floor without weakening any leg. |
| F-9 wrong pointer | **FIXED.** The ADR-011 Decision 1 attribution is gone; the principle is stated unattributed. |

**No new finding introduced by the fix**, checked specifically: `MIN_SIGNING_KEY_LENGTH` is *used*
(F-4's class not repeated); no new export, no new env var, no new claim about the tree beyond the
two corrected ones; `redirect: 'error'` fails closed into the existing 502 path.

**Three-axis (ADR-011 Decision 4), unchanged and CLEAN.** The module still cites no §10 ordinal
and makes no layer attribution; its RT-22 *"both on every PR"* claim is still accurate
(`security-scan.yml` runs both jobs with no `paths:` filter); the single quoted string *"no tenant
or money knowledge"* is still verbatim from `sitting-log.md:38`.

---

## R-1 (must fix, one line) — F-6's correction did not reach the call site

`renderClient.ts`, inside the `res.status !== 200` branch, still reads:

```ts
			// (g)'s app-side half — status ONLY, never the body.
```

The header six screens above now says this conduct *"is NOT part of (g)'s discharge."* Two
contradictory statements in one file, and the surviving one is the exact phrasing ADR-050 D6's
2026-09-05 annotation, constraint (2), bars. Replace with:

```ts
			// Redaction only — NOT part of (g)'s discharge (see header): status ONLY, never the body.
```

## R-2 (must fix) — the ⟨OPEN⟩ record states the ruling's weakest ground as its surviving one

The header reads *"The surviving ground for the ruling: leaving it is the lower-churn choice."*
Churn was the **third** ground, not the surviving one, and stating it alone installs the wrong
revisit trigger: a reader concludes "reverse it when churn is low", which will be true the next
time RT-21 is touched for any reason. The ruling's primary ground is that the capability is
**fenced today**, and the correct trigger is capability, not churn. Commit-ready replacement for
the two sentences beginning *"The surviving ground for the ruling"* through *"was not judged worth
it here."*:

> The grounds, in the order they carried the ruling. **(1) The security delta today is zero and
> is fenced, not merely unused:** the worker holds no DB reach and no Supabase credential of any
> kind (RT-22 + the RT-22-manifest fence, both run-always in CI), so it cannot act on the claim
> even if a later edit read its value. **(2) The residual is prospective and has a named shape:**
> a `users_id` claim is the affordance that would make a tenant-keyed render cache inside the
> worker easy to write, which is an RT-10 violation; an opaque per-render id would foreclose that
> structurally rather than by convention. Note the opaque-id shape is a DELETION, not a
> substitution — the `nonce` already is a per-render opaque UUID, so correlation can live app-side
> against it without the worker holding any tenant knowledge at all. **(3) Cost:** the swap
> touches five artifacts, two of them already merged (`auth.js` and its battery), and would land a
> claim-set change mid-rewrite of RT-21. **Revisit trigger — capability, not churn:** if the
> worker ever gains outbound reach, a persistence surface, or any per-tenant keying, the swap
> becomes the right shape and should be booked as its own change to SD-20 + the worker.

## Ruling — F-1 catch criterion (2) is NOT required for GREEN; it is bookable

**Why it is not redundant, stated so the booking is not read as cosmetic.** Criterion (1) does not
subsume it. Moving `clearTimeout(timer)` back to immediately after `fetch()` — *inside* the try —
leaves criterion (1) green (the `catch` still covers the body read) while silently unbounding the
body download again. That is precisely the F-1 regression, and today only a comment guards it.

**Why it does not gate the merge.** The defect is fixed and demonstrated; the residual is
regression-detection for an availability property, reachable only by an editor moving a line
against an explicit comment; and I have not been able to run the suite myself, so a leg I
prescribed but did not execute should not hold a merge. **Book it as a tracked issue, owner QA,
`joint-review:sec` — not a PR-body follow-up line.** ADR-050 D6's own annotation is the precedent:
a follow-up recorded only in a merged PR description has no watcher.

**Shapes I reject.** (i) An **injectable timeout in the production module** — I do not accept a
test-only mutable knob on a security-relevant bound in shipped source. (ii) A **real-timer leg
with a short override**, if the override is production-side; acceptable only if it lives entirely
in the test.

**Shape I accept — no fake timers, so the `jose`/WebCrypto obstacle never arises.** Stub
`setTimeout`/`clearTimeout` for this one test, capture the module's abort callback, and make the
*arming* the assertion:

```ts
	it('Sec F-1 catch criterion (2): the abort timer stays ARMED across the body read — a body that never settles is aborted, not awaited forever', async () => {
		let fire: (() => void) | undefined;
		let cleared = false;
		vi.stubGlobal('setTimeout', (cb: () => void) => { fire = cb; return 42; });
		vi.stubGlobal('clearTimeout', (id: unknown) => { if (id === 42) cleared = true; });
		vi.stubGlobal('fetch', vi.fn(async (_url: string, init: { signal: AbortSignal }) =>
			new Response(new ReadableStream({ start() { /* never enqueue, never close */ } }), { status: 200 })
		));

		const p = renderReportHtml(USERS_ID, '<html></html>');
		await new Promise((r) => setImmediate(r)); // let the module reach the pending body read

		// THE CATCH: if clearTimeout were called before the body read (the pre-fix shape),
		// the download would be unbounded. This assertion is what reds on that regression.
		expect(cleared).toBe(false);

		fire!(); // the abort the 30s timer would have fired
		await expect(p).resolves.toEqual({ ok: false, status: 502 });
	});
```

⚠ **Do not stub `clearTimeout` as a bare no-op.** That version passes under the pre-fix shape too —
a false green. The `cleared === false` assertion at the pending-body moment is the entire value of
the leg; the 502 assertion alone is not.

The yielding detail (`setImmediate` vs `vi.waitFor` on the fetch mock) is QA's to settle. My
requirement is the two assertions, in that order.

## Notes

- **N-5 (DevOps, deploy precondition).** F-8's floor is app-side only; the worker enforces none. A
  provisioned `PDF_WORKER_SIGNING_KEY` shorter than 32 characters now fails closed at first render
  with a clear error. Verify the Coolify value's length before the PDF worker's first deploy.
- **N-6 (one-character, non-blocking).** F-8's rejecting leg uses `'too-short'` (9 chars). A
  boundary **pair** would be `'x'.repeat(31)` rejected / `'x'.repeat(32)` accepted; as written, an
  off-by-one loosening to `< 31` reds nothing. Fold into the QA booking.
- **Placed record verified.** `git show 5e1900b:docs/records/v15-execution/self349-sec-review.md`
  (on `origin/meta/v15-execution-log`) diffs **IDENTICAL** to my authored
  `temp/sec2-self349-a5-review.md`. No paraphrase drift on the way in.
