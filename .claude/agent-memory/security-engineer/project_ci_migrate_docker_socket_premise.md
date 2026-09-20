---
name: ci-migrate-docker-socket-premise
description: RESOLVED 2026-09-17 in the fail-closed branch — ci-migrate cannot reach the docker socket, so C1/C5 hold and the sha + delivery assertions are inert by failure
metadata:
  type: project
---

`scripts/migrator-orchestrate.sh` runs **as `ci-migrate`** and uses `docker compose --project-name <uuid> exec -T …` in two places: the sha-check (`cat /workspace/.build-sha` in `migrator`) and, since PR #798, the delivery assertion (`psql -U supabase_admin` in `db`). **Nothing in the repo grants `ci-migrate` docker-socket access, and `provision-vps.sh`'s C1 arm DIES if `ci-migrate` is in the `docker` group.** Measured at `88b3a213`: the only `-aG`/`setfacl`/`docker.sock` hit in that script is `usermod -aG sudo deploy`.

**Why:** two live branches, different owners. (a) No socket access → both checks fail closed (exit 3 / exit 6) and the CI trigger path is **wedged and never exercised end-to-end as `ci-migrate`** — operational. (b) Access via a non-group route (setfacl, socket mode, rootless docker) → **docker socket is root-equivalent on a Docker host, so ADR-072 C1 and C5 are BOTH void as written** (`docker run -v /:/host` rewrites the root-owned orchestrator), and `id -nG` **cannot see an ACL** — the same blind-spot class as my FLAG 1 on PR #771, where `sudo -ln -U` could not see group membership. See [[feedback_catalog_invisible_capability]].

**RESOLVED 2026-09-17 (F/CTO box measurement), branch (a).** `ci-migrate` groups = `ci-migrate,users`; `/var/run/docker.sock` `root:docker 660`, no ACL; `sudo -l` not allowed; `sudo -u ci-migrate docker compose … exec -T migrator true` → permission denied, exit 1. **C1 and C5 hold as written.** Consequence: the CI trigger path has never run end-to-end as `ci-migrate`, and #790's sha assertion + #798's delivery assertion are **inert by failure** — the next fire exits 3 at the sha step. ADR-072 Amendment 7 is drafting options to source both values without the socket (A group/ACL rejected as root-equivalent; B narrow sudoers; C the task's own stdout via the executions API; D a root timer writing to `/run/pfin`).

**How to apply:** the pattern is the durable part — a code comment asserting a box capability as settled fact, contradicted by the repo's own provisioning check. Re-measure with `sudo -u ci-migrate docker compose … exec -T migrator true; echo $?` plus `stat -c '%U %G %a'` and `getfacl` on `/var/run/docker.sock`. **Do not accept a comment asserting "ci-migrate already has this access" as settled** — it is an unverified premise stated as fact. Branch (b) is an ADR-072 amendment and an F/CTO call, never a script tweak. Re-check this memory against the tree before citing it; it may have been measured since.
