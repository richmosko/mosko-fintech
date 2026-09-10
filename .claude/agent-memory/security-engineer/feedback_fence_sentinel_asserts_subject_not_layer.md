---
name: fence-sentinel-asserts-subject-not-layer
description: Reusing an existing fence's sentinel on a different-subject file is layer-attribution drift; and an RT label in a workflow mints a CI-fenced-set member by side effect
metadata:
  type: feedback
---

**A fence's target sentinel ASSERTS what the file IS, not what layer it sits at. Two surfaces that share a LAYER but not a SUBJECT get separate fences with separate sentinels.**

**Why:** `scripts/ci/fence-admission-private-bind.sh` requires the line
`# fence-admission-private-bind: target` and refuses (exit 2) without it — so
placing that sentinel in a file declares *"this is the admission manifest."*
When the Supabase stack's compose needed the identical three-vector check
(published `ports:` / public-FQDN label / `network_mode: host`), the tempting
move was to point the existing script at it. Refused: **RT-27's SUBJECT is a
credential-admission channel; its LAYER is network-exposure/config**
(ADR-011 D4's own §10 boundary ruling). The Supabase compose shares the layer
and not the subject. Reusing the sentinel would be precisely the
layer-attribution drift D4's CHANGELOG catalogues. The pdf-render **N-4**
precedent — an *intra-instance* RT-27 expansion — does not carry, because
pdf-render's compose genuinely IS an admission manifest.

**How to apply:** when a second surface wants an existing fence, ask whether it
shares the fence's SUBJECT or only its LAYER.
- Same subject → intra-instance coverage expansion, CI-fenced side only, no
  ledger effect (the N-4 shape).
- Same layer, different subject → **sibling script with its own sentinel**, or a
  shared checker parameterized by sentinel token. Never one sentinel over two
  subjects.

**Corollary — an `RT-NN` string in a workflow file MINTS a CI-fenced-set member
by side effect**, because the set is *measured* by
`grep -rhoE 'RT-[0-9]{2}' .github/workflows/`. So when a new fence needs an RT
id it does not have yet: **merge the job with NO RT label**, and add the label
only after the SECURITY §4.5 catalog entry is ratified. Otherwise a DevOps
commit silently changes a set whose boundary changes are an escalation trigger.
Also: recommend, never mint, a §10 catalogued instance — cataloguing is an
F/CTO D4 ratify, not a deploy-time act.

Related: [[feedback_enumeration_and_watcher_stop_one_short]] ·
[[project_ci_fenced_set_grep_must_not_be_tightened]] ·
[[feedback_corrupt_the_control_canary_boundary_tie]]
