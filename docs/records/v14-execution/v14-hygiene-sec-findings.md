# V1.4 pre-close-gate hygiene batch — Security joint-review

Scope: [ADR-066](../../../DECISIONS.md#adr-066) Decision 1 (b) — rendering guards on money figures.
The batch closes four notes I raised at the SELF-264 / SELF-266 review, so this is a re-look at my
own findings rather than a fresh surface.

---

## Hygiene batch at `31526ac`

**Verdict: GREEN.** No veto, no flag. All four notes are closed, and each is closed at the
**mechanism** rather than at the symptom. **One new note (N-H1)**, unrelated to the four, in the
watcher N-7 built.

**Reviewed at** `origin/meta/v14-hygiene` **`31526ac`**, with `origin/main` **`48bbcb7`** verified an
**ancestor** (`git merge-base --is-ancestor` → true). `git diff --stat origin/main
origin/meta/v14-hygiene` = **8 files, 334 insertions, 40 deletions**. No migration, no policy, no
grant, no `SECURITY DEFINER` object, no FK-shaped column, no CI-fence change, no `secrets-manifest`
change. ADR-011 Decision 3 and Decision 4's §10 ledger are untouched, and the §10 **catalogued** set
and the **CI-fenced** set are nowhere reconciled in this branch.

---

### N-1 / N-2 — CLOSED, and closed on the nullish half specifically

`api/src/lib/tax-quarterly.ts`. Both captions now guard with `== null`, which catches `null` **and**
`undefined`:

- `federalRateCaption` — `rate.ordinary == null` and `rate.lt_cg == null` each route to
  `'unavailable'`.
- `californiaRateCaption` — same on `rate.ordinary`.
- The type widened to `ordinary: number | null` / `lt_cg?: number | null`, so the two shapes are
  reachable in the type rather than only in the comment.

**The distinction the fix had to preserve, and does:** a genuine `0` rate still renders `"0%"` —
only an absent-or-null key renders unavailable. `tax-quarterly.test.ts` carries that as its own leg
on all three sites (*"a genuine 0 LT CG rate still renders 0%, not unavailable"*, and the two
ordinary mirrors), which is the leg that would go red if someone "simplified" `== null` to a
falsiness check. That is the correct watcher for this fix, and it is present.

**The header records the honest reachability**, which is the half I care about most: `104` wraps the
object in `jsonb_strip_nulls` today, so a null figure is **not currently reachable** — and the mirror
is closed against both shapes anyway, *"independently of that other-layer, other-repo guarantee."*
That is exactly the right framing: the guard does not claim to fix a live defect, and it does not
rest on a promise made in a different directory.

I do **NOT** require anything further here. The `!rate` object guard is retained and is not
redundant — it distinguishes *"the key is absent"* from *"the object is present with a null field"*,
and both now land on the same copy deliberately, which the header states.

### N-4 — CLOSED, at the function boundary, as a typed throw and never a clamp

`api/src/lib/server/queries/taxLiability.ts`, `loadPriorYearQ4`. Two guards before the RPC:

1. `Number.isInteger(window.tax_year)` — rejects `NaN`, `Infinity` and fractional years **before** an
   as-of string is built, so a malformed year cannot become a syntactically-plausible date.
2. `asOf < AS_OF_FLOOR || asOf > today` → `TaxLiabilityPayloadError` naming the derived value, the
   range, and its authority (Lock 15 / ADR-011 Decision 19).

**Verified rather than read:** `AS_OF_FLOOR` is imported from `$lib/server/schemas/asOf`
(`asOf.ts:126`, `'2015-12-01'`) — the same constant the Zod fence uses, so there is no second
hardcoded copy to drift; and `today` comes from `serverTodayAsOf()`, the same server-derived helper
the other query modules use, never a fresh `new Date()`.

**I checked the lexicographic comparison, because ISO string ordering is where this shape usually
fails.** The comparison is on `` `${tax_year}-12-31` ``, so a non-four-digit year is compared
character-wise, not numerically. Walked the cases: `0`/`999` → `"9…"` > today → throws; `10000` →
`"1…"` < `"2015-12-01"` → throws on the floor; negative → `"-…"` < the floor → throws. **The fence is
total over integers**, which the `Number.isInteger` guard has already narrowed the domain to. It is
correct, and it is correct for a reason worth having stated — so I am stating it here rather than
leaving the next reader to re-derive it.

The battery carries both boundaries (`tax_year` 2015 passes; `CURRENT_YEAR + 1` throws;
`CURRENT_YEAR − 1` passes) plus the non-integer leg, each asserting the RPC was **never reached** —
not merely that a throw occurred.

### N-7 — CLOSED, both halves, and the non-vacuity leg is there

`api/src/routes/route-module-export-allowlist.server.test.ts`.

- **N-7(a)** — the predicate is extracted as a named export, `disallowedExportNames(module,
  allowed)`, and exercised against a **synthetic** `{ load: 1, STRAY: 2 }` module that must return
  `['STRAY']`. That is the boundary pair one step apart: the allowlisted name is left alone and the
  stray is flagged, so the leg reds if the predicate is loosened. A second leg pins the `_`-prefix
  escape.
- **N-7(b)** — the glob is extended to `+layout.server.ts` and `+server.ts`, each with its **own,
  narrower** allowlist.
- **And the leg I would have asked for if it were missing:** each `describe` block opens with
  *"discovered at least one module (glob is not silently empty)"*. A glob matching nothing passes
  every per-module leg trivially; without this the whole watcher could go vacuous on a directory
  rename and stay green. It is present for all three shapes.

**I verified the three copied allowlists against the installed upstream** rather than taking the
"copied verbatim" claim — read from `@sveltejs/kit` **2.70.1**,
`src/utils/exports.js:63–87`:

| Local constant | Upstream | Match |
|---|---|---|
| `PAGE_SERVER_ALLOWED_EXPORTS` (8) | `valid_page_server_exports` = layout-server ∪ `{actions, entries}` | ✅ same members |
| `LAYOUT_SERVER_ALLOWED_EXPORTS` (6) | `valid_layout_server_exports` = `{...valid_layout_exports}` | ✅ same members |
| `SERVER_ALLOWED_EXPORTS` (12) | `valid_server_exports` | ✅ same members |

The predicate is also a faithful mirror of upstream's `validate`: upstream skips on `key[0] === '_'`,
the local form on `!name.startsWith('_')` — equivalent, including for the empty-string key.

### The 265 a11y note — CLOSED

`DeleteScheduleControl.svelte`: the refusal message moves from `role="status"` to `role="alert"`.
Correct for this case — a refusal is an assertive interruption, not a polite status update, and a
destructive-action refusal that a screen-reader user may never hear is the failure mode. One line,
right line.

`api/CLAUDE.md` gains the test-naming and route-export conventions. No objection.

---

### N-H1 (note, new) — the three copied allowlists have no drift watcher, and one drift direction is silent

The three constants are **copies of an upstream private constant**. `src/utils/exports.js` is not a
public export of `@sveltejs/kit`, so copying is a reasonable choice — but the copy has nothing
watching it, and the two drift directions are **not symmetric**:

- **SvelteKit ADDS a valid export name** → the local copy lacks it → a legitimate new export is
  flagged → the suite goes **RED**. Loud, safe, self-announcing.
- **SvelteKit REMOVES a name** → the local copy still allows it → a module exporting that name
  passes this watcher **green** while SvelteKit **500s the route at request time**. Silent, and it
  is precisely the failure class this watcher was built to catch — the original N-7 was a stray
  export that 500'd a route.

The asymmetry is what makes it worth a note: the reassuring direction is the loud one, so the
copy will feel reliable right up until it isn't.

**Cheapest closure — a drift leg, not a refactor:** one test that reads
`node_modules/@sveltejs/kit/src/utils/exports.js` and asserts set-equality against the three local
copies, failing with the upstream version in the message. It reds on **either** direction and costs
one file read. A deep import of the private module would be more fragile than the copy it replaced.

**⚠ Two limits on this note, stated rather than implied.** (1) It is a **note, not a flag** — there
is no live defect, the copies match upstream today, and I verified that by reading 2.70.1 directly.
(2) `node_modules` is not installed in my review worktree, so I read the package from the main
repo's checkout (`/Users/mosko/Projects/mosko-fintech/api/node_modules`) rather than from a tree
built at `31526ac`. That is the same version this branch resolves, but I did not build the branch to
confirm it — if the batch changed a lockfile it did not, since no lockfile appears in the diff.

---

### Non-objections, stated explicitly

- I do **NOT** require the `jsonb_strip_nulls` dependency to be removed or fenced at the DB side.
  The mirror is now closed against both shapes regardless of it, which is the correct resolution —
  the client guard should not depend on a producer-side guarantee, and now it does not.
- I do **NOT** require `loadPriorYearQ4` to clamp, coerce, or degrade. A typed throw is right: this
  row is primary content, and a silently-clamped as-of would render a confident figure for a date
  nobody asked for.
- I do **NOT** require the copied allowlists to become a deep import. N-H1's drift leg is the
  proportionate fix, and I am not blocking on it.
- I do **NOT** require anything of `104`, `105`, or any migration — this batch touches no DB object.
- No finding here interacts with the open SELF-268 items (F-1 / F-2 / N-1 / N-2 of that review);
  the two surfaces are disjoint.
