"""
Project:       pfin-back-etl
Author:        Rich Mosko

Description:
    Integration tests for ETL update operations.
    Requires valid .env credentials to connect to SupaBase and external APIs.
"""

import logging
import pytest
import pfin_back_etl as pfbe

SYMBOL_LIST = [
    "NVDA",
    "AAPL",
    "IREN",
    "V",
    "ALAB",
    "APP",
    "GOOGL",
    "META",
    "ABXL",
    "MSFT",
    "UAMY",
    "VIR",
    "VRTX",
    "MPT",
    "ADSK",
    "PANW",
]

logger = logging.getLogger("test_dbase")


@pytest.mark.integration
def test_update_table_cpi(backend):
    backend.update_table_cpi()
    backend.update_table_cpi(num_years=2)


@pytest.mark.integration
def test_update_table_cpi_u_index(backend):
    # Requires migration 053 (pfin.cpi_u_index) applied in the test fixture.
    # Idempotent upsert: run twice, second run must not raise (revision path).
    backend.update_table_cpi_u_index()
    backend.update_table_cpi_u_index()


@pytest.mark.integration
def test_backfill_cpi_u_index(backend):
    # AC4 one-shot historical backfill Dec-2015 -> now; idempotent (upsert).
    # Requires migration 053 applied. Guarded to a short window to keep the
    # integration run cheap while still exercising the multi-year loop.
    backend.backfill_cpi_u_index(start_year=2015)


@pytest.mark.integration
def test_update_table_asset(backend):
    backend.update_table_asset(sym_list=SYMBOL_LIST)


@pytest.mark.integration
def test_update_table_equity_profile(backend):
    backend.update_table_equity_profile(sym_list=SYMBOL_LIST)


@pytest.mark.integration
def test_update_table_reporting_period(backend):
    backend.update_table_reporting_period(sym_list=SYMBOL_LIST)


@pytest.mark.integration
def test_update_table_income_statement(backend):
    backend.update_table_income_statement(sym_list=SYMBOL_LIST)


@pytest.mark.integration
def test_update_table_balance_sheet_statement(backend):
    backend.update_table_balance_sheet_statement(sym_list=SYMBOL_LIST)


@pytest.mark.integration
def test_update_table_cash_flow_statement(backend):
    backend.update_table_cash_flow_statement(sym_list=SYMBOL_LIST)


@pytest.mark.integration
def test_update_table_earning(backend):
    backend.update_table_earning(sym_list=SYMBOL_LIST)


@pytest.mark.integration
def test_update_table_eod_price(backend):
    backend.update_table_eod_price(sym_list=SYMBOL_LIST)


@pytest.mark.integration
def test_update_table_all(backend):
    backend.update_table_all(sym_list=SYMBOL_LIST)


# ---------------------------------------------------------------------------
# SELF-214 W-1 daily-NAV checkpoint worker (impersonation). Live legs require
# migration 054 (pfin.nav_daily) applied AND the connecting role able to
# `SET ROLE authenticated` (see the Sec/DevOps flag). Forward-only.
# ---------------------------------------------------------------------------
@pytest.mark.integration
def test_nav_daily_enumerates_active_users(nav_worker):
    # Enumeration is a service_role read on pfin.account — no 054 dependency.
    user_ids = nav_worker.active_account_user_ids()
    assert isinstance(user_ids, list)


@pytest.mark.integration
def test_nav_daily_run(nav_worker):
    # Full W-1 run: impersonate each active-account tenant, compute
    # fn_compute_nav(current_date, true) under RLS, append to pfin.nav_daily.
    # Idempotent: run twice; second run must be a clean no-op (ON CONFLICT DO
    # NOTHING), not an error. Requires migration 054 applied.
    summary_1 = nav_worker.run()
    summary_2 = nav_worker.run()
    assert summary_1["failed"] == 0
    assert summary_2["failed"] == 0
    assert summary_1["total"] == summary_2["total"]


@pytest.mark.deployment
def test_update_table_all_search():
    logger.info("Perform Full Symbol Search. Update All records...")
    pfb = pfbe.PFinBackend()
    pfb.update_table_all()
