---
name: a-sibling-implementation-cited-as-precedent-is-a-claim
description: "\"Same idiom as <sibling>.sh already uses\" in a code comment is a falsifiable claim about another file; I treat implementation-shape citations as self-evidencing where I would check a doc citation — grep the sibling"
metadata:
  type: feedback
---

A comment of the form *"same X idiom `<sibling>` already uses"* is a **citation**, and it
gets the same treatment as an ADR citation: open the cited artifact and read it.

**Why:** PR #738 (`scripts/push-production-secrets.sh`, Sec-gated, I reviewed it) shipped
`api GET "/applications?name=$resource"` + `d[0]` under the comment *"Same by-name-lookup
idiom provision-supabase-stack.sh already uses for its own application."* The sibling does
the **opposite**: `api GET /applications` unfiltered, then an exact `a['name']==` match in
local Python. `provision-app.sh` matches locally too. The `?name=` filter was invented by
this script and then justified by a precedent that says the reverse. Coolify **ignores**
`?name=` (measured on the box 2026-09-20, 4.3.18: `?name=etl`, `?name=app`,
`?name=does-not-exist` all return the identical 3-element list), so four manifest keys all
resolved to `pfin-app`'s uuid and the whole per-container confinement collapsed onto the
web-app container. Caught only when someone ran the preflight live, months later.

**The specific blind spot — name it, because it is asymmetric:** I verify doc/ADR citations
reflexively, but I read a citation to *another file's implementation shape* as
self-evidencing. It is not. It is cheaper to check than an ADR (one grep, no interpretation)
and it is more load-bearing, because it is the stated reason a reviewer does not re-derive
the mechanism from scratch.

**How to apply:**
- Any comment naming another in-tree file as precedent → grep that file **in the same turn**
  as reading the comment. Confirm the cited code does the thing claimed, not merely something
  adjacent. One grep.
- **A borrowed idiom carries the lender's unverified premises.** Here the premise was a vendor
  API contract (`?name=` filters). Ask: what does this idiom assume about a system outside the
  repo, and did anyone measure it — or did it just never get exercised?
- **An API that silently ignores an unknown query parameter returns 200 and a plausible body.**
  There is no error to notice. The tell is `?filter=` + `[0]` with no assertion that the
  result actually matches what was asked for. Treat `[0]` off a *filtered* list as an
  unchecked claim that the filter ran.
- When the fix lands, the uniqueness assertion must be over the **resolved set**, not
  per-lookup: the observed symptom was N distinct keys → ONE uuid, which every per-lookup
  "exactly one match" check passes cleanly. See
  [[a-fixture-written-to-match-the-premise-cannot-falsify-it]].

Related: [[false-composite-citation]], [[verify-the-cited-source-subsection-not-the-headline]],
[[hazard-mechanism-vs-reachability]] (the same PR's `-d '$body'` argv branch has zero callers —
the LIVE value-in-argv is the on-box python `-d json.dumps(body)`, not the shell helper).

## Widened: a file's OWN header describing its OWN behaviour is the same class

Second instance, PR #840 (2026-09-20), same surface, found by DevOps not me.
`push-production-secrets.sh`'s header claimed *"the API call itself [is] built with the
token as a `curl -K -` stdin config directive (never an argv element)."* True of the PUSH
step's `api()`. **False of the resolution step's `api()`**, three hundred lines away, which
put the Coolify token straight into curl's `-H` argv on the box. I reviewed this file twice
— at #738 and again in my own #840 pre-read — and both times traced the transport the
header pointed me at, never the other helper.

**The failure is scope, not honesty.** A header sentence about "the API call" reads as
universal; it was written when there was one call site. A second call site was added later
and the sentence silently became a partial truth. Nobody edited a claim into falseness — the
code grew out from under it.

**How to apply:**
- A file-level claim of the form "X is always done via Y" is a claim about **every** call
  site. Enumerate them (`grep -n 'api()' `, `grep -n '<helper>('`) and check each. Two
  helpers with the same NAME in one file is the specific tell — I saw `api()` twice and
  read the second as the first.
- Do not let a header steer which code you read. Read the code the *change* touches, then
  ask what the header now claims about it.
- Same shape as [[feedback_correcting_half_a_hand_maintained_mirror]]: one statement,
  several carriers, only one kept current.
