---
name: stack-transport-posture-plaintext-in-network
description: Sec ruled sslmode=disable (explicit, not prefer) for the in-network Postgres hop; workers/etl defaults to require and is a latent connect-failure until its prod env overrides it
metadata:
  type: project
---

**Ruling (2026-09-14, Sec consult ahead of PR #757 / §7.36 item 26):** the Supabase stack's in-network Postgres hop is **plaintext, stated explicitly as `sslmode=disable`** — not left to libpq's `prefer` default, and not TLS-on-`db` for V1.

**Why:** measured on `origin/main`, the stack already held two contradictory postures. Every compose consumer (`GOTRUE_DB_DATABASE_URL`, `PGRST_DB_URI`, supavisor `DATABASE_URL`, migrator `PROD_DB_URL`) specifies **no** `sslmode`, so all four run on libpq's `prefer` → silently plaintext, which is why nobody noticed there is no TLS on this stack. Meanwhile `workers/etl/src/pfin_back_etl/utils.py` resolves a **`require` default** (PR #355 / §7.6 S11, deliberately fail-closed for unspecified environments). `disable` is not weaker than the status quo — same wire, made greppable. TLS-on-`db` was rejected for V1 because `require` without `verify-*` is encryption without authentication (useless against the only adversary that matters here, and a passive sniffer on that bridge already reads `POSTGRES_PASSWORD` from every sibling container's env), and `verify-ca` needs a CA rotation owner that does not exist.

**How to apply:**
- ⚠ **`workers/etl` and `workers/provider-sync` are a LATENT connect-failure** — they will fail exactly as the migrator did the first time their containers start against production. The fix is **`PFIN_DB_SSLMODE=disable` in the production Coolify env**, never a change to the code default: S11 chose `require` so an unspecified environment fails closed, and relaxing the default would destroy that.
- ⚠ **The ruling creates a dependency on RT-32.** "Plaintext is acceptable" is load-bearing on `db`/`supavisor` staying `expose:`-only. **Re-open trigger: if any RT-32 vector is ever opened, or any off-host consumer appears, (a) is VOID and TLS becomes required.** Treat a proposal to host-publish `db` as also being a proposal to re-open this ruling.
- **`sslmode=prefer` is rejected outright** — it makes the transport unobservable from configuration and is exactly how this went unnoticed.
- **No ADR-072 amendment, no new RT id, no CI-fence change.** It is a transport parameter, not a confinement change: C7/C8 untouched. RT-32's vectors (`ports:` / proxy Domain / `network_mode: host`) are blind to a query parameter.
- **Rule it together with §7.36 item 22** (`PGRST_DB_SCHEMAS` / whether `pfin` is exposed via PostgREST): if `pfin` is exposed, `rest` carries tenant financial rows over this same plaintext hop. Transport and exposure are one decision seen from two sides. No interaction with item 24.
- **Suspended if** `show ssl` on `db` returns `on` — the whole ruling infers TLS-off from the CLI error plus three libpq clients connecting on `prefer`. Re-read before acting if that measurement contradicts it.
