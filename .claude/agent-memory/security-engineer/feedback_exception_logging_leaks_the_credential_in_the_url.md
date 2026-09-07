---
name: exception-logging-leaks-the-credential-in-the-url
description: logger.exception / str(exc) on an HTTP client error writes the request URL to logs, and when the URL IS the credential (webhook, presigned, token-in-path) that is a secret-store violation — check the sibling the module claims to mirror.
metadata:
  type: feedback
---

**The rule.** On any surface that posts to a URL containing a secret — Discord/Slack webhooks,
presigned URLs, any token-in-path — **`logger.exception(...)`, `str(exc)` and `repr(exc)` all leak
it.** Log the exception **type** only.

**Why.** Found at the A7 / PR #642 D1 review (2026-09-06), `workers/etl/src/pfin_back_etl/notify_discord.py`.

- `requests` embeds the request URL in its exception messages. The standard connection-failure form
  is `HTTPSConnectionPool(host='discord.com', port=443): Max retries exceeded with url:
  /api/webhooks/<id>/<token>`. **That path IS the credential** — holding it is sufficient to post.
- `logger.exception` emits the full traceback, whose last line is the exception repr. So a catch-all
  `except Exception: logger.exception(...)` written *specifically to be fail-safe* is the leak.
- ⚠ **Check where the logs GO, not just that they exist.** The entrypoint added a
  `logging.FileHandler(LOG_FILE, mode="a")`, so the credential also landed in an append-only file
  on the container filesystem, accumulating across runs with no rotation. stdout is transient; a
  file is a second, unmanaged secret store.
- The secret was classified `production_only` in `secrets-manifest.yml`. **Writing it to logs moves
  a production secret into a different, broader-access store** — the storage-class discipline is
  defeated without any manifest line changing, so a manifest-only review would not see it.

**⚠ THE FASTEST WAY TO FIND IT: read the sibling the module SAYS it mirrors.** This module's
docstring claimed it mirrored `workers/provider-sync/src/notify/discord.ts`'s "thin, fail-safe
poster". That sibling carries, at its `catch`:
`// Discard the raw error object — keep only a coarse message (never echo the payload/URL body).`
It mirrored the never-raise property and dropped the never-echo-the-URL property. **A claim to
mirror a sibling is a claim about what the guarded region ENCLOSES** — diff the two error paths
statement by statement, not the two shapes. See [[guarded-region-is-the-control-not-the-constant]]
and [[grep-the-existing-battery-before-scoping-a-remediation]] (the convention was already in the
tree; the finding is that it was not carried over, which is a much stronger finding to state than
an invented one).

**How to apply.**

- On any new HTTP-posting module, go straight to the `except` / `catch` and ask **what does the
  library put in the exception message?** For `requests`, `httpx` and `urllib3` the answer is: the
  URL. For Node `fetch` it is usually not, which is why the TS sibling could get away with
  `err.message`.
- Fix shape: `except Exception as exc:` → log `type(exc).__name__` only, with a comment naming why
  `str(exc)`/`repr(exc)`/`logger.exception` are all forbidden **at that call site**, or the next
  editor restores one of them.
- **Require a watcher, or the fix regresses silently:** call the poster with a sentinel token in the
  URL against an unroutable host, capture the logger output, assert the sentinel is absent — and
  inversion-prove by restoring `logger.exception` on a scratch copy and confirming it REDs. Per
  [[inversion-test-the-rationale-not-the-presence]], a leg that cannot fail here is the failure mode.
- **Say the second-order consequence out loud when the manifest claims stability:** the manifest
  comment said *"rotation posture unchanged"*, which is true only while the secret is not leaking.
  A leak forces an unscheduled rotation across every consumer of the shared name — here, four.
