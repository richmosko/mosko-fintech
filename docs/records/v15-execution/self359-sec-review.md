# SELF-359 (P7) — Sec joint-review verdict · GREEN at `e879c35` · 2026-09-06

Verbatim from Security (sec-c), measured against `main` @ `0ffab75`. Team-lead cross-check against the tree (the `106` CHECK at the cited lines, the merge-tree CLEAN, the session-client write path, zero `{@html}`) recorded at execution log E84.

---

P7 / SELF-359 is **GREEN at `e879c35`**, measured against `main` @ `0ffab75`. **CLEAR TO MERGE from Sec's side: YES, no conditions.** Four notes below, none of which gates.

**md5 `06a2c740d41954ba31437c89df466568`** — the nine blobs of `30ac2cc..e879c35` concatenated in `git diff --name-only` order, read via `git show e879c35:<path>`. That is what this verdict covers.

## 1. Summary

I read ADR-011 D1/D4 and migration `106`'s three CHECK constraints verbatim before grading, took my own `--stat` and classified all nine paths, and verified both 120-char layers independently rather than accepting the walk. The write path is a user-JWT PostgREST UPSERT with `users_id` from the session and never from the body, no `{@html}` anywhere, and the DB refusal is a real second layer with the app layer strictly on the safe side of it. I also discharge the Backend/Sec re-read the two server files ask for by name.

## 2. Paths changed — my own classification, all nine

**Server surface (ARCH §4.1 — the Lock 14 mandatory anchor), 2 new files:** `api/src/lib/server/schemas/owner-identification.ts` (+102) · `api/src/routes/settings/owner-id/+page.server.ts` (+109).
**Client mirrors, not enforcement, 2 new:** `api/src/lib/schemas/owner-identification.ts` (+61) · `api/src/lib/validation/ownerIdHeader.ts` (+57).
**UI, 2 new:** `api/src/lib/components/OwnerIdentificationEditor.svelte` (+195) · `api/src/routes/settings/owner-id/+page.svelte` (+45).
**Nav, 1 modified:** `api/src/routes/settings/+layout.svelte` (+19/−9) — a comment rewrite plus `{ label: 'Owner Identification', href: null }` → `href: '/settings/owner-id'`. **No security content**; I read the whole hunk rather than assuming from the path.
**Tests, 2 new:** `owner-id.server.test.ts` (+377) · `OwnerIdentificationEditor.dom.test.ts` (+163).
**No migration, no workflow, no Dockerfile, no `secrets-manifest.yml`, no `DECISIONS.md`.** No "X only" scope was assumed — this is the full nine.

**`30ac2cc..0ffab75` does not change the read.** Scoped to the surfaces this review depends on, the only change is A5's `api/src/lib/server/pdf/renderClient.ts`/`.test.ts` (P6's work), which P7 neither touches nor imports. **`106` is byte-identical since the branch point**, so its GREEN at #629 carries. `git merge-tree --write-tree --name-only origin/main e879c35` → CLEAN.

## 3. Broken

None.

## 4. Bubble up

**Both 120-char layers hold, and they are genuinely independent — I did not take this from the walk.** App: the server schema bounds `trimmed.length > 120` → `ctx.addIssue` → `safeParse` fails → `fail(400)`. DB: `owner_identification_header_len_check` (`… or length(owner_id_header_text) <= 120`) at `106` L254–256. ⚠ **The direction is the safe one and it is worth stating because it is easy to get backwards:** Zod bounds UTF-16 **code units** (an astral character counts 2) while the CHECK counts **code points** (counts 1), so the app layer is equal-or-**stricter** and can never accept a value the DB would reject on length. The reverse arrangement would have made the DB the only real bound.

**Write path — GREEN on every clause the brief names.** The UPSERT runs through `locals.supabase` (the session client) against `pfin.owner_identification`; **no `supabaseAdmin()` import and no `service_role` path anywhere in the diff.** `users_id` is not a schema field, is never read from the request, and is written explicitly as `user.id` from `safeGetSession()` — belt-and-braces over `106`'s own `DEFAULT auth.uid()` and its RLS `WITH CHECK`. Error mapping discharges the #629 Sec rider: 23514 and 23505 both map to a fixed generic 400 and **the constraint name is never sent to the client**; 42501 → 403; anything else is a logged 500.

**No `{@html}`** — zero occurrences in both new `.svelte` files; the value round-trips through `bind:value` on an input and renders through default `{…}` interpolation. That matters here specifically because the server schema deliberately accepts `<script>`, RTL overrides and homoglyphs as prose (correctly — that is the wrong fence at the wrong layer), so escaping at the render surface **is** the control for those classes and it is present.

**E5 trim-on-save — no objection.** The transform trims before applying the bound, so the limit a user hits is measured against what is stored. Frontend flagged it as its own judgment call since `106` carries no trim CHECK; it is the safe direction and reversible without a migration. **I do NOT require it be removed or moved to the DB.**

