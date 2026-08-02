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


@pytest.mark.deployment
def test_update_table_all_search():
    logger.info("Perform Full Symbol Search. Update All records...")
    pfb = pfbe.PFinBackend()
    pfb.update_table_all()
