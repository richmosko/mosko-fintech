---
name: measure-the-fence-regex-not-its-comment
description: Run a fence/test regex against a written list of candidate evasion strings before accepting the coverage its own comment claims — comments over-claim and the over-claim retires the reader's suspicion
metadata:
  type: feedback
---

Never accept a fence's **description** of its own coverage. Write the candidate evasion strings to a
file and match the actual predicate against them. Cite the command and the miss list.

**Why:** at the SELF-218 / migration `067` joint-review, the paired battery's zone leg carried the
predicate `prosrc !~* 'date_trunc|interval|::\s*timestamp'` under a comment asserting it caught "the
parenthesis-free evasions `'today'::date` and `'now'::timestamp`". Measured against nine candidates,
it caught only `'now'::timestamp`. `'today'::date` matches nothing in that alternation — `::date` is
not `::timestamp`. Worse than a plain gap: a **false coverage claim inside a test description retires
the next reader's suspicion at the exact point suspicion was the control.** The same pass had
*replaced* a clock-token deny-list with the "stronger structural" regex rather than supplementing it,
so `current_date` / `now()` / `localtimestamp` — the three tokens the migration header explicitly
instructs future editors not to introduce — ended up with **no watcher at all**.

**Where this defect actually originates** (attribution recorded 2026-08-12 at Architect's own ask):
the control's **owner had a working leg and removed it on a reviewing role's recommendation**, which
was framed as *stronger* while in fact covering a **different class** — date arithmetic, not clock
reads. Nobody was careless; the owner deferred to a reviewer, and "stronger" was never tested against
the retired leg's own member list. **So watch cross-role recommendations that swap one control for
another**: ask what the new form covers that the old did not, and — the question that actually catches
it — what the OLD form covered that the new one does not. A strengthening subtracts nothing.

**The remediation shape that worked** (accepted at `4260c18`, same review): restore the retired leg
**alongside** the structural one rather than merging them; state in the leg's description that the two
are *corroborating, not substitutive*, with a concrete example the structural leg lets through
(`where x <= current_date` has no `date_trunc`/`interval`/`::timestamp`); record the token set's
**provenance as a union of named sources in the file header** so it cannot silently lose members
again; and pin a **negative control** — the legitimate literal the fence must NOT match. Ask for that
shape by name next time.

**The same discipline applies to a PERMISSION DENY RULE, where the matcher is not mine to read.**
At the 2026-08-15 db-reset guard review, DevOps proposed `"deny": ["Bash(supabase db reset*)", …]`.
Two failure axes, neither visible in the diff: (1) **match semantics** — every existing Bash pattern in
`.claude/settings.local.json` uses `<prefix> *` with a **space**, and newer Claude Code documents a `:`
separator; if the matcher reads the entry literally it matches NOTHING and the guard is inert while
looking present. (2) **shell composition** — the matcher is prefix-based on the whole command string,
so `cd <worktree> && supabase db reset …` may not be caught, and that is the form agents actually use
(every Bash call I made that session began `cd … &&`). **When the predicate lives in someone else's
engine, the only measurement available is an empirical probe, so demand one before confirming:** a
positive canary (the real command in a harmless `--help` form, MUST be denied), a compound-command
probe, and a **negative control** that must still run (`supabase status`) so "blocked" can be
distinguished from a session blocked for unrelated reasons. If the compound probe fails, the mechanism
is wrong rather than the pattern — a `PreToolUse` hook sees the full `tool_input.command` and is not
prefix-bound.

**A `PreToolUse` guard hook has its own fail-open, one layer beneath the regex.** The shape
`cmd=$(jq -r '.tool_input.command // empty'); if … grep -qE …; then <emit deny JSON>; fi` **exits 0 and
allows the call** whenever `jq` is missing or errors — the parser is a silent single point of failure,
and it will never be noticed while `jq` happens to be installed. Require `command -v jq >/dev/null ||
exit 2` (exit 2 blocks; the deny-JSON path with exit 0 is the honored protocol and is correct). Second
recurring hole in the same shape: an **interposed global flag** — `supabase --debug db reset` defeats an
adjacency regex like `supabase[[:space:]]+db[[:space:]]+reset`, and it is a form an agent reaches for
while debugging, not an adversarial one; allow flag tokens explicitly:
`supabase([[:space:]]+--?[^[:space:]]+)*[[:space:]]+db[[:space:]]+reset`. Third: `grep` is line-based,
so `[[:space:]]` cannot span a newline — `tr '\n' ' '` first if multi-line invocations are plausible.

**⚠ The rule applies to the regex I PRESCRIBE, not only the one I review — and I have already failed
this once.** At the same db-reset review I flagged that `supabase --debug db reset` / `supabase
--workdir . db reset` evade an adjacency match, then specified the fix as
`supabase([[:space:]]+--?[^[:space:]]+)*[[:space:]]+db[[:space:]]+reset` — which **allows
`--workdir . db reset`**, my own justifying example, because a flag's VALUE is its own token and does
not start with a dash. DevOps caught it by testing text attributed to me instead of treating a
reviewer's recommendation as privileged. **Run every prescribed predicate against its own stated
example before sending it.** Encoding is validation; a rule and its example share my frame, so only
mechanical execution separates them.

**Ruling that followed, worth reusing for total bans:** prefer the BROAD form
(`([[:space:]]+[^[:space:]]+)*` — any interposed token) over a precise flag-parsing one. Where no
legitimate invocation of the phrase exists, precision buys nothing and each extra group is another
`--workdir .`-class miss; the broad form's false positives land harmlessly on commands that merely
*mention* the phrase, which the precise form blocks anyway. **Complexity in a fence is its own defect
class.**

**And scope the control to the HAZARD CLASS, not to the command string that happened to fire.** The
db-reset rule covers one invocation while `supabase stop --no-backup`, `docker compose down -v`, and a
plain `psql -c 'truncate …'` all reproduce the same outcome. Useful framing when the siblings merely
prompt rather than being denied: **the incident's own invocation also prompted, and was approved** — so
the siblings sit at exactly the protection level the wiping command had when it fired. Also worth
saying out loud: **do not over-block** (denying non-destructive `supabase stop`/`start` creates bypass
pressure, which is how guards die quietly), and offer the data-layer option — a pre-flight `pg_dump`
snapshot is the only control whose protection does not depend on guessing the invocation form.

**A NAME-DENYLIST over a catalog column is the same defect in test clothing — and the fix has a
reusable shape.** `self228_v1_1_close_gate.sql` (PR #464) fenced "no scope/tenant/household parameter
on any of the six NAV read functions" with
`coalesce(proargnames,'{}') && array['p_scope','p_users_id','p_tenant','p_tenant_id','p_household_id']
= 0`, under a description claiming *"a future V2 per-scope param addition turns this leg RED by
design."* Five spellings; `p_scope_filter` / `p_scopes` / `p_user_id` (note `p_users_id` was listed and
`p_user_id` was not) all pass green. **Prescribe a POSITIVE PIN instead of a longer denylist:** assert
each function's ordered IN-argument vector equals an expected literal via `proargnames[1:pronargs]`
(`pronargs` counts IN/INOUT/VARIADIC only, so the slice is the IN-arg prefix for `RETURNS TABLE`
shapes — have the author confirm against `proargmodes` rather than take it on my word; QA did, and the
contiguous-`'i'`-prefix property is worth having stated in the file where an interleaved `OUT` param
would break it). A pin catches an added parameter under **any** name, and fails closed on a dropped or
renamed function (`is(NULL, array[...])` fails) and on an overload (scalar subquery raises).
**Name the losing side even when the swap is favourable:** the denylist ran over full `proargnames`,
which for `RETURNS TABLE` includes output-column names, so it incidentally covered an output column
named `p_scope`; the slice drops that. Accidental coverage and a false-positive source — a good trade,
but it goes on the record rather than being reported as a pure strengthening.

**⚠ A TWO-STAGE fence (population filter → extraction → aggregate) has a hole BETWEEN the stages,
and `count(distinct)` hides it. Check the two stages' matching semantics against each other.**
SELF-328's kernel-identity fence: population = `prosrc ilike '%when ''manual_valuation'' then 1%'`
(**case-INsensitive**), extraction = `substring(prosrc from '(?s)case ep\.source.*?limit 1\)')`
(POSIX regex, **case-SENSITIVE** — `(?s)` is not `(?i)`). Measured: the `ilike` matches an uppercase
body, the `substring` returns **NULL** on it, and `count(distinct)` over `('a','a',NULL)` = **1**.
A copy rewritten in uppercase therefore stays in the population (`count(*)`=3, green) and drops out of
the identity set (green) — **both legs green on an arbitrarily diverged copy.** Not hypothetical:
uppercase `CASE ` already appears inside one of the three kernel function bodies, measured.

**The remedy is a POSITIVE PIN, not another evasion patched.** Either
`md5(regexp_replace(coalesce(kernel_block, p.prosrc), …))` — a failed extraction hashes the whole
body, which cannot collide, so it reds regardless of WHY extraction failed — or an explicit
`count(kernel_block) = 3` leg. **Adding `(?i)` is the wrong fix**: it closes the one vector I
imagined and leaves whitespace, renames and restructures open. ⚠ And when the predicate appears in
BOTH the fence and its golden fixture, both copies must change or the fixture stops testing the fence.

**Two reusable generalisations:**
- **NULL is the universal silent-pass in any aggregate that ignores it.** Anywhere an extraction can
  return NULL and feeds `count(distinct)` / `bool_and` / `string_agg`, ask what happens when it does.
- **The good version of this catch appeared one level down in the same file** — QA correctly refused
  to anchor extraction on the text the mutation removes, for exactly this reason. **A team that
  closes the vector it found has not closed the class.** When someone defends against a NULL-exclusion
  hole, look immediately for a second path to the same hole.

**⚠ The INVERSE failure: a set of raise-message classifiers with a GAP, where the fall-through is a
500.** At PR #564 the classify path's error branch tested `isJournaledCatFenceRejection` then
`isCrossTenantSubCat` then `error.code === '23503'`, else a generic 500 "Please try again." But
`084`'s `fn_account_trans_annotation_trade_constraints` raises `'Trade consistency violation …'` on
that same write — P0001, and its text carries no `sub_cat` / `Decision 3` / `matched-tenant`, so it
matches **nothing** and lands on the 500. A user-input error, reported as a server error, with retry
advice that can never work. **Reachability came from a UI change, not a DB change:** the new picker
sourced `pfin.posting_prototype` with no `cat` filter, and `041` seeds `Trade/BTO` + `Trade/STC` into
every provisioned user — so a trigger that had been endpoint-only became one click from every row.
**Two reusable moves:** (1) when reviewing a classifier CHAIN, enumerate every trigger and constraint
on the WRITTEN table and check each raise against the chain — the residual is what the fall-through
message will claim; (2) when a PR adds a picker/dropdown over a vocabulary table, ask which rows the
query does NOT filter out and what fires when one of them is chosen. A read-side change can move a
DB fence from unreachable to everyday without touching a migration.

**How to apply:** whenever a review surface includes a grep/regex fence, a `prosrc` assertion, or a CI
token gate — build the candidate list first (include the parenthesis-free special literals
`'today'::date` / `date 'today'` / `'now'::date`, both spellings of the zone-aware type, and bare
`date ± integer` arithmetic), then `grep -E` the real predicate over it. Also ask whether the new form
**replaced** rather than **extended** an older fence: replacement is where coverage silently
disappears while the diff reads like a strengthening. Related: [[sec-lock-cross-check-catches-my-own-misreads]].

⚠ **MY OWN PROBE IS THE FENCE TOO — two self-inflicted misreads in one review (SELF-257).**
(1) **I graded a coverage inventory against a label format I assumed from a sibling file.** The
`099` battery labels legs `'(X1a) …'`, so I grepped `093`'s for `(R1)`/`(S3a` and got zeros —
and nearly reported a fabricated defect. `093` labels its legs `'093 R1: …'`. **All 17 cited
labels existed.** Enumerate the target's ACTUAL label form (`grep -oE "'[0-9]{3} [A-Za-z0-9-]+:"`)
before testing membership; never carry a sibling's convention into a probe.
(2) **I counted 34 pgTAP legs as 33** because my verb alternation omitted `throws_like`. A leg
count that disagrees with `plan(N)` by one is far more likely to be my regex than their
arithmetic — **re-run with the full verb list before reporting a plan mismatch.**
Both errors fail in the direction of a FALSE FINDING, which is the expensive direction: name them
in the same message as the real findings.

⚠ **A FAILED GREP AND A CLEAN RESULT ARE THE SAME OUTPUT — and the cost can land on someone else.**
Architect went to confirm a measurement was in a commit message; their pattern spanned a line break
that the message wraps across, so the grep returned nothing. For a few seconds the correct-looking
conclusion was *"it didn't make it in — amend the commit"* — which would have **rewritten a sha I had
just signed and verified**, over a regex artifact. They re-checked looser instead.
**Three transferable pieces:**
- **A negative grep is a claim about the PATTERN, never about the tree.** Before acting on an
  absence, re-run looser (drop the anchors, shorten to a distinctive fragment, `grep -c` a word you
  know is present as a positive control). This is the same shape as my own two SELF-257 probe errors
  above — assumed label format, omitted `throws_like` verb — all three fail toward a FALSE FINDING.
- **Line-spanning is the specific trap in commit messages, wrapped prose and HTML.** Corpora that
  reflow defeat single-line patterns; `grep -z`, `tr -d '\n'`, or a Python read is the fix.
- **Grade the blast radius of acting on the negative.** Here it was `--amend` on a signed,
  countersigned sha — a destructive, cross-agent action justified by a null result. **When the
  remedy for an absence is destructive or touches another agent's verified artifact, the bar for
  the measurement is higher, not the same.**
