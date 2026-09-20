---
name: filter-side-of-the-ssh-boundary
description: When a pipeline crosses an ssh hop, WHICH SIDE the cut/grep runs on decides whether full secret VALUES or only NAMES cross the wire — read the quoting, not the pipeline
metadata:
  type: feedback
---

In `ssh host "<remote cmd>" | filter`, everything after the closing quote runs
**locally**. The whole remote output — values included — crosses the wire, lands in
the operator's terminal buffer, shell scrollback and the ssh client's pipe, and only
then gets filtered. Moving the filter inside the quotes is a one-character change
with a completely different exposure.

**Why:** PR #825 (2026-09-19) shipped this twice, in the SAME PR that existed to
improve secret hygiene:
- `migrator-cutover-verify.sh:157` — `sshx "docker compose … exec -T meta env" 2>&1 | cut -d= -f1`.
  Leg 9 one function above it got this RIGHT (whole pipeline inside the quotes); leg
  10 did not. Per ADR-072 Amendment 3 every stack service holds the whole env store,
  so the local-cut version dumped POSTGRES_PASSWORD / JWT_SECRET / SERVICE_ROLE_KEY /
  VAULT_ENC_KEY / ANON_KEY / SECRET_KEY_BASE to the operator.
- runbook §6.9 `--post-check` — same shape on `rest`, whose env carries `PGRST_DB_URI`
  (authenticator password) and `PGRST_JWT_SECRET`. **The very next sentence in the
  same paragraph forbade it** ("filter before the value leaves the container").

The regression vector both times was **introducing an ssh hop into a pipeline that
previously had none**. The old by-hand step ran `docker … env | grep …` with the
operator already on the box, so the filter was trivially on-box. Wrapping the first
stage in `ssh "…"` silently relocated every later stage to the wrong side.

**How to apply:** on any diff that scripts a previously-by-hand box step, find every
`ssh`/`sshx` call and mark where the closing quote is relative to each `|`. Ask "does
a VALUE cross this boundary, or only a NAME?" A sibling leg in the same file that
gets it right is evidence of intent, not of correctness — grade each leg separately.
Same question for `docker exec`, `kubectl exec`, and any `-c '<cmd>'` wrapper.

Related: [[a-grep-over-comments-measures-intent-not-data]],
[[enumeration-frame-misses-cluster-level-objects]], Sec #822 F1 (never dump a
container's full env).
