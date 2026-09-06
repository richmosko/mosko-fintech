"""
Project:       pfin-back-etl
Author:        Rich Mosko (mosko-fintech Backend)

Description:
    `unit` tests for notify_discord.py (SELF-351 / A7's operator-notification
    module). Pure builder + a network-mocked poster — no live Discord, no DB.
"""

import logging
from unittest.mock import patch

import pytest
import requests

from pfin_back_etl.notify_discord import build_run_summary_alert, post_discord

pytestmark = pytest.mark.unit


class TestBuildRunSummaryAlert:
    def test_success_payload_has_no_failure_emoji(self):
        summary = {"total": 5, "ok": 5, "failed": 0, "target_month": "2026-08-01"}
        payload = build_run_summary_alert(summary, "2026-09-05T00:00:00+00:00")
        assert "✅" in payload["content"]
        assert "🚨" not in payload["content"]

    def test_failure_payload_flags_the_run(self):
        summary = {"total": 5, "ok": 3, "failed": 2, "target_month": "2026-08-01"}
        payload = build_run_summary_alert(summary, "2026-09-05T00:00:00+00:00")
        assert "WITH FAILURES" in payload["embeds"][0]["title"]

    def test_fields_carry_counts_and_target_month_only_no_tenant_data(self):
        summary = {"total": 2, "ok": 1, "failed": 1, "target_month": "2026-08-01"}
        payload = build_run_summary_alert(summary, "2026-09-05T00:00:00+00:00")
        field_names = {f["name"] for f in payload["embeds"][0]["fields"]}
        assert field_names == {"target_month", "total", "ok", "failed", "run_at_utc"}

    def test_deterministic_no_clock_read(self):
        """PURE — same inputs, same output, across two calls."""
        summary = {"total": 1, "ok": 1, "failed": 0, "target_month": "2026-08-01"}
        p1 = build_run_summary_alert(summary, "2026-09-05T00:00:00+00:00")
        p2 = build_run_summary_alert(summary, "2026-09-05T00:00:00+00:00")
        assert p1 == p2


class TestPostDiscord:
    def test_missing_webhook_url_is_a_clean_noop_returns_false(self):
        assert post_discord(None, {"content": "x"}) is False
        assert post_discord("", {"content": "x"}) is False

    def test_2xx_response_returns_true(self):
        with patch("pfin_back_etl.notify_discord.requests.post") as mock_post:
            mock_post.return_value.status_code = 204
            assert post_discord("https://discord.example/webhook", {"content": "x"}) is True

    def test_non_2xx_response_returns_false_never_raises(self):
        with patch("pfin_back_etl.notify_discord.requests.post") as mock_post:
            mock_post.return_value.status_code = 500
            assert post_discord("https://discord.example/webhook", {"content": "x"}) is False

    def test_network_exception_is_swallowed_never_raises(self):
        with patch("pfin_back_etl.notify_discord.requests.post", side_effect=Exception("boom")):
            assert post_discord("https://discord.example/webhook", {"content": "x"}) is False


class TestPostDiscordUrlLeakage:
    """Sec finding (SELF-351 A7 review, FLAG-1): the Discord webhook URL is the
    `production_only` credential, and `requests` embeds the request URL in its
    OWN connection/timeout exception text
    (`HTTPSConnectionPool(host='discord.invalid', ...): Max retries exceeded
    with url: /api/webhooks/.../SENTINEL`) — `str(exc)`, `repr(exc)`, and
    `logger.exception` (which logs the traceback, itself carrying the
    exception's string form) ALL leak it. Fixed by logging only the exception
    TYPE (`post_discord`'s `except Exception as exc: logger.warning(f"...
    ({type(exc).__name__})...")`).

    A REAL (unmocked) `requests.post` call against an RFC 2606 `.invalid`
    host is used deliberately, not a mocked exception — a mock cannot be
    trusted to reproduce `requests`' own URL-embedding exception text, which
    is exactly the mechanism this leg guards against.

    STRIKE RESULT (inversion proof, matched pair):
    `test_the_webhook_url_never_reaches_the_log_on_failure` passes against the
    fixed `post_discord` (below). `test_inversion__the_struck_pattern_does_leak`
    reproduces the STRUCK pre-fix pattern (`except Exception: logger.exception(exc)`)
    against the SAME sentinel URL and confirms the sentinel DOES appear in that
    case — i.e. the leg is not one that would pass regardless of which pattern
    ships; it discriminates the exact defect FLAG-1 named.
    """

    _SENTINEL = "SELF351-SENTINEL-TOKEN-4f9c2b"

    @staticmethod
    def _webhook_url(sentinel):
        # RFC 2606 `.invalid` — guaranteed non-resolving, a fast deterministic
        # DNS failure, no live network dependency, no flakiness.
        return f"https://discord.invalid/api/webhooks/000000000000000000/{sentinel}"

    def test_the_webhook_url_never_reaches_the_log_on_failure(self, caplog):
        with caplog.at_level(logging.DEBUG, logger="pfin_etl"):
            result = post_discord(self._webhook_url(self._SENTINEL), {"content": "x"})
        assert result is False
        combined = "\n".join(
            f"{record.getMessage()}\n{record.exc_text or ''}" for record in caplog.records
        )
        assert self._SENTINEL not in combined
        # A real leg, not a leg that cannot fail (per the inversion-testing
        # discipline): confirm it actually observed the failure path at all.
        assert any("notify_discord" in record.getMessage() for record in caplog.records)

    def test_inversion__the_struck_pattern_does_leak(self, caplog):
        """Reproduces the pre-fix shape directly (not by patching the shipped
        module — the struck code no longer exists there to restore) against
        the exact same real, unmocked failure this test file's sibling above
        exercises. Confirms the sentinel DOES leak under `logger.exception`,
        proving the discriminating power of the leg above."""
        logger = logging.getLogger("pfin_etl")
        webhook_url = self._webhook_url(self._SENTINEL)
        with caplog.at_level(logging.DEBUG, logger="pfin_etl"):
            try:
                requests.post(webhook_url, json={"content": "x"}, timeout=5)
            except Exception:  # noqa: BLE001 — deliberately mirrors the struck pattern
                logger.exception("notify_discord: POST to Discord webhook failed (struck pattern).")
        combined = "\n".join(
            f"{record.getMessage()}\n{record.exc_text or ''}" for record in caplog.records
        )
        assert self._SENTINEL in combined
