"""
Project:       pfin-back-etl
Author:        Rich Mosko (mosko-fintech Backend)

Description:
    `unit` tests for notify_discord.py (SELF-351 / A7's operator-notification
    module). Pure builder + a network-mocked poster — no live Discord, no DB.
"""

from unittest.mock import patch

import pytest

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
