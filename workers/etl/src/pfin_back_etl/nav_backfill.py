"""
Project:       pfin-back-etl
Author:        Rich Mosko (mosko-fintech Backend)

Description:
    SELF-217 one-shot historical NAV backfill. Reads F/CTO's existing
    net-worth-tracking spreadsheet (exported to CSV) and lays down historical
    pfin.nav_daily checkpoints for the period BEFORE the SELF-214 forward-only
    cron (nav_daily.py / NavDailyWorker) existed for a given tenant.

    THIS IS NOT A RECURRING WORKER. There is no run_nav_backfill cron entry
    and none is planned — the entry point (run_nav_backfill.py) is invoked
    manually, once, by whoever holds the CSV. Every write is
    `on conflict (users_id, nav_date) do nothing`, so a second accidental
    invocation is a safe no-op rather than a corruption risk, but the script
    is still built dry-run-first (see run_nav_backfill.py) because a
    units/date mistake here becomes a PERMANENT row in an append-only,
    trigger-immutable table (054) — there is no UPDATE path to fix it after
    the fact, only a decision about what a wrong row costs a future consumer
    of the trend.

    SCOPE. This module owns two things:
      (1) parse_baseline_csv() / split_before_first_checkpoint() — pure CSV
          parsing + validation + boundary partitioning. No DB access. Used by
          BOTH the dry-run and the --commit path so the two can never
          disagree about which rows are in scope.
      (2) NavBackfillWorker — the DB-touching half: determining the target
          tenant's first recorded cron checkpoint, and the AC7 ratified
          write path.

    ONE TRANSACTION, ALL ROWS OR NONE (ADR-053 Decision 6, F/CTO-ratified
    2026-08-12): *"A partial backfill is the worst outcome — irreversible AND
    incomplete."* pfin.nav_daily blocks UPDATE and DELETE for EVERY role
    including service_role, by trigger (054) — there is no fixing a partial
    write after the fact, only a migration to remove what should never have
    landed. write_backfill() therefore opens exactly ONE connection and ONE
    transaction for the whole admissible set: one impersonation, one
    read-back, one write-tenant bind, then every row's INSERT in sequence —
    and a failure on ANY row raises, rolling back EVERY row, committed or
    not. ⚠ THIS WAS NOT THE ORIGINAL SHAPE. An earlier revision gave each row
    its OWN transaction (mirroring nav_daily.py's per-TENANT isolation,
    mistakenly carried over to per-ROW here) — Architect caught it in review:
    per-row transactions compound with the first-cron-checkpoint boundary
    below into an UNRECOVERABLE state, because a mid-run abort leaves the
    already-written rows as the tenant's new first_cron_checkpoint, which
    then REFUSES every remaining row on re-run as "already covered by the
    cron." The single-transaction shape dissolves this: either everything in
    `rows` lands, or nothing does, so there is never a suffix left stranded
    behind a boundary that thinks it's already covered.

    AC7 WRITE PATH (F/CTO-ratified 2026-08-12) — deliberately NOT nav_daily.py's
    shape, and the difference is the whole point of this file existing rather
    than reusing NavDailyWorker.compute_and_checkpoint_user() with a historical
    date swapped in:

        nav_daily.py sets `app.nav_computed_for` INSIDE the impersonation
        block, via `select set_config('app.nav_computed_for', auth.uid()::text,
        true)` — an expression evaluated SERVER-SIDE, while impersonation (b)
        is the sanctioned TenantBoundConnection binding admitting it (see
        connection.py _check_tenant_statement branch (4)).

        THIS module reads auth.uid() back into Python WHILE impersonating,
        THEN exits impersonation, THEN re-asserts that captured value as a
        bound LITERAL parameter to set_config — binding (a), not (b), ONCE
        per run rather than once per row. The value that ends up in
        `app.nav_computed_for` is therefore a value this code has already
        SEEN and can validate (see the None/mismatch guards in
        write_backfill), not an expression it trusts blindly at write time
        under a session whose role has already changed twice (authenticated ->
        pfin_etl -> service_role) since the read.

    FIRST-CRON-CHECKPOINT BOUNDARY. A row whose nav_date is ON OR AFTER the
    target tenant's earliest EXISTING pfin.nav_daily row (whether written by
    the forward cron or a prior backfill run) is OUT OF SCOPE and refused —
    this backfill exists to cover the period the forward-only cron never
    reached, not to contest or duplicate it. ON CONFLICT DO NOTHING would make
    a same-date collision a harmless no-op regardless, but refusing it here
    means the dry-run SURFACES the boundary instead of silently no-op'ing
    past it — a same-day gap the operator did not expect to see excluded is
    exactly the kind of thing a dry run exists to catch before --commit.

    AC5 COMPARAND (F/CTO-ratified 2026-08-12). Both the dry-run AND --commit
    paths report the imported BOUNDARY-MONTH NAV (the most recent admissible
    CSV row — the historical figure closest to where the live cron takes
    over) alongside this app's OWN computed NAV today (NavBackfillWorker.
    computed_nav_today — the exact fn_compute_nav(current_date, true) call
    the forward cron makes) and their delta, always in dollars. This is a
    continuity sanity check, not a reconciliation: the two dates are not the
    same, so a nonzero delta is expected and the numbers are reported for a
    HUMAN to judge, never reduced to a bare pass/fail. --commit additionally
    REQUIRES --ack-delta whenever |delta| >= $1,000 (the source's whole-$K
    quantization floor; no tighter automatic gate) — see run_nav_backfill.py.

    Lock anchors: Lock 13 mod #3 (TenantBoundConnection) · migration 054
    (pfin.nav_daily — consumed, not modified) · nav_daily.py (W-1
    impersonation model, from which impersonate() itself is reused verbatim).
"""

