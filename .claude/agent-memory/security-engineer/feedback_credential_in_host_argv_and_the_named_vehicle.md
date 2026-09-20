---
name: credential-in-host-argv-and-the-named-vehicle
description: B10's prohibition extends past ALTER ROLE to any credential expanded in an OPERATOR-side command line; and a runbook that names a container as the vehicle is claiming that container holds the binary
metadata:
  type: feedback
---

Two findings from the PR #752 migrator-bootstrap review that recur together, because a runbook bullet that names a vehicle usually also names a credential.

**1. `docker ... exec ... --db-url "postgres://user:${PW}@..."` puts the plaintext in the HOST's process argv.**
The expansion happens in the operator's shell, so the docker *client* argv carries it. `ps auxww` / `/proc/*/cmdline` are world-readable by default, and this repo's runbook §1 step 3 deliberately creates a **separate non-root operator account** — so it is a documented local-account path to whatever the credential is. When the credential is `POSTGRES_PASSWORD` (cluster superuser) it is strictly higher-value than the `pfin_etl` password B10 was written about.

**Why:** Sec B10 (2026-08-02) is recorded in runbook §6.1/§6.2/§6.3 as a prohibition on the single-statement `ALTER ROLE … WITH LOGIN PASSWORD '…'` form, with the rationale *server log + `~/.psql_history`*, and the flag-#10 retraction adds that an interactive session *"dodges shell history and lands in psql's own plaintext `~/.psql_history`"*. The rationale is the CLASS — "a credential in a place that gets recorded or observed" — and it travels to channels B10's literal text never names. Read B10 verbatim from §6.1 before citing it, then argue the class, not the letter.

**How to apply:** the acceptance criterion is *no host-side process argv and no shell-history line contains the plaintext*. Accept: piping the secret on **stdin** and building the URL inside `sh -c` in the container; or a mode-0600 file read inside the container. ⚠ **REJECT `-e PGPASSWORD="$PW"` — `-e KEY=VALUE` lands in the docker client's argv and fixes nothing.** REJECT moving a superuser credential into a standing container's Coolify env (persists at rest; worse than the argv window). Also check whether the doc gives a **sourcing** step: if it only says "the value is in `/root/.pfin/foo.env`", a stranger will `cat` and paste the literal, adding shell history to the argv leak.

**2. A runbook naming `exec <container> <binary>` is asserting that image contains that binary — grade it.**
`infra/supabase/migrator/Dockerfile` installs `ca-certificates curl tar` only; the Supabase CLI ships no `psql`. A §6 bullet directed the §4/§4.1 verification reads at `exec -T migrator psql …`, which returns `psql: not found`. Also `exec -T` suppresses the TTY that `\password` **requires**.

**Why:** the operator blocked at a 🔒 SECURITY-SENSITIVE credential handoff reaches for the nearest alternative, and in this document the nearest alternative is the B10-PROHIBITED single-statement form. A broken vehicle at a handoff step is a re-entry path for the exact defect the handoff exists to prevent.

**How to apply:** grep the Dockerfile's install line before accepting any `exec <svc> <bin>` in a runbook. Redirect to the service that already holds the binary (here: `db`, which authenticates over the local socket and needs **no password in any command line** — solves finding 1 for free). ⚠ **Say explicitly "do not fix this by installing the client into the lean image"** — ADR-011 D4's Privileged-context-surfaces bullet names *"no Postgres client installed in Dockerfile"* as a §10 layer for RT-22/the PDF worker, and a well-meaning fix elsewhere invites the same erosion on a surface where the attribution does not apply. See [[a-hazard-has-two-falsifiable-halves-mechanism-reachability]] and [[runbook-must-serve-a-stranger]].

**3. ⚠ MY OWN ERROR, caught at the re-confirm: single-quoting the `sh -c` body to defer the SECRET also defers every OTHER `${VAR}` in it.**
I supplied a commit-ready block that piped the password on stdin and single-quoted `sh -c '… --db-url "postgres://postgres:${PGPW}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}" …'`. The single quotes correctly kept `${PGPW}` from host-expanding — and equally kept the three NON-secret vars from host-expanding, moving them to a container where they are **not defined**. Measured: the migrator service's `environment:` block sets `PROD_DB_URL` and nothing else; `POSTGRES_HOST`/`PORT`/`DB` are Coolify **env-store interpolation** vars consumed when compose RENDERS, never container environment. DevOps committed it verbatim because I told them to, so no one else was ever going to catch it.

**Why:** deferring expansion is a per-variable decision, but quoting is an ALL-OR-NOTHING switch over the whole body. Every `${VAR}` inside a single-quoted `sh -c` is a claim that the CONTAINER defines it. Compose-file `${VAR}` interpolation and container `environment:` keys look identical in the YAML and are different scopes — the interpolated value reaches the rendered string, not the process env.

**How to apply:** before handing over any `exec … sh -c '…'` text, **enumerate every `${VAR}` in the body and grade each one host-side or container-side**, then read the service's `environment:` block (and check for `env_file` / `x-` anchors) to confirm the container-side ones exist. Prefer literalising non-secret values the doc already states in the clear — lowest fragility, keeps the single-quote structure. The alternative is a double-quoted body with `\${SECRET}` escaped, which host-expands the non-secrets into argv (safe: not secret) and defers only the secret. ⚠ This failed **closed** (malformed URL → error), but a stranded operator at a 🔒 credential step is the improvise-toward-the-prohibited-form hazard from finding 2 — so a fail-closed break in a security procedure is still blocking. See [[supplied-verbatim-text-ships-unfiltered]], [[my-requirement-can-be-voided-by-an-artifact-i-did-not-read]] and [[adding-vs-qualifying]] — my own supplied text is the unchecked one.

**⚠ COMPARE SIBLING SCRIPTS INTRODUCED IN THE SAME PR AGAINST EACH OTHER — asymmetry inside one PR is
the tell (PR #833 r2, 2026-09-19).** That PR added three new operator scripts. Two (`deploy-app.sh`,
`smoke-pfin-exposure.sh`) put the Coolify token on `curl -K -` (stdin config) **and named the residual
they still keep** in their headers. The third (`provision-app.sh`) used a plain
`-H "Authorization: Bearer $TOKEN"` — the box-side argv — **and said nothing about it.** Every
individual choice had a precedent; the *set* did not. Reviewing each file on its own merits would
have cleared all three.

**Why this is worth its own habit:** a copied-from-a-sibling script inherits the sibling's *shape* but
not its *header*, so the weaker channel arrives with the stronger one's credibility. And a residual
that is accepted-and-named in file A but silent in file B reads, to the next author, as "file B has no
residual" — the acceptance widens without anyone deciding to widen it
([[feedback_an_accepted_residual_must_not_silently_widen]]).

**How to apply:**
- On any PR adding more than one script that talks to the same API: **tabulate the credential channel
  per file before reading any of them closely.** One `grep -n 'Authorization: Bearer\|-K -' scripts/*.sh`
  answers it. Then ask which files *name* what they keep.
- The remediation menu is always two-tier: **(A)** adopt the stronger helper — usually already present
  in the same PR, so the cost is a move not a design; **(B) minimum** — name the residual in the new
  carrier's header, in the same shape the sibling uses. Offer (B) so the flag cannot be read as a block.
- Related: [[project_provision_scripts_shell_api_has_no_dash_k]] (the standing fact about which family
  uses which channel), [[feedback_filter_side_of_the_ssh_boundary]].
