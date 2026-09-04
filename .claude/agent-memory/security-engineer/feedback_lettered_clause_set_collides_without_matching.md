---
name: lettered-clause-set-collides-without-matching
description: A drafted "(a)–(g) full battery" whose LETTERS match the canonical catalog entry in count and form but not in content — same cardinality, same shape, four different clauses. Passes every count check and every label check; only a clause-by-clause read catches it.
metadata:
  type: feedback
---

**When an AC promises a lettered battery against a catalogued test — "RT-NN (a)–(g) full verification
battery" — open the catalog row and diff the clauses letter by letter. Matching cardinality is not
matching coverage.**

**Why:** at the V1.5 pre-flight an AC drafted RT-21 as *(a) JWT signature; (b) nonce replay; (c)
tenant claim presence; (d) expiry; (e) no service_role escalation; (f) audience check; (g) issuer
check*. The canonical row reads *(a) authenticated-tier only, service_role JWT rejected at signature
verification; (b) **dedicated signing key** — Supabase-JWT-signed tokens rejected; (c) **60-second
freshness window**; (d) nonce replay; (e) no service_role escalation; (f) **dedicated endpoint** —
verification logic at this path only; (g) **rejected payloads dropped with a detection signal**.*
Exactly **one** letter agreed on both letter and content. Seven letters, seven letters, four clauses
silently swapped.

**Why this class survives every cheap check.** A label sweep (`grep -o 'RT-[0-9]\{2\}'`) returns a
hit and reports the surface as covered. A count check returns 7 = 7. The AC even *reads* more
thorough than the catalog, because the invented clauses (audience, issuer, tenant-claim presence)
are real controls a reviewer wants. The battery ships labelled *"full RT-NN battery"*, is green, and
four canonical clauses have no watcher — including, in this instance, the one the SECURITY doc marks
*"Sec joint-review-mandatory at the build"*.

**The two substitutions that cost the most, because they LOOK like the thing they replace:**
- **"expiry" for a freshness window.** A token with a one-hour `exp` satisfies "expiry" and fails a
  60-second `iat` window by a factor of sixty. Near-synonyms in the same semantic family are where
  this hides. Prove freshness with a **boundary pair** — 59s accepted, 61s rejected — never with a
  single "expired token rejected" leg, which passes with no window at all.
- **"JWT signature" for a dedicated-key requirement.** A generic signature leg does not require that
  a *platform-issued* token is rejected here. Separate-signing-key controls exist precisely so the
  platform's own valid tokens are not credentials on this surface; a generic leg is green while that
  property is absent.

**Related tell: the letters can also be attached to the wrong SURFACE entirely.** In the same pass an
AC cited *"RT-21 HIGH"* on the snapshot-child table whose canonical test is RT-20. Both labels real,
both surfaces real, the pairing invented — the false-composite class. The consequence is worse than a
missing label: an RT-21 battery *will* exist elsewhere and *will* be green, so the RT-20 battery's
absence is masked by a passing test with a similar name.

**How to apply:**
- On any AC promising a lettered/numbered battery, read the catalog row **verbatim in the same turn**
  and write the diff out clause by clause. Do not summarize the canonical row from the AC's framing.
- Require the battery's legs to carry the **canonical letters with the canonical content**, and any
  added controls to be labelled **separately** (e.g. "(h) audience", not "(f)"). A leg named `(c)`
  asserting the wrong property is a red whose message names the wrong defect — and the tempting
  repair is to loosen the control until the message is true.
- Check the **path/identifier** too when a clause is written over one. A clause reading *"verification
  logic lives at `/x` only"* is falsified by an AC that routes the endpoint to `/api/x`; the path
  change is not cosmetic when the clause names it.
- **Sweep the whole issue set for the catalog's labels, not just the ones the drafts cite.** Grep the
  drafts for `RT-` and diff that set against the labels the read sources name for those surfaces.
  At V1.5 that one command surfaced five canonical labels present in no draft — the omissions are
  invisible from inside any single issue.

Related: [[false-composite-citation]] (shared index) · [[enumeration-and-watcher-stop-one-short]] ·
[[a-red-whose-message-names-the-wrong-defect]] · [[adding-vs-qualifying-verification-asymmetry]] ·
[[verify-the-cited-source-subsection-not-the-headline]]