import csv
import datetime as dt
import logging
import re
from dataclasses import dataclass
from decimal import Decimal

import sqlalchemy as sqla

from pfin_back_etl import utils
from pfin_back_etl.connection import TenantBoundConnection

logger = logging.getLogger("pfin_etl")

# ADR-023 write role-of-record — identical to nav_daily.py's constant. The
# login role (`pfin_etl`) is NOINHERIT and holds no privileges on its own.
_SET_WRITE_ROLE = "set local role service_role"

# SELF-214 Sec joint-review B7 write-tenant binding GUC. PINNED CONTRACT:
# 054's BEFORE INSERT trigger reads this exact name — see nav_daily.py's
# _NAV_TENANT_GUC for the full rationale. Reproduced here rather than
# imported so this module's write path is legible on its own; the name
# itself is the shared contract, not the Python identifier.
_NAV_TENANT_GUC = "app.nav_computed_for"

# Same production statement SHAPE as nav_daily.py's _CHECKPOINT_INSERT, with
# nav_date as a bound parameter instead of `current_date` — the one axis this
# script varies from the forward cron. See 054 for the three-artifact
# invariant (constraint / grant / ON CONFLICT target) this statement pins.
_CHECKPOINT_INSERT = (
    "insert into pfin.nav_daily "
    "(users_id, nav_date, nav_value) "
    "values (:uid, :nav_date, :nav) "
    "on conflict (users_id, nav_date) do nothing"
)

# service_role's column-level grant on pfin.nav_daily is (users_id, nav_date)
# ONLY (054) — it can never read nav_value. This SELECT stays inside that
# grant: it names the same two arbiter columns nav_daily.py's SD-24 residual
# already documents as readable.
_FIRST_CHECKPOINT_QUERY = (
    "select min(nav_date) from pfin.nav_daily where users_id = :uid"
)

# AC5 comparand (F/CTO-ratified 2026-08-12). The SAME production statement
# nav_daily.py's forward cron issues inside its own impersonated read
# (current_date, active-only) — reused VERBATIM rather than re-derived, so
# the comparand this script reports can never silently diverge from what the
# live cron itself would compute. See NavBackfillWorker.computed_nav_today.
_NAV_COMPUTE_TODAY_QUERY = "select pfin.fn_compute_nav(current_date, true)"

