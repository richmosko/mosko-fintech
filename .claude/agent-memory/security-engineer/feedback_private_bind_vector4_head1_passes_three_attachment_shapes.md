---
name: private-bind-vector4-head1-passes-three-attachment-shapes
description: The compose private-bind fences' external-network check greps the first `name:` line in the top-level networks block, so a SECOND network, a non-`default` key, and a missing `external: true` all pass green while the fence prints "attaches to exactly ${VAR}"
metadata:
  type: feedback
---

`scripts/ci/fence-worker-private-bind.sh` and `scripts/ci/fence-app-private-bind.sh` both implement
their vector-4 external-network check as: find the top-level `networks:` line, collect the block,
`grep -E '^[[:space:]]*name:' | head -1`, substring-test for `${VAR:?`. **Measured 2026-09-20 against
`workers/pdf-render/docker-compose.yaml`, three shapes pass GREEN (exit 0):**

1. A **second top-level network** with the service attached to both (`networks: [default, extra]`).
   This is precisely the multi-attachment axis the fence exists to lint.
2. The network key renamed from `default:` to anything else, with no `default` present. Both scripts'
   headers claim to check `networks.default.name`; neither checks the key name.
3. `external: true` removed — Docker then CREATES a network by that name instead of joining the
   stack's. The fence still prints *"attaches to exactly ${…}"*, which is false.

Shape 3 fails toward isolation (a broken deploy, not a widening) — but the operator's tempting fix for
a resolution failure is the published-port/Domain regression RT-32 and RT-27 exist for, so it is not
inert.

**Why:** the fence's own FAILURE MESSAGE overclaims relative to its predicate — *"or attach to any
network other than exactly `${VAR}:?...`"*. That sentence is what a reviewer reads a green result
against. The header's narrower `networks.default.name` phrasing is closer to true but still wrong on
shape 2.

**How to apply:** when reviewing any private-bind fence, strike the SHAPES the failure message claims
to forbid, not just the ones the golden fixtures cover — the fixtures encode the author's frame.
Catch criterion to hand over: assert the top-level block declares **exactly one** network key, that
the key is `default`, that there is **exactly one** `name:` line (never `head -1`), and that
`external: true` is present; three new goldens, each striking a copy of a real compose and each
asserting its own distinct vector token. **The fix belongs to BOTH scripts** — `fence-app-private-bind.sh`
is the original and has the identical gaps on `main`.
See [[fence-shape-stated-in-prose-is-wrong-twice]] and [[measure-the-fence-regex-not-its-comment]].
