# `workers/etl/tests/fixtures/replay/` — synthetic record-replay payloads

Frozen, deterministic, **synthetic** BLS + FMP HTTP response payloads for the ETL integration
tier. Replayed (not live-fetched) so the integration tests are deterministic and need **zero**
production API keys.

**Governance:** these payloads are governed by the central RT-15 parity-fixture access-control
discipline at [`tests/fixtures/parity/README.md`](../../../../../tests/fixtures/parity/README.md).
**No production data. No PII. No real account numbers. No real API keys.** All values are
authored synthetic equivalents grown from the `conftest.py` sample shapes
(`sample_bls_cpi_json` / `sample_fmp_income_json` / `sample_fmp_profile_json`) to production
*shape* — never copied from a live call.

The synthetic ticker `ZZTEST` is used so payloads are unmistakably non-production; market-data
values are obviously-synthetic round numbers. The ETL parse path (snake_case conversion,
new/updated-row isolation) is identity-agnostic, so synthetic identity exercises the real code
path faithfully.

| File | Replays | Source seam |
|---|---|---|
| `bls_cpi.json` | BLS CPI timeseries response | `utils.fetch_cpi_df` → `requests.post("https://api.bls.gov/...")` |
| `fmp_income_statement.json` | FMP income statement response | `PFinFMP.fetch_fmp_df` → FMPStab method `rsp.json()` |
| `fmp_profile.json` | FMP company profile response | `PFinFMP.fetch_fmp_df` → FMPStab method `rsp.json()` |

Load via `tests/replay.py` → `load_replay("bls_cpi")`. See that module for the monkeypatch
seams.