_THOUSAND = Decimal(1000)
_MONEY_BODY_RE = re.compile(r"\d+(\.\d+)?")


class NavBackfillCsvError(ValueError):
    """Raised on a malformed / out-of-contract CSV row or header. Fail loud
    rather than silently skip, coerce, or default a row — a silently-dropped
    historical row understates the trend and a silently-coerced one is worse,
    and both are equally invisible in the dry-run summary if swallowed here."""


@dataclass(frozen=True)
class BackfillRow:
    """One parsed, in-range CSV row, ready to write. `nav_value_dollars` is
    ALWAYS in dollars (already scaled x1000 from the source $K column) —
    nothing downstream of parse_baseline_csv ever sees a $K value."""

    nav_date: dt.date
    nav_value_dollars: Decimal
    source_row_num: int  # 1-based CSV line number (header = line 1), for error messages only


def _parse_money_k(raw, *, row_num, column):
    """Parse a '$K'-formatted money string into a Decimal number of
    THOUSANDS (the caller scales to dollars). Accepts a leading '$', a
    thousands-comma, and EITHER a leading '-' or wrapping parens for negative
    (both forms appear elsewhere in this sheet, e.g. the ignored Expenses
    column) — the NAV column itself has shown neither in the sample F/CTO
    supplied, but this does not assume that holds for every future export.

    Uses Decimal throughout (never float): the source values are whole
    thousands, so x1000 is an EXACT integer number of dollars, and Decimal is
    what keeps it exact through the parse.
    """
    s = raw.strip()
    if not s:
        raise NavBackfillCsvError(
            f"row {row_num}: column {column!r} is empty — refusing to treat "
            f"a blank cell as zero or skip the row silently."
        )
    negative = False
    if s.startswith("(") and s.endswith(")"):
        negative = True
        s = s[1:-1].strip()
    if s.startswith("-"):
        negative = True
        s = s[1:].strip()
    if not s.startswith("$"):
        raise NavBackfillCsvError(
            f"row {row_num}: column {column!r} value {raw!r} does not start "
            f"with '$' after stripping sign/parens — refusing to guess at a "
            f"unit-less number."
        )
    s = s[1:].strip().replace(",", "")
    if not _MONEY_BODY_RE.fullmatch(s):
        raise NavBackfillCsvError(
            f"row {row_num}: column {column!r} value {raw!r} is not a plain "
            f"decimal number after stripping currency formatting."
        )
    value = Decimal(s)
    return -value if negative else value


def _parse_month_end_date(raw, *, row_num):
    """Parse an M/D/YYYY date and require it to be a real MONTH-END date —
    the whole premise of a monthly NAV series. A date that is not the last
    calendar day of its month is refused rather than silently accepted."""
    s = raw.strip()
    try:
        parsed = dt.datetime.strptime(s, "%m/%d/%Y").date()
    except ValueError as exc:
        raise NavBackfillCsvError(
            f"row {row_num}: date {raw!r} is not in M/D/YYYY format: {exc}"
        ) from exc
    next_day = parsed + dt.timedelta(days=1)
    if next_day.month == parsed.month:
        raise NavBackfillCsvError(
            f"row {row_num}: date {raw!r} is not a month-end date (the next "
            f"calendar day, {next_day.isoformat()}, is still the same "
            f"month) — refusing to treat a mid-month row as a checkpoint."
        )
    return parsed


