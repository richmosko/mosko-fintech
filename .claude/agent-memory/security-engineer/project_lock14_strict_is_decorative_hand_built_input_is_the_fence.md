---
name: lock14-strict-is-decorative-hand-built-input-is-the-fence
description: Across the Lock 14 settings write paths the Zod `.strict()` cannot fire — actions hand-pick fields from formData — so the real mass-assignment fence is the hand-built parse input, not `.strict()` as the file headers claim.
metadata:
  type: project
---

**Fact, measured at the P7 / SELF-359 review (`e879c35`, 2026-09-06) and confirmed against a
sibling.** The Lock 14 settings form actions build their Zod parse input **field by field** from
`form.get(...)`:

```js
ownerIdentificationUpsertSchema.safeParse({
    owner_id_header_text: typeof raw === 'string' ? raw : null
});
```

**No unknown key can ever reach the schema, so `.strict()` cannot fire.** Checked
`settings/tax-brackets/+page.server.ts` before writing it up — same shape (`form.get('tax_year')`,
`form.get('schedule_type')`, …). **This is the family convention, not a P7 divergence.**

**The security property HOLDS.** Mass assignment is prevented **by construction**, which is at
least as strong as `.strict()` — and `users_id` is separately written from `safeGetSession()`, never
from the body, with `106`'s `DEFAULT auth.uid()` and the RLS `WITH CHECK` behind it.

**What is inaccurate is the CLAIM.** Every one of these file headers states *"`.strict()` is the
mass-assignment fence (Lock 14 mod #1)"*. As built, the hand-picked input is the fence. Same class
as a `comment on function` asserting a property the body does not have — see
[[read-the-whole-cell-before-diagnosing-doc-drift]] and
[[a-check-chained-to-its-action-is-decoration]].

**⚠ Why this is worth carrying rather than shrugging at — the failure mode is one step out.** A new
settings schema copied from this pattern **without** `.strict()` looks identical and behaves
identically **today**. The moment someone refactors an action to `Object.fromEntries(form)` — the
natural move when a second or third field lands — `.strict()` becomes the only fence, and its
absence fails **open**, silently. The pattern that never exercises a control is the pattern that
teaches people to omit it.

**How to apply at the remaining Lock 14 reviews (P3 commentary editor, P4 finalize/skip).** Do not
grade `.strict()` as present-therefore-effective. Read the ACTION and ask which of these it is:

- **hand-picked input** → `.strict()` inert; the fence is the pick list. Verify the pick list
  omits every privileged field (`users_id`, ids, status columns) and that each picked value is
  type-narrowed before parse.
- **`Object.fromEntries(form)` / spread of a JSON body** → `.strict()` IS the fence and is
  load-bearing. Verify it is present, and that no `.passthrough()`/`.catchall()` sits under it.

**Reported as a NOTE, no gate, no code change required** — recording the disposition so I do not
re-litigate it as a fresh finding on the next Lock 14 surface. If a future header is edited for
other reasons, one sentence correcting the claim is the cheap fix.