**Forward-only header semantics — stated precisely rather than claimed.** This diff introduces **no path that writes to `pfin.monthly_report`** and no path that mutates an already-generated report. The forward-only property lives in the generation path (`110`/`115`), not here, and is unaffected. I verified the absence, not the property.

**Client mirrors are not looser.** Both carry the same `MAX_HEADER_LENGTH = 120`, the same seven-code-point class byte-for-byte, the same blank-input-is-NULL normalization, and the object schema carries `.strict()`. They are UX, not enforcement; the server re-validates unconditionally.

**NOTE-1 — `.strict()` is decorative here, and uniformly across the Lock 14 family. No action, and the security property holds.** The action hand-builds its parse input: `safeParse({ owner_id_header_text: typeof raw === 'string' ? raw : null })`. **No unknown key can ever reach the schema, so `.strict()` cannot fire.** I checked whether P7 diverges from the family before writing this up, and it does not — `settings/tax-brackets/+page.server.ts` builds its input the same way, field by field from `form.get(...)`. **Mass assignment is prevented by construction, which is at least as strong.** What is inaccurate is the claim, repeated in these file headers, that *"`.strict()` is the mass-assignment fence (Lock 14 mod #1)"* — as built, the hand-picked input is the fence. **I do NOT require a code or comment change now.** I record it because the failure mode is one step out: a future schema copied from this pattern, authored **without** `.strict()`, would look identical and be fine — until someone refactors to `Object.fromEntries(form)`, at which point `.strict()` is suddenly the only fence and its absence fails open silently. Worth one sentence whenever one of these headers is next edited.

**NOTE-2 — an omitted field silently clears the header with a 200.** `form.get('owner_id_header_text')` returns `null` when the field is absent, and `typeof raw === 'string' ? raw : null` maps both "absent" and "non-string (a File in a multipart post)" to `null`, which normalizes to a NULL write — a successful destructive save. For a single-field replace-all editor this is defensible (empty means clear) and it is **not remotely triggerable**: I confirmed no `csrf` override in `api/vite.config.ts` (and there is no `api/svelte.config.js` — kit config lives in the vite config), so SvelteKit's default `checkOrigin` is in force. Recording it because "omitted" and "explicitly cleared" are different intents collapsed into one destructive outcome, and a second field added to this form inherits the collapse. **No action.**

**NOTE-3 — five of the seven line-boundary code points have only a structural observer, and I do NOT require behavioural legs for them.** `106`'s battery proves LF (LINE1) and CR (LINE2) behaviourally by constraint name with a positive control (LINE3, same content with a space, accepted); VT/FF/NEL/LS/PS are covered by CATLINE1, a `pg_get_constraintdef` substring pin. **Why I am declining rather than just noting it:** the ARE `\uXXXX` escape *mechanism* is already proven behaviourally — LINE1/LINE2 demonstrate that the regex's escapes actually match — and the *enumeration* is pinned by exact-substring matching that a typo would RED. The battery also builds those escape strings at runtime via `chr(92)` concatenation specifically so the test file never carries `\u` notation an editor could silently reinterpret. That is a known hazard in this repo, designed around rather than stumbled into, and I want it recorded as good work rather than only as a residual.

**NOTE-4 — the role-boundary re-read the files ask for by name: I am it, and I discharge it.** Both server files carry a header saying *"a Backend/Sec re-read of this file is owed at the AC8 Sec joint review (Lock 14 MANDATORY joint-review)."* **This review is that re-read. I have no objection to the authorship and no security finding arising from it.** The §4.1 consequence that actually matters is satisfied: the RT-26 fence's audit scope grows by two server-source files, **neither references `SUPABASE_SERVICE_ROLE_KEY`**, and the allowlist is exact-path rather than glob-shaped, so it is unchanged and **no ADR-016 D1 amendment is owed**. Separately and not a Sec gate: Backend has still not re-read these two files. That is your call, not a merge condition from me.

**Verify-hook, read live from the ADR body at `main` @ `0ffab75`.** §10 catalogued-instance ledger: **count = 3**, RT-22 first / RT-26 second / RT-27 third — unchanged by this diff. No instance added, removed, reordered or renumbered; no layer attribution moves; the branch quotes and paraphrases no Lock text, so axis (iii) has nothing to grade. **No drift to surface.** Stated separately because they coincide on three labels and must never be reconciled: the CI-fenced RT set is a different set, and I did not reconcile them.

**VERDICT — GREEN. CLEAR TO MERGE: YES, no conditions.** ⚠ `main` moved four times yesterday; re-run `git merge-tree --write-tree --name-only origin/main e879c35` in the same turn as the merge — my CLEAN read is scoped to `0ffab75`.
