---
name: backup-rotation-prunes-its-own-recovery-points
description: Review a backup control by running the DEFENDED-AGAINST event through the retention policy — keep-newest-N deletes the real recovery points after the wipe it exists to survive; prefer a retention-SHAPE fix (never prune the largest) over a size-ratio heuristic, which fails on a schema-dominated dump; also check file mode, cloud sync, and never-blocking⇒never-watched
metadata:
  type: feedback
---

When reviewing any snapshot / backup / recovery-point control, **run the defended-against event forward
through the retention policy.** The question is not "does it capture the data" but "what does the
incident do to the archive."

**Why:** PR #473's pre-flight `pg_dump` (my own rec C, from the PR #463 db-reset guard review) rotated
`ls -t | tail -n +$((KEEP+1)) | rm` — keep-newest-10 **by mtime**. But `supabase db reset`, the exact
event it defends against, leaves a migrations+seed-only database. The next run dumps that, `pg_dump`
exits **0** (a valid dump), it is promoted to a real snapshot name, and rotation deletes the **oldest**
— the real data. Ten runs and every pre-incident recovery point is gone, silently. The wipe makes the
worthless snapshots the *newest* ones, so a recency-ordered policy destroys precisely what it was
holding. Accelerated by the script's own advice to run `--force` before anything destructive.

**The fix shape to ask for, and it fails safe by keeping MORE:** before pruning, compare the new dump's
size to the **largest retained** one; if the new one is dramatically smaller, **skip pruning entirely**
and log a loud warning. Plus a floor: never promote a `.partial` under some byte count. Do **not**
prescribe the threshold — have the owner measure a real-vs-post-reset dump pair. Decline tiered
grandfather retention unless asked for: complexity in a guard is its own defect class.

**Two companions that showed up in the same review and generalize:**

- **A full `pg_dump` is a strictly weaker container than the database it came from.** `mkdir -p` and
  `>"$file"` inherit umask 022 → dir 755, dump 644; `mv` preserves the mode. An `-Fc` all-schema dump
  carries the `auth` schema (password hashes, refresh tokens, sessions, MFA factors) plus SD-15 /
  SD-03-class columns, unencrypted, retained N deep, in `$HOME` — while the live DB sits behind
  container auth. Require `umask 077` **before** the `mkdir` and the redirect (covers dir, tmp, output
  and the stderr log in one line), plus an explicit `chmod 700` since `mkdir -p` no-ops on an existing
  755 directory. ⚠ Also ask the one thing the tree cannot answer: **is that path cloud-synced?** A
  synced dump changes the blast radius entirely and is not a question about the location.
- **"Never blocks" and "never watched" arrive together.** A hook that must not stop a session exits 0
  on every path — correct — but then a *persistently* failing snapshot is invisible by construction.
  Ask for a staleness-aware warning (skip/fail **and** newest snapshot older than N hours ⇒ a
  distinctly-marked WARNING line), not for a blocking failure. Same file: an unvalidated
  `KEEP` deletes everything (`KEEP=0`, or any non-numeric → `0` in bash arithmetic → `tail -n +1`).

**⚠ SEQUEL — my 0.5x number was wrong for this repo, and a size RATIO is the wrong instrument here.**
DevOps implemented the guard faithfully and it does not fire in the incident scenario. `supabase db
reset` **re-applies migrations**, so the post-reset dump carries the FULL SCHEMA (measured ~911KB),
not the ~900B of a genuinely empty database — against a ~1.4MB populated dump that is 0.65, above any
usable threshold. General form: **the ratio guard only bites once the database's DATA exceeds its
SCHEMA in dump bytes**, and on a young schema-dominated database it never does. Raising the ratio
doesn't help — at 0.9x it fires on routine churn and gets ignored. **A correct edit on a wrong
premise, and the premise was mine**: I handed over a number while saying "measure it", and the pair
that decides it is real-vs-**post-reset**, which is not the pair anyone naturally measures
(real-vs-empty and real-vs-schema-only both look like the right experiment). **Derive the ratio from
the schema/data split yourself before quoting one.**

**Prefer a retention-SHAPE fix over a detection heuristic:** *never prune the largest retained
snapshot.* It cannot be mistuned, depends on no measurement being right, keeps one pre-incident
recovery point by construction, and its worst case is one stale file after a legitimate permanent
shrink. Row-count canaries stored beside the snapshots are the precise alternative; keep the byte
floor and ratio guard alongside either, since they are real controls for truncated / wrong-target
dumps — just not for the wipe.

**Resolution, and what the shape-fix does and does not buy.** "Never prune the largest retained
snapshot" landed and works: trace the wipe forward and exactly one pre-incident dump survives
indefinitely, with no threshold in the path. Ask for the **negative control** that a naive version
would fail — largest-is-newest at `KEEP=1` must still prune to exactly `KEEP`, or the guard has
silently become "retain one extra forever." Remaining bound, worth stating when you approve it:
largest is a proxy for *most valuable*, so a junk large dataset can absorb the protection and let the
useful snapshot rotate out — the guarantee is "a recovery point survives", not "a good one does".
Don't block on a case you didn't raise once the ruled remediation is implemented exactly.

**How to apply:** for any backup control ask, in order — (1) what does the defended event do to the
retention policy, (2) what mode does the artifact land at and what is actually inside it, (3) what
watches that the control is still running, (4) which env knobs are unvalidated and what is the worst
value. Related: [[assertion-with-no-watcher]] and
[[measure-the-fence-regex-not-its-comment]] (a control's description over-claiming its coverage).