def parse_baseline_csv(csv_path, start_date, end_date):
    """Parse F/CTO's baseline NAV CSV into BackfillRow objects, ascending by
    nav_date, restricted to [start_date, end_date] INCLUSIVE.

    Reads ONLY the unnamed leading date column and the 'NAV ($K)' column —
    every other column (the component breakdown, Expenses, CPI-U) is read by
    nothing here; SELF-217's scope is the two columns this function touches.
    The date column's header is looked up POSITIONALLY (fieldnames[0]) because
    it has no name in the source; every other column is looked up BY NAME so a
    reordering of the sheet's other columns cannot silently misalign this read.

    Duplicate nav_dates and rows outside [start_date, end_date] are handled
    deliberately, not incidentally: a duplicate date RAISES (there is no
    principled way to pick a winner from here), and an out-of-range row is
    silently excluded (rows outside the requested window are a normal,
    expected shape of a caller narrowing scope, not a data defect) — but
    duplicate-detection runs over the WHOLE file, before range-filtering, so a
    duplicate outside the window still raises rather than going unnoticed.

    Raises NavBackfillCsvError on anything this cannot confidently parse.
    """
    if start_date > end_date:
        raise NavBackfillCsvError(
            f"start_date {start_date} is after end_date {end_date}."
        )

    rows = []
    seen_dates = set()
    with open(csv_path, newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        fieldnames = reader.fieldnames or []
        if not fieldnames:
            raise NavBackfillCsvError(f"{csv_path}: no header row found.")
        date_col = fieldnames[0]
        nav_col = "NAV ($K)"
        if nav_col not in fieldnames:
            raise NavBackfillCsvError(
                f"{csv_path}: expected a {nav_col!r} column; header was "
                f"{fieldnames!r}."
            )
        for i, raw_row in enumerate(reader, start=2):  # header occupies line 1
            nav_date = _parse_month_end_date(raw_row[date_col], row_num=i)
            if nav_date in seen_dates:
                raise NavBackfillCsvError(
                    f"row {i}: duplicate nav_date {nav_date.isoformat()} — "
                    f"refusing to guess which row is authoritative."
                )
            seen_dates.add(nav_date)
            nav_value_k = _parse_money_k(raw_row[nav_col], row_num=i, column=nav_col)
            if nav_date < start_date or nav_date > end_date:
                continue
            rows.append(
                BackfillRow(
                    nav_date=nav_date,
                    nav_value_dollars=nav_value_k * _THOUSAND,
                    source_row_num=i,
                )
            )
    rows.sort(key=lambda r: r.nav_date)
    return rows


def split_before_first_checkpoint(rows, first_checkpoint_date):
    """Partition `rows` (ascending by nav_date) into (admissible, refused) by
    the target tenant's first recorded pfin.nav_daily checkpoint.

    `first_checkpoint_date` is None when the tenant has no checkpoint at all
    yet — nothing to refuse against, every row is admissible. Otherwise a row
    is admissible iff nav_date is STRICTLY BEFORE first_checkpoint_date; a row
    ON OR AFTER it is refused (see module docstring — SELF-217's scope is the
    period before the forward-only cron existed for this tenant).
    """
    if first_checkpoint_date is None:
        return list(rows), []
    admissible = [r for r in rows if r.nav_date < first_checkpoint_date]
    refused = [r for r in rows if r.nav_date >= first_checkpoint_date]
    return admissible, refused


class NavBackfillWorker:
    """SELF-217 one-shot historical NAV backfill — the DB-touching half.

    Construct once, call first_cron_checkpoint(users_id) to determine the
    refusal boundary, then run(users_id, admissible_rows, commit=...) to
    (optionally) write. Every write is its own transaction — one bad
    historical row must not abort the rest of the backfill, mirroring
    nav_daily.py's run() per-tenant isolation, here per-ROW instead of
    per-tenant (this worker backfills exactly one tenant per invocation).
    """

    def __init__(self, env_prefix="PFIN_"):
        # DB parameters ONLY (S12 precedent, utils.load_db_params) — this
        # worker makes no external API calls and needs no other credential.
        self._params = utils.load_db_params(env_prefix)
        self._db_url = utils.build_database_url(self._params)
        # System-mode engine for the cross-tenant-shaped-but-single-tenant-
        # filtered boundary read below. No per-tenant assertion registers in
        # system mode (exemption by construction — see connection.py); the
        # actual per-row WRITE always goes through a fresh for_tenant() TBC.
        self._system_tbc = TenantBoundConnection.system(self._db_url)

    # ------------------------------------------------------------------ #
    # Boundary read (service_role; column-level grant admits this).
    # ------------------------------------------------------------------ #
    def first_cron_checkpoint(self, users_id):
        """MIN(nav_date) already recorded for `users_id` in pfin.nav_daily —
        by the forward cron, an earlier backfill run, or both; this query
        cannot and does not distinguish the source. None if no checkpoint
        exists yet for this tenant.

        Runs AS service_role (system-mode TBC + explicit SET LOCAL ROLE): the
        column-level SELECT grant on (users_id, nav_date) — the same grant
        that admits the checkpoint INSERT's targeted ON CONFLICT (054) —
        is exactly what this MIN() needs and nothing more; nav_value stays
        unreadable to this role.
        """
        stmt = sqla.text(_FIRST_CHECKPOINT_QUERY)
        with self._system_tbc.engine.connect() as conn:
            with conn.begin():
                conn.execute(sqla.text(_SET_WRITE_ROLE))
                row = conn.execute(stmt, {"uid": str(users_id)}).fetchone()
        return row[0] if row and row[0] is not None else None

    # ------------------------------------------------------------------ #
    # AC5 comparand (F/CTO-ratified 2026-08-12) — read-only, ONE dedicated
    # transaction, deliberately SEPARATE from every backfill_row() write
    # transaction rather than folded into one of them.
    #
    # fn_compute_nav is a plain SELECT (head 'select', a member of
    # connection.py's _IMPERSONATION_ALLOWED_HEADS), so reading it inside
    # impersonate() composes with the B2 read-only fence with no conflict —
    # it is exactly the read nav_daily.py already performs, just without a
    # write following it in the same transaction. It gets its OWN
    # transaction anyway: tying a comparison read's lifetime to a write
    # transaction's boundaries buys nothing here and would make the
    # comparand unavailable in dry-run (no write transaction exists yet) —
    # the run() orchestrator below never has to reconcile this read against
    # its own error handling as a result.
    # ------------------------------------------------------------------ #
    def computed_nav_today(self, users_id):
        """This app's own live NAV for `users_id`, AS OF TODAY — the exact
        statement the forward cron issues (see nav_daily.py's `run()` /
        `_NAV_COMPUTE_TODAY_QUERY` above), reused verbatim so this comparand
        can never silently diverge from what the cron itself would compute.

        Returns whatever the driver returns for a NUMERIC scalar (Decimal) —
        never None: a tenant with no accounts yields a real 0, per
        fn_compute_nav's own contract, not a NULL this caller would have to
        special-case.
        """
        tbc = TenantBoundConnection.for_tenant(self._db_url, users_id)
        with tbc.engine.connect() as conn:
            with conn.begin():
                with tbc.impersonate(conn):
                    nav_value = conn.execute(
                        sqla.text(_NAV_COMPUTE_TODAY_QUERY)
                    ).scalar()
        return nav_value

    # ------------------------------------------------------------------ #
    # Whole-batch impersonated-read-back + privileged append, ONE txn
    # (ADR-053 Decision 6 — see module docstring for why this is not
    # per-row).
    # ------------------------------------------------------------------ #
    def write_backfill(self, users_id, rows):
        """Write ALL of `rows` for `users_id` in ONE transaction — all rows
        or none (ADR-053 Decision 6, F/CTO-ratified: "A partial backfill is
        the worst outcome — irreversible AND incomplete"). AC7 ratified write
        path, established ONCE and reused for every row rather than once per
        row (see module docstring for why this differs from nav_daily.py's
        inline `auth.uid()::text` shape):

            impersonate(users_id) -> read auth.uid() BACK FROM THE DB into
            Python -> exit impersonation -> set_config('app.nav_computed_for',
            <that DB-resolved value>, true) -> SET LOCAL ROLE service_role ->
            for each row: INSERT ... ON CONFLICT (users_id, nav_date) DO
            NOTHING -> commit (or roll back on any failure).

        A bad row RAISES and the WHOLE transaction rolls back — nothing
        partial is ever committed, and this function does not catch or
        isolate a per-row failure the way nav_daily.py's run() isolates a
        per-TENANT one; there is no unit smaller than "the whole backfill"
        that is safe to leave half-done here (see Decision 6: 054's
        immutability trigger means a partially-committed run can only be
        undone by a migration, and — compounding it — the rows that DID land
        would become the tenant's new first_cron_checkpoint, which would then
        REFUSE every remaining row on any retry as "already covered by the
        cron").

        Returns the total rowcount actually inserted (excludes any row
        already present via ON CONFLICT DO NOTHING) on full success. Empty
        `rows` is a no-op returning 0 without opening a connection.

        Raises RuntimeError if auth.uid() resolves to NULL or to a value
        other than the bound users_id while impersonating — either would mean
        the write-tenant binding this function is about to set is not
        trustworthy, and this is the one function whose entire job is to
        establish that it is. Raises (and rolls back) on any INSERT failure.
        """
        if not rows:
            return 0

        tbc = TenantBoundConnection.for_tenant(self._db_url, users_id)
        with tbc.engine.connect() as conn:
            with conn.begin():
                with tbc.impersonate(conn):
                    resolved_uid = conn.execute(sqla.text("select auth.uid()")).scalar()

                if resolved_uid is None:
                    raise RuntimeError(
                        f"auth.uid() resolved to NULL while impersonating "
                        f"users_id={users_id!r} — refusing to bind "
                        f"'{_NAV_TENANT_GUC}' to a NULL value."
                    )
                if str(resolved_uid) != str(users_id):
                    raise RuntimeError(
                        f"auth.uid() resolved to {resolved_uid!r} while "
                        f"impersonating users_id={users_id!r} — these must be "
                        f"identical. Refusing to bind '{_NAV_TENANT_GUC}' to a "
                        f"value that disagrees with the tenant this "
                        f"connection is bound to."
                    )

                # (post-teardown) bind the WRITE tenant from the value already
                # READ BACK, as a literal parameter — binding (a), not (b);
                # see connection.py's per-tenant assertion. Set ONCE; every
                # row's INSERT below reuses this same transaction-local GUC.
                conn.execute(
                    sqla.text(f"select set_config('{_NAV_TENANT_GUC}', :uid, true)"),
                    {"uid": str(resolved_uid)},
                )
                conn.execute(sqla.text(_SET_WRITE_ROLE))

                total_inserted = 0
                for row in rows:
                    result = conn.execute(
                        sqla.text(_CHECKPOINT_INSERT),
                        {
                            "uid": str(resolved_uid),
                            "nav_date": row.nav_date,
                            "nav": row.nav_value_dollars,
                        },
                    )
                    total_inserted += result.rowcount
                    logger.info(
                        f"nav backfill users_id={users_id} nav_date="
                        f"{row.nav_date} nav_value={row.nav_value_dollars} "
                        f"inserted={bool(result.rowcount)}"
                    )
                # Falling through here (no exception raised by any row above)
                # is what lets `with conn.begin():` commit on context exit —
                # any raise instead rolls back everything written so far in
                # this loop, which is the whole point (Decision 6).

        return total_inserted

    # ------------------------------------------------------------------ #
    # Orchestrate one tenant's admissible rows.
    # ------------------------------------------------------------------ #
    def run(self, users_id, rows, *, commit):
        """Backfill every row in `rows` (already filtered to admissible —
        see split_before_first_checkpoint) for `users_id`, ALL-OR-NOTHING via
        write_backfill() (ADR-053 Decision 6).

        commit=False performs NO writes and returns a summary of what WOULD
        happen (total only — the caller is expected to have already printed
        the dry-run summary from the rows themselves).

        commit=True calls write_backfill() and does NOT catch what it
        raises — deliberately, unlike nav_daily.py's run(), which isolates a
        per-TENANT failure because tenants are independent of each other.
        Here there is exactly one call, covering every row in `rows`; a
        failure means NOTHING was written, and swallowing that into a
        {"failed": N} summary would let a caller report "backfill complete"
        over a transaction that rolled back to zero. Let it propagate; the
        caller (run_nav_backfill.py) is responsible for a fail-loud exit.

        Returns {total, inserted} on success.
        """
        summary = {"total": len(rows), "inserted": 0}
        if not commit or not rows:
            return summary
        summary["inserted"] = self.write_backfill(users_id, rows)
        return summary
