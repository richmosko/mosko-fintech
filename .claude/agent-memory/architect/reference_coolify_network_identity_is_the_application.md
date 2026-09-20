---
name: coolify-network-identity-is-the-application
description: Coolify's unit of Docker-network identity is the APPLICATION, not the project — same-project placement confers no reach; attachment must be explicit (external: network or the predefined-network toggle)
metadata:
  type: reference
---

**Coolify's unit of Docker-network identity is the APPLICATION, not the Coolify project.** Every `dockercompose` resource gets its own network named for its own UUID. Project membership attaches nothing and grants no service-name DNS resolution. Reach is a property of **declared network attachment** only.

**Two mechanisms, different widths:**
- **(b) `external:` network in the service's own committed compose**, naming the target application's network — attaches exactly one member, stays in committed/lintable config. **MEASURED WORKING on Coolify 4.3.18, 2026-09-19.** The standing convention.
- **(a) the predefined-network toggle** (`settings.connect_to_docker_network`) — fallback only; ADR-072 Amendment 4 grades it a widening of `db`'s reachable-from set, on an axis RT-32 cannot see. `false` on every resource as of 2026-09-19.

**The control experiment, so it is never re-derived:** `pfin-migrator` was created **inside the Supabase stack's own Coolify project** and still could not reach `db` until its compose declared the stack's network `external:`. After attachment (standup-log §6.8 step 2, deployment `vpwlnr4t9o0mci7qkmsq7odf`): container on both networks, `getent hosts db` resolves, `pg_isready -h db -p 5432` accepting. **Same project, no reach.**

⚠ **The runbook carried the false premise in §3 and still carries it in at least four §7/§10 CA-4 carriers** — while §4 (1d) and §10 CA-7 simultaneously record the attachment as *"confirmed not automatic and not project-scoped, has to be flipped on both sides."* A doc can hold both sides of a falsified premise at once; grep for BOTH before citing either. Corrected at [[adr-073]] (2026-09-19); ADR-072 Amendment 4's own Decision A parenthetical still carries it, left unedited per keep-and-annotate.

**Consequence for design:** Coolify project/environment placement is an organizational convenience with **no connectivity or security meaning**. Never argue a reachability property from project membership. Related: [[a-locks-join-list-is-a-dated-artifact]], [[consequence-list-inherits-its-authors-instrument]].
