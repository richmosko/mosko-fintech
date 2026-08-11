"""
Project:       pfin-back-etl
Author:        Rich Mosko

Description:
    Define the Classes used for creating the database connections
    and accessing APIs to populate the tables...

    Full disclosure... I am NOT a pofessional sotware developer, so
    this might be a bit janky. Please be kind.
"""

# library imports
import logging
from contextlib import contextmanager
from datetime import date, datetime, timezone, timedelta
import sqlalchemy as sqla
import sqlalchemy.ext.automap as sqla_automap
from sqlalchemy.dialects.postgresql import insert as pg_insert
import polars as pl
import fmpstab
from pfin_back_etl import utils
from pfin_back_etl.connection import TenantBoundConnection

logger = logging.getLogger("pfin_etl")

# ---------------------------------------------------------------------------
# CPI-U (BLS series CUUR0000SA0) ingest constants — SELF-230 (V1.1 Platform).
# Target table pfin.cpi_u_index (migration 053; Architect-owned, consumed here).
# ---------------------------------------------------------------------------
# BLS series id for CPI-U: All Urban Consumers, US city average, all items, NSA.
CPI_U_SERIES_ID = "CUUR0000SA0"
# Provenance string stored in pfin.cpi_u_index.source (matches the 053 DEFAULT).
CPI_U_SOURCE = "BLS_CUUR0000SA0"
# AC4 historical-backfill anchor: rows must exist for every month Dec-2015 -> now.
CPI_U_BASE_YEAR = 2015
# Nightly rolling window (years, inclusive of the current year). BLS revises only
# recent prints, so a short trailing window catches revisions cheaply; the deep
# history is laid down once by backfill_cpi_u_index() (the AC4 one-shot).
CPI_U_NIGHTLY_WINDOW_YEARS = 2
# 063's published_value_raw CHECK bounds the token at 64 chars. Carried here so
# the worker fails-closed by truncating rather than aborting the whole append on
# a DB CHECK; the observed real token is the single character '-'.
CPI_U_RAW_TOKEN_MAX = 64


class CpiReconciliationError(RuntimeError):
    """
    Raised when a CPI-U fetch cannot be fully accounted for across its two
    destination tables. See PFinBackend._prepare_cpi_u_frames.

    ⚠ THIS IS A FAIL-LOUD GATE, NOT A WARNING, and the reason is specific.
    `pfin.cpi_u_nonpublication` (063 / ADR-049 Decision 1) has exactly one
    reachable failure mode: silence. An EMPTY non-publication record is
    INDISTINGUISHABLE from a clean run at every layer — no constraint, no test
    and no query can tell "BLS published every period" from "something upstream
    ate the valueless rows again". Degrading this to a log line restores that
    indistinguishability, which is precisely the defect the table exists to
    close. A run that cannot account for every period it fetched must not write.
    """


# ---------------------------------------------------------------------------
# ROLE ASSUMPTION — BACKLOG §7.6 S17. ADR-023 write role-of-record + the
# ADR-023 amendment's read role-of-record. Sec-ruled 2026-08-09 (D-A option c).
# ---------------------------------------------------------------------------
# The ETL LOGS IN as `pfin_etl`, a NOINHERIT role that `055` deliberately grants
# NO direct table privileges. A NOINHERIT session holds NOTHING until an
# explicit SET ROLE, so EVERY statement — reads included — must assume a role or
# fail 42501. `nav_daily.py` already did this; `SBaseConn` did not, which is S17.
#
# ⚠ READS ARE `authenticated`, NOT `service_role`, AND THE REASON IS NOT
# COSMETIC. [ADR-011] Decision 1 clause (b) says *WRITES* execute under
# `service_role` and is SILENT on reads; reading it as "the privileged context
# runs as service_role" is the widening that produced the hazard. Two of the
# three tables this worker touches are NOT global reference data:
#   • pfin.asset    (016) is HYBRID — users_id nullable; non-NULL rows are a
#                   user's private assets.
#   • pfin.eod_price(019) is asset-anchored and carries per-user
#                   `manual_valuation` rows — user-entered money figures.
# Under `service_role` a plain SELECT returns EVERY tenant's private rows, and
# the read is the smaller half: `update_table_df` bulk-UPDATEs from that frame,
# so a refresh could silently overwrite another tenant's row. Widening the read
# role to fix a permissions defect would have manufactured a cross-tenant WRITE
# hazard — fixing a fail-closed bug by failing open, one layer down.
# `authenticated` with no JWT is not degraded: it resolves to exactly the global
# partition this worker wants, fail-closed, with no SQL change.
_READ_ROLE = "authenticated"
_WRITE_ROLE = "service_role"

# ⚠ THIS ALLOWLIST IS ALSO THE INJECTION FENCE. `SET ROLE` takes an identifier,
# not a parameter, so it CANNOT be bound — the role name is interpolated. Every
# value reaching that interpolation must therefore come from this frozen set.
# Do not add a caller-supplied fallback, and do not relax it to "any role the
# login is a member of": both re-open the interpolation.
_ROLE_ALLOWLIST = frozenset({_READ_ROLE, _WRITE_ROLE})


def staging_seed_sql(staging_name, target_schema, target_name):
    """The staging-table seed statement — S17 requirement (a′).

    ⚠ MODULE-LEVEL AND EXPORTED SO THE REGRESSION TESTS EXERCISE THE REAL
    STATEMENT. Kept inline, the tests could only re-type the SQL and assert on
    their own copy — pinning the PATTERN while a refactor of this function went
    unobserved. A detector that cannot see the code it guards is the failure
    this whole entry exists to stop; do not inline it again.

    `WHERE false` seeds the target's column SHAPE and none of its rows. Three
    defects turn on that clause — an unbounded cross-tenant read inside the
    write path, a full copy discarded immediately, and (measured) an ambiguous
    `UPDATE … FROM` join that silently kept the OLD values while self-updating
    every untouched row. See update_table_df's docstring.
    """
    return (
        f"CREATE TEMP TABLE {staging_name} AS\n"
        f"SELECT * FROM {target_schema}.{target_name}\n"
        f"WHERE false;"
    )


class PFinFMP(fmpstab.FMPStab):
    """
    Personal Finance Fiancial Modeling Prep Connection
    Child class of FMPStab which adds some fetching functions specific to the
    PFin project.
    """

    def __init__(self, api_key: str) -> None:
        max_calls_per_minute = 280
        config_file = None
        base_url = None
        logger = None
        log_enabled = False
        super().__init__(
            api_key, max_calls_per_minute, config_file, base_url, logger, log_enabled
        )

    def get_screened_stocks(self, min_mkt_cap, result_limit):
        """
        Run FMP company-screener API to get list of stocks to add to assets...

        returns:
            df_slist:      polars dataframe of screened stocks
        """
        df_slist = self.fetch_fmp_df(
            self.company_screener,
            marketCapMoreThan=min_mkt_cap,
            country="US",
            isEtf=False,
            isFund=False,
            isActivelyTrading=True,
            limit=result_limit,
        )
        return df_slist

    def fetch_fmp_list_df(self, fmp_func, key, **kwargs):
        """
        Calls self.fetch_fmp_df multiple times for each item in key(list).
        Concatenates each result into a single polars dataframe

        returns: df_fmp (polars dataframe of query results)
        """
        key_list = kwargs.pop(key)
        if not isinstance(key_list, list):
            key_list = [key_list]

        df_fmp = pl.DataFrame()
        for item in key_list:
            kwargs[key] = item
            df_tmp = self.fetch_fmp_df(fmp_func, **kwargs)
            if df_fmp.is_empty():
                df_fmp = df_tmp
            elif not df_tmp.is_empty():
                df_fmp = pl.concat([df_fmp, df_tmp], how="vertical_relaxed")
        return df_fmp

    def fetch_fmp_df(self, fmp_func, **kwargs):
        """
        fetch data from the Financial Modeling Prep API using the access function
        fmp_func(). specific arguments to that function are passed through kwargs.

        returns: df (polars dataframe of query results)
        """
        fmp_api_name = fmp_func.__name__
        logger.info(f"FMP ({fmp_api_name}): Fetching {kwargs} ...")
        rsp = fmp_func(**kwargs)
        df = pl.DataFrame(rsp.json())
        df = df.rename(utils.col_to_snake(df.columns))
        logger.info(f"FMP ({fmp_api_name}): Got {len(df)} row(s)")
        return df


class SBaseConn:
    """
    SupaBase Connection
    Setup and maintain a connection to the SupaBase postgreSQL database.
    Query the connection to discover the relavant tables, and create
    methods to query, insert, and update data.
    """

    def __init__(self, env_prefix, schema_list):
        """
        Class initializer...
        """
        self._env_prefix = env_prefix
        self._schema_list = schema_list
        self._params = utils.load_env_variables(env_prefix)
        (self.engine, self.metadata, self.base) = self._sbase_setup()

    @contextmanager
    def _role(self, executor, role):
        """Assume `role` transaction-locally for the duration of the block.

        THE ROLE ARGUMENT IS REQUIRED AND HAS NO DEFAULT — DELIBERATELY (Sec,
        D-A). A default would make the privileged choice invisible at the call
        site, which is the same defect as assuming privilege at the engine
        level wearing a different costume: the reader of a call site must be
        able to see which role it runs under without navigating anywhere.

        ⚠ WHY NOT AT THE ENGINE LEVEL. Setting the role on the engine (a
        connect/execute listener) was considered and VETOED on two independent
        grounds: it confers ambient privilege for the engine's lifetime,
        defeating the whole point of `055`'s NOINHERIT choice; and it would
        alter `TenantBoundConnection`'s semantics, which ADR-011 Decision 4
        names BY NAME as the code-layer fence of the Lock 13 privileged-context
        surface class. Session-level `SET ROLE` is the same veto at connection
        scope, and worse in one way: SQLAlchemy pools connections with
        `pool_reset_on_return='rollback'`, which does NOT reset role, so a
        missed teardown poisons the pool for whatever borrows it next.

        ⚠ TRANSACTION-LOCAL MEANS EXACTLY THAT. `SET LOCAL ROLE` is cleared by
        COMMIT and by ROLLBACK (measured). A caller that commits in the middle
        of a block silently loses the role, and every statement after that
        point runs privilege-less and fails 42501 PART-WAY THROUGH — after the
        role was correctly assumed, which is why it reviews as correct. Callers
        must not commit inside this block.

        args:    executor — an open Session OR Connection. Named for what it
                 must DO (execute) rather than what it usually IS: reflection
                 passes a Connection while the data methods pass a Session, and
                 a `session` parameter misdescribed half its call sites.
                 role — allowlisted.
        raises:  ValueError if `role` is not in _ROLE_ALLOWLIST.
        """
        if role not in _ROLE_ALLOWLIST:
            raise ValueError(
                f"role {role!r} is not allowlisted. Permitted: "
                f"{sorted(_ROLE_ALLOWLIST)}. SET ROLE takes an identifier and "
                f"cannot be parameterised, so this allowlist is the injection "
                f"fence as well as the privilege policy — refusing to "
                f"interpolate an unvetted value."
            )
        executor.execute(sqla.text(f"set local role {role}"))
        try:
            yield executor
        finally:
            # N1 teardown shape, copied from connection.impersonate(): if the
            # block raised a DB error the transaction is ABORTED, and `reset
            # role` would raise InFailedSqlTransaction, REPLACING the original
            # exception exactly where diagnosis matters most. Swallow and log;
            # the original propagates. Safe because SET LOCAL is transaction-
            # scoped and auto-clears at COMMIT/ROLLBACK regardless.
            try:
                executor.execute(sqla.text("reset role"))
            except Exception as exc_reset:
                logger.warning(
                    f"reset role failed during teardown (transaction likely "
                    f"already aborted; SET LOCAL clears at COMMIT/ROLLBACK "
                    f"regardless): {exc_reset}"
                )

    def fetch_table_df(self, table):
        """
        Fetch what's already in {table}
        Args:    table (sqlalchemy ORM table object)
        Returns: df_tab (pandas dataframe of table entries)
        """
        tab = table.__table__
        stmt = sqla.select(tab)
        with sqla.orm.Session(self.engine) as session:
            with self._role(session, _READ_ROLE):
                df_tab = pl.read_database(stmt, session)
        # print(f"self.fetch_table_df():\n {df_tab}")
        return df_tab

    def insert_table_df(self, tab_sbase, df_insert):
        """
        Insert new row entries into table tab_sbase from
        polars dataframe df_insert
        """
        with sqla.orm.Session(self.engine) as session:
            s_name = tab_sbase.__table__.schema
            t_name = tab_sbase.__table__.name
            logger.info(
                f"Inserting {len(df_insert)} new entries in {s_name}.{t_name}..."
            )
            ldict_insert = df_insert.to_dicts()
            if ldict_insert:
                with self._role(session, _WRITE_ROLE):
                    stmt = sqla.insert(tab_sbase)
                    session.execute(stmt, ldict_insert)
                # COMMIT IS OUTSIDE THE ROLE BLOCK, DELIBERATELY. SET LOCAL
                # ROLE is cleared by COMMIT, so committing inside would tear
                # the role down mid-block and leave the teardown `reset role`
                # running in a fresh, privilege-less transaction.
                session.commit()

    def update_table_df(self, tab_sbase, key_list, df_update):
        """
        Update existing row entries in table tab_sbase from
        polars dataframe df_update. This will create a temp
        table matching tab_sbase, and insert the rows into the
        temp table. It then updates the data locally in the database
        which executes much faster than a sqlalchemy update command.

        ⚠ THE WHOLE PATH IS ONE TRANSACTION UNDER ONE ROLE ASSUMPTION, and it
        must stay that way. `_staging_update` used to COMMIT MID-FLIGHT, and
        COMMIT clears `SET LOCAL ROLE` (measured) — so a role assumed here was
        silently dropped part-way through and every later statement ran
        privilege-less, failing AFTER the role was correctly assumed. Do not
        reintroduce a commit inside the helper.

        Two options were rejected rather than overlooked. Re-assuming the role
        after an internal commit leaves a LIVE WINDOW in which any
        later-inserted statement runs privilege-less — S17's own shape re-armed
        inside the function fixing S17; it fixes the instance, not the class.
        Session-level `SET ROLE` survives commits but confers ambient privilege
        for the connection's lifetime, and SQLAlchemy pools connections with
        `pool_reset_on_return='rollback'`, which does NOT reset role — so a
        missed teardown hands a privileged role to the next checkout.

        Atomicity is a deliberate gain, not a tolerated side effect: a bulk
        update of price reference data that fails part-way must not leave
        durable partial work, because the next night's run derives its diff
        from whatever state it finds. Bound: this holds a transaction open for
        the length of the bulk update — negligible at V1 scale, revisit only if
        these tables grow enough for lock duration to matter.
        """
        with sqla.orm.Session(self.engine) as session:
            s_name = tab_sbase.__table__.schema
            t_name = tab_sbase.__table__.name
            logger.info(
                f"Updating {len(df_update)} existing entries in {s_name}.{t_name}..."
            )
            ldict_update = df_update.to_dicts()
            if ldict_update:
                with self._role(session, _WRITE_ROLE):
                    self._staging_update(session, tab_sbase, key_list, ldict_update)
                session.commit()  # outside the role block — COMMIT clears SET LOCAL

    def upsert_table_df(self, tab_sbase, index_elements, df_upsert):
        """
        UPSERT rows from polars dataframe df_upsert into tab_sbase using a native
        Postgres INSERT ... ON CONFLICT (index_elements) DO UPDATE. This is the
        single-statement upsert path for global-reference tables whose natural key
        IS the conflict target (e.g. pfin.cpi_u_index keyed on cpi_period) — new
        rows INSERT, existing rows UPDATE in place. Idempotent: re-running with the
        same data is a no-op-equivalent (same values re-written).

        Distinct from insert_table_df + update_table_df (the two-step
        isolate-new / staging-update path used by surrogate-key tables like
        pfin.cpi where the conflict key is not the row identity). Prefer this when
        the table's PRIMARY KEY / unique key is exactly the upsert key.

        args:
            tab_sbase:       sqlalchemy ORM table object (the target)
            index_elements:  list of column names forming the conflict target
                             (must be a PK / unique constraint on tab_sbase)
            df_upsert:       polars dataframe of rows to upsert

        Columns present in df_upsert are written on INSERT; columns absent from
        df_upsert fall back to their DB DEFAULT on INSERT. On CONFLICT, every
        non-key column of the target is refreshed from the proposed row (EXCLUDED),
        so a column with a DEFAULT now() (e.g. ingested_at) is re-stamped on each
        revision-update even when it is not carried in df_upsert.
        """
        if not isinstance(index_elements, list):
            index_elements = [index_elements]

        ldict_upsert = df_upsert.to_dicts()
        if not ldict_upsert:
            return

        tab = tab_sbase.__table__
        with sqla.orm.Session(self.engine) as session:
            logger.info(
                f"Upserting {len(ldict_upsert)} entries into "
                f"{tab.schema}.{tab.name} on conflict {index_elements}..."
            )
            stmt = pg_insert(tab).values(ldict_upsert)
            update_cols = {
                col.name: stmt.excluded[col.name]
                for col in tab.columns
                if col.name not in index_elements
            }
            stmt = stmt.on_conflict_do_update(
                index_elements=index_elements, set_=update_cols
            )
            # ON CONFLICT DO UPDATE needs the arbiter read as well as the
            # write, which is why `053` grants service_role SELECT alongside
            # INSERT + UPDATE. Do not tighten that grant to write-only.
            with self._role(session, _WRITE_ROLE):
                session.execute(stmt)
            session.commit()  # outside the role block — COMMIT clears SET LOCAL

    def append_table_df(self, tab_sbase, index_elements, df_append):
        """
        APPEND rows from polars dataframe df_append into an APPEND-ONLY table
        using INSERT ... ON CONFLICT (index_elements) DO NOTHING. First
        observation wins; a re-run of the same fetch is a no-op.

        ⚠ `DO NOTHING` IS A STANDING REQUIREMENT OF THE TARGET, NOT A STYLE
        CHOICE, and this helper exists so it cannot be forgotten at a call site.
        `pfin.cpi_u_nonpublication` (063) is IMMUTABLE + APPEND-ONLY: its BEFORE
        UPDATE / DELETE triggers raise, and its header states in as many words
        that the ingest MUST append with `on conflict (cpi_period) do nothing`
        because `do update` reaches that fence and fails loud. Reaching for
        upsert_table_df() on such a table is the mistake this method prevents —
        that one writes `on_conflict_do_update` unconditionally.
        Also why: `observed_at` records when WE FIRST OBSERVED the
        non-publication. DO NOTHING preserves the first observation across a
        monthly re-fetch of the same window; DO UPDATE would re-stamp it from
        EXCLUDED and quietly convert an audit trail into a "last run" clock.

        Bounded re-run cost: without a conflict target this would accumulate one
        duplicate row per run, forever — which is why index_elements is REQUIRED
        rather than optional.

        args:
            tab_sbase:       sqlalchemy ORM table object (the target)
            index_elements:  list of column names forming the conflict target
                             (must be a PK / unique constraint on tab_sbase)
            df_append:       polars dataframe of rows to append
        """
        if not isinstance(index_elements, list):
            index_elements = [index_elements]

        ldict_append = df_append.to_dicts()
        if not ldict_append:
            return

        tab = tab_sbase.__table__
        with sqla.orm.Session(self.engine) as session:
            logger.info(
                f"Appending {len(ldict_append)} entries into "
                f"{tab.schema}.{tab.name} on conflict {index_elements} "
                "do nothing..."
            )
            stmt = pg_insert(tab).values(ldict_append)
            stmt = stmt.on_conflict_do_nothing(index_elements=index_elements)
            # DO NOTHING still needs the arbiter READ, which is why `063` grants
            # service_role SELECT alongside INSERT. Do not tighten to
            # insert-only — the append would start failing on every re-run.
            with self._role(session, _WRITE_ROLE):
                session.execute(stmt)
            session.commit()  # outside the role block — COMMIT clears SET LOCAL

    def print_schema_info(self):
        """
        Print the schema and table names reflected from supabase
        TBD:: Need to fill this out by polling all the table names per schema
        """
        logger.info("Iterating through automapped Classes:")
        schema_list = self.base.by_module.keys()
        for schema in schema_list:
            logger.info("==== " * 8)
            logger.info(f"SCHEMA: {schema}")
            tab_list = self.base.by_module[schema].keys()
            for tab in tab_list:
                logger.info(f"    TABLE: {tab}")

    def get_reflected_table(self, schema_name, table_name):
        """
        return the reflected table object based on a schema name
        and table name...

        returns:
            tab:           sqlalchemy ORM Table object
        """
        tab_collection = self.base.by_module[schema_name]
        tab = tab_collection[table_name]
        return tab

    def get_column_dict(self, tab_obj):
        """
        Get a list of the column names in a table

        args:
            tab_obj:       sqlalchemy ORM Table object

        returns:
            keys:          dictionary of column names -> data types
        """
        c_dict = {}
        columns = tab_obj.__table__.columns
        logger.info(f"Table Name: {tab_obj.__table__.schema}.{tab_obj.__table__.name}")
        for column in columns:
            c_dict[column.name] = column.type
            logger.info(
                f"  Column Name: {column.name}, Type: {column.type}[{type(column.type)}]"
            )
        return c_dict

    def _sbase_setup(self):
        """
        Sets up the sqlalchemy engine connection and reflects the database
        structure to self.base object for referencing the database table data

        returns:
            engine:        The connection engine
            metadata:      The database table metadata to define the fields
            base:          The base instance containing the reflected tables
        """
        # SBASE:: Try to establish a connection to the postgresql database.
        # Single source of the connection string (utils.build_database_url) so the
        # ETL system engine and the SELF-214 per-tenant NAV worker are identical.
        DATABASE_URL = utils.build_database_url(self._params)

        # 1. Construct the SQLAlchemy connection string and setup the engine.
        #    Lock 13 mod #3: the engine MUST be created through
        #    TenantBoundConnection — the single sanctioned engine factory. The
        #    ETL writes global market-reference tables (no users_id column), so
        #    this is the SYSTEM-mode (service-context) construction path. A bare
        #    sqla.create_engine() here would be a TBC CI-fence violation.
        logger.info("Setting up sqlalchemy engine (via TenantBoundConnection)...")
        engine = TenantBoundConnection.system(DATABASE_URL).engine

        # 2. Create the Automap Base, linking to your engine's metadata
        logger.info("Initializing sqlalchemy MetaData object...")
        metadata = sqla.MetaData()
        base = sqla_automap.automap_base(metadata=metadata)

        # 3 + 4. Reflect, then prepare the automap base — BOTH INSIDE ONE ROLE
        #        BLOCK, ON ONE CONNECTION.
        #
        # ⚠ THIS IS THE STATEMENT THAT RUNS FIRST, AND THE S17 FIX MISSED IT.
        # Every `_role()` call site was a DATA method; reflection sits in
        # `__init__`, ahead of all of them, so under the production login
        # `PFinBackend()` died here before any data path was reached —
        # `permission denied for schema pfin`, found by the acceptance run.
        # A fix covering every statement except the first one covers nothing.
        #
        # THE FAULT IS SCHEMA `USAGE`, ONE GATE EARLIER THAN THE TABLE
        # PRIVILEGES S17 WAS FILED AGAINST. Measured:
        #     has_schema_privilege('pfin_etl','pfin','USAGE')      -> f
        #     has_schema_privilege('authenticated','pfin','USAGE') -> t
        #     has_schema_privilege('service_role','pfin','USAGE')  -> t
        # which is why the operator's RED read "permission denied for SCHEMA
        # pfin" rather than naming a table.
        #
        # WHY `authenticated`, NOT `service_role`. Reflection is a READ and the
        # ADR-023 amendment's read role-of-record is `authenticated`. The
        # amendment's partition-class rule is SILENT here — reflection reads no
        # tenant rows at all, only catalog shape — and where the rule is silent
        # the least-privileged sufficient role is the correct default, which is
        # the same reasoning that produced the reads veto. `service_role` would
        # confer write-tier context for a metadata read that does not need it.
        #
        # ⚠ THE RISK THAT MADE THIS WORTH MEASURING RATHER THAN REASONING: if
        # the less-privileged role saw FEWER objects, reflection would silently
        # produce a PARTIAL base, automap would omit tables, and the failure
        # would surface later, elsewhere, and confusingly. MEASURED —
        # reflecting `auth` + `pfin` returns an IDENTICAL 50-table set under
        # `postgres`, `authenticated` and `service_role`; zero missing, zero
        # extra. The dialect reflects from `pg_catalog`, which is not
        # row-filtered by privilege; only schema USAGE gates it. So
        # `authenticated` is both sufficient and least-privileged. RE-MEASURE
        # if the dialect changes — do not re-derive it from the role names.
        with engine.connect() as conn:
            with conn.begin():
                with self._role(conn, _READ_ROLE):
                    logger.info("Reflect database tables to MetaData object...")
                    for sch in self._schema_list:
                        # ONCE per schema. This was called TWICE in the same
                        # loop body — every schema reflected twice for
                        # identical results. Harmless but real, and now doubly
                        # so, since each round trip sits inside the role block.
                        metadata.reflect(bind=conn, schema=sch)

                    # The two name_for_*_relationship hooks are the BACKLOG
                    # §7.6 S13 collision guard: automap names a generated
                    # relationship after the referred table, which collides
                    # with a same-named column and RAISES here
                    # (pfin.user_taxonomy.tax_character + FK ->
                    # pfin.tax_character). The guard renames the RELATIONSHIP,
                    # never the column — see the block comment in utils.py.
                    logger.info("Automapping DB tables to base object...")
                    base.prepare(
                        autoload_with=conn,
                        modulename_for_table=utils.sqla_modulename_for_table,
                        name_for_scalar_relationship=(
                            utils.sqla_name_for_scalar_relationship
                        ),
                        name_for_collection_relationship=(
                            utils.sqla_name_for_collection_relationship
                        ),
                    )
        return (engine, metadata, base)

    def _staging_update(self, session, tab_sbase, key_list, ldict_update):
        """
        Create a temp staging table, and insert data into table. Updates from temp
        table to the actual target table internally in the database...

        args:
            session:       The active sqlalchemy session
            tab_sbase:     The sqlalchemy table instance to target
            key_list:      list of columns that are unique to key off of
            ldict_update:  list of dictionaries (rows) to update

        returns:
            None
        """
        if not isinstance(key_list, list):
            key_list = [key_list]

        # (a) NO COMMIT HERE. `SET LOCAL ROLE` is cleared by COMMIT (measured),
        # so a mid-flight commit silently drops the write role and every
        # statement after it runs privilege-less — failing AFTER the role was
        # correctly assumed, which is why it would review as correct and fail
        # at night. `DISCARD TEMPORARY` is legal inside a transaction
        # (measured), so the whole path now runs in ONE transaction under ONE
        # role assumption. Atomicity is a deliberate gain, not a side effect: a
        # bulk update of price data that fails part-way must not leave durable
        # partial work for the next night's run to derive a diff from.
        session.execute(sqla.text("DISCARD TEMPORARY"))

        tab_stag = tab_sbase.__table__.to_metadata(
            self.metadata,
            name="table_staging",
            schema=None,
            referred_schema_fn=utils.sqla_resolve_referred_schema,
        )
        tab_stag._prefixes.append("TEMP")
        tab_stag.constraints = set()
        tab_stag.foreign_keys = set()

        tg_sch_name = tab_sbase.__table__.schema
        tg_name = tab_sbase.__table__.name
        st_name = tab_stag.name
        # (a′) `WHERE false` — SEED THE SHAPE, NOT THE ROWS. THREE defects in
        # one line, and the third is the one that makes this a repair rather
        # than a hardening:
        #
        #  1. SECURITY. This is an unbounded whole-table read INSIDE the write
        #     path, independent of fetch_table_df. Under the write role it
        #     copies EVERY TENANT'S ROWS into staging — reintroducing, inside
        #     the write path, exactly the over-read the read/write split
        #     exists to prevent. pfin.eod_price carries per-user
        #     `manual_valuation` rows, so this is user-entered money.
        #  2. WASTE. A full copy of the target, discarded immediately.
        #  3. ⚠ CORRECTNESS — MEASURED, and it means this path did not work.
        #     Seeded with the full copy AND then the update rows, every updated
        #     key matches TWO staging rows. Postgres documents `UPDATE … FROM`
        #     with a multi-row match as UNPREDICTABLE which row is used, and
        #     reproduced in a rolled-back transaction it took the STALE one:
        #     the new values were silently discarded and the row kept its old
        #     value, while every untouched row was self-updated anyway (firing
        #     its `updated_at` and BEFORE UPDATE triggers). `UPDATE 3` where 2
        #     were intended, and neither intended change landed.
        #
        # Seeding empty removes all three: the join becomes unambiguous, no
        # untouched row is written, and no other tenant's row is ever read.
        session.execute(sqla.text(staging_seed_sql(st_name, tg_sch_name, tg_name)))

        stmt = sqla.insert(tab_stag)
        session.execute(stmt, ldict_update)

        # SQL statement to update from staging table
        ud_stmt = f"""UPDATE {tg_sch_name}.{tg_name} as TG"""
        ud_stmt += """\nSET"""
        set_list = []
        for column in tab_sbase.__table__.columns:
            if column.name not in key_list:
                set_list.append(f"""\n{column.name} = ST.{column.name}""")
        ud_stmt += ", ".join(set_list)
        ud_stmt += f"""\nFROM {st_name} as ST"""
        ud_stmt += """\nWHERE """
        cond_list = []
        for key_col in key_list:
            cond_list.append(f"""TG.{key_col}=ST.{key_col}""")
        ud_stmt += " AND ".join(cond_list)
        ud_stmt += ";"
        stmt = sqla.text(ud_stmt)
        session.execute(stmt)
        # (a) The caller commits, ONCE, outside the role block. Committing here
        # would end the transaction mid-helper and tear down the assumed role.
        self.metadata.remove(tab_stag)

    def _calc_common_cols_df(self, tab_sbase, df_sbase, df_api):
        """
        Find the common columns to populate in the DB table.
        args:
            tab_sbase:     sqlachemy ORM table object
            df_sbase:      existing table entries as polars dataframe
            df_api:        data from API source as polars dataframe
        returns:
            common_cols:   common columns detected
            df_old:        df_sbase, reformated with common_cols
            df_new:        df_api, reformated with common_cols
        """
        sb_cols = tab_sbase.__table__.columns.keys()
        api_cols = set(list(df_api.columns))
        common_cols = [item for item in sb_cols if item in api_cols]
        # df_new = pd.DataFrame(columns=common_cols) # initialze empty DF
        # df_old = pd.DataFrame(columns=common_cols) # initialze empty DF
        df_new = df_api.select(common_cols)
        df_old = df_sbase.select(common_cols)
        return (common_cols, df_old, df_new)

    def _isolate_new_rows_df(self, on_key, df_old, df_new):
        """
        Compare the existing and new pandas dataframs, and isolate which
        rows are new and should be inserted instead of updated
        args:
            on_key:        list of column names to use for key matching
            df_old:        existing dataframe
            df_new:        dataframe with new and updated entries
        returns:
            df_mrg:        polars dataframe with only the new entries to insert
                           (can be empty dataframe)
        """
        if len(df_old) == 0:
            # special handling of empty table... as data types were not inferred
            # insert all rows
            return df_new

        df_mrg = df_new.join(df_old, on=on_key, how="anti")
        df_mrg = utils.apply_schema_df(df_old, df_mrg)
        return df_mrg

    def _isolate_updated_rows_df(self, on_key, df_old, df_new):
        """
        Compare the existing and new pandas dataframs, and isolate which
        rows are overlapping and should be updated
        args:
            on_key:        list of column names to use for key matching
            df_old:        existing dataframe
            df_new:        dataframe with new and updated entries
        returns:
            df_mrg:        polars dataframe with only the updated entries to
                           update (can be empty dataframe)
        """
        if len(df_old) == 0:
            # special handling of empty table... as data types were not inferred
            # update no rows
            return df_old

        df_mrg = df_new.join(df_old, on=on_key, how="semi")
        df_mrg = utils.apply_schema_df(df_old, df_mrg)
        return df_mrg

    def _fetch_sbase_ldict(self, stmt):
        """
        Run a select query (stmt) on the database.

        args:
            stmt:          sqlalchemy (select) statement to execute

        returns:
            ldict:         List of dictionaries, one dict per row
        """
        with sqla.orm.Session(self.engine) as session:
            with self._role(session, _READ_ROLE):
                result = session.execute(stmt)
                ldict = []
                for row in result:
                    row_as_dict = row._asdict()
                    ldict.append(row_as_dict)
        return ldict


class PFinBackend(SBaseConn):
    """
    Personal Finance Backend
    Setup all database and API connections for the Personal Finance
    Backend ETL (Extract, Transfer, and Load) functionality. Define
    methods to update the tables in the (postgres) database,
    pulling from the various API data sources.
    """

    def __init__(self):
        env_prefix = "PFIN_"
        schema_list = ["auth", "pfin"]
        super().__init__(env_prefix, schema_list)
        self._fmp_client = None
        self._stock_screener_min_mkt_cap = 1000000000
        self._stock_screener_result_limit = 5000
        self._tmp_date_fut = "4000-12-31"
        self._tmp_year_fut = 4000
        self._tmp_period_fut = "NA"

    @property
    def fmp_client(self):
        """The FMP client, constructed on FIRST USE — S12.

        It used to be built in __init__, which made `FMP_API_KEY` a hard
        requirement of PFinBackend ITSELF: a CPI-only container had to carry a
        credential it never uses, and a machine without one could not construct
        the object at all. That is the same least-privilege objection S12 makes
        against the NAV cron, on the worker that actually does the CPI-U work.

        Lazy construction moves the requirement to the FMP call sites, where
        `require_api_key` raises with the operation named. The CPI-U path never
        touches this property, so it never needs the key.
        """
        if self._fmp_client is None:
            self._fmp_client = PFinFMP(
                api_key=utils.require_api_key(self._params, "FMP_API_KEY")
            )
        return self._fmp_client

    def update_table_all(self, sym_list=None):
        """
        Update all tables that get data from external API services... Meant to
        be run as a scheduled job nightly.
        """
        self.update_table_cpi()
        self.update_table_cpi_u_index()
        self.update_table_asset(sym_list=sym_list)
        self.update_table_equity_profile(sym_list=sym_list)
        self.update_table_reporting_period(sym_list=sym_list)
        self.update_table_income_statement(sym_list=sym_list)
        self.update_table_balance_sheet_statement(sym_list=sym_list)
        self.update_table_cash_flow_statement(sym_list=sym_list)
        self.update_table_earning(sym_list=sym_list)
        self.update_table_eod_price(sym_list=sym_list)
        return

    def update_table_cpi(self, num_years=10):
        """
        Fetch CPI data from the BLS. Insert new data into SupaBase... otherwise
        update the existing data in the cpi table in case the data was revised.
        """
        logger.info("==== " * 16)
        logger.info("==== Updating pfin.cpi Table")
        api_key = utils.require_api_key(self._params, "BLS_API_KEY")

        logger.info("Fetch current CPI data from the BLS...")
        current_year = date.today().year
        starting_year = current_year - num_years + 1  # includes current year
        logger.info(f"Fetching years {starting_year} to {current_year}:")

        # [richmosko]: FIXME... Get Series Name(s) from .env
        df_api = utils.fetch_cpi_df(
            api_key, starting_year, current_year, ["CUUR0000SA0"]
        )
        # df_api = fetch_cpi(api_key, '2022', '2026', ['CUUR0000SA0','SUUR0000SA0'])
        df_api = df_api.with_columns(pl.lit("cpi-u").alias("series_name"))
        df_api = utils.clean_empty_str_df(df_api)
        # print(df_api)

        logger.info("Figure out what's already in pfin.cpi...")
        tab_sbase = self.base.by_module.pfin.cpi
        df_sbase = self.fetch_table_df(tab_sbase)
        # print(df_sbase)

        logger.info("Merging columns to (inner join) to limit what gets sent to DB...")
        (common_cols, df_old, df_new) = self._calc_common_cols_df(
            tab_sbase, df_sbase, df_api
        )
        # print(common_cols)

        logger.info("Determining entries to insert...")
        # [richmosko]: FIXME... key_list should inclue Series Name
        key_list = ["year", "month"]
        df_insert = self._isolate_new_rows_df(key_list, df_old, df_new)
        logger.info(f"Rows to insert:\n{df_insert}")

        logger.info("Determining entries to update...")
        df_update = self._isolate_updated_rows_df(key_list, df_old, df_new)
        # [richmosko]: add back primary key for update
        df_prikey = df_sbase.select(key_list + ["id"])
        df_update = df_update.join(df_prikey, on=key_list, how="left")
        logger.info(f"Rows to update:\n{df_update}")

        self.insert_table_df(tab_sbase, df_insert)
        self.update_table_df(tab_sbase, "id", df_update)
        return

    @staticmethod
    def _map_cpi_u_index_df(df_api):
        """
        Map a raw BLS CPI-U dataframe (as returned by utils.fetch_cpi_df) to the
        pfin.cpi_u_index grain: one row per calendar month.

        Transform contract:
            - month grain: BLS periods are M01..M12 for real months and M13 for the
              ANNUAL AVERAGE. M13 (and any period > 12) is DROPPED — it is not a
              calendar month and would produce an invalid first-of-month DATE.
            - cpi_period: first-of-month DATE = date(year, month, 1).
            - cpi_value:  the BLS series_value; non-finite / null values are dropped
              (the 053 CHECK cpi_u_index_value_finite rejects NaN; NOT NULL rejects
              null — we fail-closed at the worker before the DB does).
            - source:     CPI_U_SOURCE provenance string (053 DEFAULT parity; carried
              explicitly so a future series can coexist).
            - ingested_at: NOT set here — the DB DEFAULT now() stamps it on INSERT and
              the upsert re-stamps it from EXCLUDED on revision-UPDATE.

        args:    df_api (polars DataFrame from utils.fetch_cpi_df)
        returns: df_rows (polars DataFrame: cpi_period[Date], cpi_value[Float64],
                 source[str]) — ready for upsert_table_df on cpi_period.
        """
        df_rows = (
            df_api.filter(
                pl.col("month").is_not_null()
                & (pl.col("month") >= 1)
                & (pl.col("month") <= 12)
                & pl.col("series_value").is_not_null()
                & pl.col("series_value").is_finite()
            )
            .with_columns(
                pl.date(pl.col("year"), pl.col("month"), 1).alias("cpi_period"),
                pl.col("series_value").cast(pl.Float64).alias("cpi_value"),
                pl.lit(CPI_U_SOURCE).alias("source"),
            )
            .select(["cpi_period", "cpi_value", "source"])
            .unique(subset=["cpi_period"], keep="first")
            .sort("cpi_period")
        )
        return df_rows

    @staticmethod
    def _map_cpi_u_nonpublication_df(df_api):
        """
        Map a raw BLS CPI-U dataframe (as returned by utils.fetch_cpi_df) to the
        pfin.cpi_u_nonpublication grain: one row per calendar month that the
        source PUBLISHED WITHOUT A USABLE VALUE. Migration 063 / ADR-049
        Decision 1 (Option C, F/CTO-ratified 2026-08-10).

        ⚠ THIS IS THE EXACT COMPLEMENT OF _map_cpi_u_index_df ON VALUE, AND THE
        SAME FILTER ON GRAIN. That is the whole design, and it is what makes the
        reconciliation in _prepare_cpi_u_frames balance:
            · GRAIN — IDENTICAL. `month` non-null and 1..12, applied BEFORE any
              date is constructed. 063's standing requirement says to reuse the
              CPI-U mapper's month projection rather than invent a new fence,
              because BLS period codes are not all calendar months (M13 is the
              annual average, S01/S02 semiannual) and the transport returns raw
              codes with no grain filter BY DESIGN. 063's first-of-month CHECK
              fences the DAY of an already-constructed date; it cannot tell a
              real month from a non-monthly code mapped onto one. Necessary,
              not sufficient — the sufficiency is here.
            · VALUE — EXACTLY OPPOSED. The index mapper keeps `series_value`
              non-null AND finite; this keeps the negation (null OR non-finite).
              ⚠ DO NOT "REUSE THE MAPPER" WHOLESALE. Its five conjuncts include
              the two value ones, and those are PRECISELY THE ROWS THIS TABLE
              EXISTS TO RECORD. Applying it whole yields an empty record that is
              indistinguishable from a clean run — the failure this table was
              built to make impossible. Reuse the MONTH conjuncts only.

        `published_value_raw` is the token the source actually emitted (the
        observed real case is the single character '-'), captured by the
        transport BEFORE its Float64 cast destroys it. NULL is permitted by 063
        and means "the ingest did not capture the token" — NOT that the source
        emitted an empty value. A token longer than 063's 64-char bound is
        TRUNCATED, not rejected, and the truncation is WARNED — see the comment
        at the truncation itself for why each half of that is deliberate.

        args:    df_api (polars DataFrame from utils.fetch_cpi_df; MUST carry
                 `series_value_raw` — see the guard below)
        returns: df_rows (polars DataFrame: cpi_period[Date], source[str],
                 published_value_raw[str|null]) — ready for append_table_df on
                 cpi_period with ON CONFLICT DO NOTHING. `observed_at` is NOT
                 set here: the DB DEFAULT now() stamps the first observation,
                 and DO NOTHING is what preserves it.
        """
        if "series_value_raw" not in df_api.columns:
            # ⚠ FAIL LOUD RATHER THAN RECORD NULLS. `published_value_raw` is
            # nullable, so a missing token column would produce a table full of
            # legal, evidence-free rows and nothing would ever notice.
            raise CpiReconciliationError(
                "df_api carries no `series_value_raw` column — the transport is "
                "not supplying the raw BLS token, so pfin.cpi_u_nonpublication "
                "would be written with no evidence. Check utils.fetch_cpi_df."
            )
        df_hits = df_api.filter(
            pl.col("month").is_not_null()
            & (pl.col("month") >= 1)
            & (pl.col("month") <= 12)
            & (pl.col("series_value").is_null() | ~pl.col("series_value").is_finite())
        )

        # ⚠ TRUNCATION IS DELIBERATE, AND SILENCE ABOUT IT WOULD NOT BE.
        # 063 bounds published_value_raw at 64 chars so a global,
        # service_role-writable table carries no unbounded-text write vector.
        # We TRUNCATE rather than let the DB CHECK abort: an upstream anomaly in
        # source-controlled text must not take down the whole append, which
        # would lose the OTHER periods' evidence too — the bound protects the
        # table, it is not a reason to record nothing.
        #
        # But 063's column comment says this column is "what the source actually
        # emitted", and A TRUNCATED TOKEN IS NOT THAT. A >64-char token is
        # exactly the anomalous case where the evidence matters MOST, and it is
        # the one case where the evidence is silently altered — which is
        # ADR-049's own thesis (an unexplained absence is indistinguishable from
        # a correct one) reappearing inside the fix for it. So the alteration is
        # announced, with the original length, which is the part truncation
        # destroys and no reader could otherwise recover.
        overlong = df_hits.filter(
            pl.col("series_value_raw").cast(pl.String).str.len_chars()
            > CPI_U_RAW_TOKEN_MAX
        )
        for row in overlong.iter_rows(named=True):
            token = row.get("series_value_raw")
            logger.warning(
                f"CPI-U {row.get('year')}-{row.get('month'):02d}: the BLS token "
                f"is {len(token)} chars, over the {CPI_U_RAW_TOKEN_MAX}-char "
                "bound on pfin.cpi_u_nonpublication.published_value_raw. It is "
                f"STORED TRUNCATED to {CPI_U_RAW_TOKEN_MAX} chars, so that "
                "column is NOT what the source emitted for this period — the "
                f"full token began {token[:CPI_U_RAW_TOKEN_MAX]!r}. Truncating "
                "rather than aborting is deliberate: a bounded column fed "
                "source-controlled text must not turn an upstream anomaly into "
                "a CHECK violation that loses every other period's evidence. "
                "The non-publication record itself is unaffected and correct."
            )

        df_rows = (
            df_hits.with_columns(
                pl.date(pl.col("year"), pl.col("month"), 1).alias("cpi_period"),
                pl.lit(CPI_U_SOURCE).alias("source"),
                pl.col("series_value_raw")
                .cast(pl.String)
                .str.slice(0, CPI_U_RAW_TOKEN_MAX)
                .alias("published_value_raw"),
            )
            .select(["cpi_period", "source", "published_value_raw"])
            .unique(subset=["cpi_period"], keep="first")
            .sort("cpi_period")
        )
        return df_rows

    @staticmethod
    def _prepare_cpi_u_frames(df_api):
        """
        Split one BLS CPI-U fetch into its two destination frames and REFUSE TO
        PROCEED unless every period fetched is accounted for.

        ⚠⚠ THIS IS THE ENFORCEABLE HALF OF ADR-049, AND IT IS THE REASON THE
        TRANSPORT LIFT (utils.fetch_cpi_df) AND THIS WRITER SHIP TOGETHER.
        Lifting the drop without this assertion is STRICTLY WORSE THAN LANDING
        NOTHING: today an empty pfin.cpi_u_nonpublication means CORRECT, because
        empty is its only reachable state. The moment valueless rows can reach a
        writer, "empty" silently changes meaning to BROKEN — and no test, no
        constraint and no layer would notice, because the two worlds are
        identical at every layer. The balance is what tells them apart.

        THE ASSERTION, verbatim from 063's standing requirement, with the third
        term made explicit because the transport is grain-agnostic by design:

            periods returned by transport
              = rows for pfin.cpi_u_index
              + rows for pfin.cpi_u_nonpublication
              + periods that are not calendar months

        ⚠ IT IS NOT A MIRROR OF THE MAPPERS, WHICH IS WHAT MAKES IT ABLE TO
        FAIL. `n_nonmonthly` is computed here, directly from df_api, by an
        expression that does not call either mapper. The other two terms are the
        mappers' ACTUAL OUTPUT COUNTS. So if a mapper grows a filter for some
        third reason nobody has thought of, its output shrinks, the sum comes up
        short, and the run dies — WITHOUT that future filter having to be
        remembered, forbidden, or individually tested. That is the property
        063's header asks for: a rule someone must remember converted into an
        assertion that cannot pass quietly.

        ⚠ THE DISJOINTNESS CHECK IS NOT REDUNDANT WITH THE COUNT. The two value
        filters are exact complements, so no single ROW can land in both frames
        — but both mappers dedupe on cpi_period, so two rows for the SAME period
        (one valued, one not) put that period in BOTH frames while the counts
        still balance (2 = 1 + 1 + 0). That state is wrong: it would record a
        period as unpublished in the same breath as storing its value. The count
        cannot see it; this can.

        ⚠ WHAT THIS ASSERTION CANNOT SEE — STATED BECAUSE THE ALTERNATIVE IS
        CLAIMING COVERAGE IT DOES NOT PROVIDE.
          (a) A VALUE DROP RESTORED INSIDE utils.fetch_cpi_df. Its first term is
              "periods RETURNED by transport", so a row discarded before the
              return is absent from every term and the sum still balances. This
              gate is structurally blind to the exact regression S21 fixed. What
              covers it is one layer down and one layer earlier: the transport
              contract test in `test_cpi_drop_reconciliation.py`, which asserts
              the valueless period is RETAINED. Both run in the `unit` lane, and
              neither substitutes for the other.
          (b) BLS COMPLETENESS. A period the source omits entirely is invisible
              to every layer here — ADR-049 Decision 2's four-state list, and
              why 063's own header says it is not a completeness guarantee.
          (c) THE WRITES THEMSELVES. This balances what is STAGED, before either
              write; it is not a post-write read-back.

        args:    df_api (polars DataFrame from utils.fetch_cpi_df)
        returns: (df_index, df_nonpub) — both ready to write
        raises:  CpiReconciliationError on any imbalance or overlap
        """
        df_index = PFinBackend._map_cpi_u_index_df(df_api)
        df_nonpub = PFinBackend._map_cpi_u_nonpublication_df(df_api)

        n_returned = len(df_api)
        # Computed from df_api independently of both mappers — see the docstring.
        n_nonmonthly = len(
            df_api.filter(
                pl.col("month").is_null()
                | (pl.col("month") < 1)
                | (pl.col("month") > 12)
            )
        )
        n_index = len(df_index)
        n_nonpub = len(df_nonpub)

        # Unconditional, exactly as the transport's own line is: if the
        # reconciliation only appeared on imbalance, its absence would be
        # ambiguous and "balanced" would look identical to "never ran".
        logger.info(
            f"CPI-U reconciliation: {n_returned} period(s) returned by "
            f"transport = {n_index} for pfin.cpi_u_index + {n_nonpub} for "
            f"pfin.cpi_u_nonpublication + {n_nonmonthly} non-monthly."
        )

        if n_index + n_nonpub + n_nonmonthly != n_returned:
            raise CpiReconciliationError(
                "CPI-U period reconciliation FAILED — the fetch cannot be fully "
                "accounted for and NOTHING has been written. "
                f"transport returned {n_returned}; "
                f"pfin.cpi_u_index rows {n_index} + "
                f"pfin.cpi_u_nonpublication rows {n_nonpub} + "
                f"non-monthly periods {n_nonmonthly} = "
                f"{n_index + n_nonpub + n_nonmonthly}. "
                "A shortfall means periods were discarded between the transport "
                "and the tables — check for a filter added to either mapper, or "
                "a value drop restored in utils.fetch_cpi_df. A shortfall also "
                "results from DUPLICATE cpi_periods in one fetch (both mappers "
                "dedupe on cpi_period): that happens when more than one BLS "
                "series is fetched in a single call, which pfin.cpi_u_index "
                "cannot represent anyway — its PRIMARY KEY is cpi_period alone."
            )

        overlap = sorted(
            set(df_index["cpi_period"].to_list())
            & set(df_nonpub["cpi_period"].to_list())
        )
        if overlap:
            raise CpiReconciliationError(
                "CPI-U period reconciliation FAILED — NOTHING has been written. "
                f"{len(overlap)} period(s) are staged for BOTH pfin.cpi_u_index "
                f"and pfin.cpi_u_nonpublication in the same fetch: {overlap}. "
                "A period cannot be simultaneously published-with-a-value and "
                "published-without-one at one observation. (The two tables MAY "
                "legitimately share a period ACROSS runs — that is the "
                "'unpublished when we looked, published later' audit trail — "
                "but not from a single response.)"
            )

        return df_index, df_nonpub

    def update_table_cpi_u_index(self, start_year=None, end_year=None):
        """
        Fetch CPI-U (BLS series CUUR0000SA0) and write BOTH of its destination
        tables from that ONE response:
          · pfin.cpi_u_index (053) — UPSERT on cpi_period (first-of-month DATE).
            New months INSERT; BLS-revised prints UPDATE in place (the table is
            MUTABLE — eod_price/019 global-reference posture, not append-only).
          · pfin.cpi_u_nonpublication (063 / ADR-049) — APPEND with ON CONFLICT
            DO NOTHING, for periods the source published with NO usable value.

        ⚠ WHY ONE FUNCTION SPANS TWO TABLES, despite its name. The reconciliation
        that makes either write trustworthy — periods returned = rows for 053 +
        rows for 063 + non-monthly — is only computable where BOTH halves of a
        SINGLE response are visible. Splitting this into a second function with
        its own fetch would make the two sides un-balanceable against each other
        and re-create exactly the defect ADR-049 exists to close. If this is ever
        split, the reconciliation must move somewhere that still sees both, and
        that place must exist BEFORE the split, not after.

        Global public reference data (no tenant): the engine is the SYSTEM-mode
        TenantBoundConnection (TenantBoundConnection.system() in _sbase_setup) —
        NOT .for_tenant(); there is no users_id on this table.

        args:
            start_year:  first BLS year to fetch (default: a CPI_U_NIGHTLY_WINDOW_YEARS
                         trailing window ending at the current year — the nightly
                         revision-catch path). Deep history is laid down by
                         backfill_cpi_u_index() (the AC4 one-shot).
            end_year:    last BLS year to fetch (default: current year).

        Gov#3 (ratified minimal): run-logging only — no per-tenant audit row and no
        new audit table. Emits structured start / fetched / upserted / done logs on
        the pfin_etl logger (the minimal ETL run-log posture).
        """
        logger.info("==== " * 16)
        logger.info("==== Updating pfin.cpi_u_index Table (CPI-U / BLS CUUR0000SA0)")
        api_key = utils.require_api_key(self._params, "BLS_API_KEY")

        current_year = date.today().year
        if end_year is None:
            end_year = current_year
        if start_year is None:
            start_year = current_year - CPI_U_NIGHTLY_WINDOW_YEARS + 1
        logger.info(
            f"CPI-U fetch window: {start_year} -> {end_year} "
            f"(series {CPI_U_SERIES_ID})"
        )

        df_api = utils.fetch_cpi_df(
            api_key, start_year, end_year, [CPI_U_SERIES_ID]
        )
        # ⚠ THE GATE RUNS BEFORE EITHER WRITE. If the fetch cannot be fully
        # accounted for, this raises and nothing is written — a partially
        # recorded window is worse than an unrun one, because the next run's
        # `on conflict do nothing` would preserve the partial state as if it
        # were a first observation.
        df_rows, df_nonpub = self._prepare_cpi_u_frames(df_api)
        logger.info(f"CPI-U rows mapped to first-of-month grain: {len(df_rows)}")

        # ⚠ THE NON-PUBLICATION RECORD IS WRITTEN FIRST, AND THE ORDER IS
        # ARGUED, NOT INCIDENTAL. Both writes are idempotent and either order
        # self-heals on the next run inside the fetch window, so ordering only
        # matters for the run that dies between them. What 053 holds is
        # RECONSTRUCTIBLE from any later fetch. What 063 holds is not: a period
        # observed as unpublished NOW may be published later, and once it is,
        # the observation can never be made again — 053 will simply have a value
        # and nothing will record that we ever saw a gap. So the irrecoverable
        # write goes first. (They are separate transactions: these are two
        # global-reference tables, not a state change and its audit row, so the
        # same-transaction audit-log discipline is not what governs here.)
        if not df_nonpub.is_empty():
            tab_nonpub = self.base.by_module.pfin.cpi_u_nonpublication
            self.append_table_df(tab_nonpub, ["cpi_period"], df_nonpub)
            logger.warning(
                f"pfin.cpi_u_nonpublication: recorded {len(df_nonpub)} "
                "period(s) the BLS published with no usable value "
                f"({df_nonpub['cpi_period'].to_list()}). These are REAL GAPS in "
                "the CPI-U series, not ingest failures; consumers resolve them "
                "through pfin.fn_cpi_u_index_for_period."
            )

        if df_rows.is_empty():
            logger.warning(
                "CPI-U fetch returned no upsertable rows for window "
                f"{start_year}->{end_year}; skipping upsert."
            )
            return

        tab_sbase = self.base.by_module.pfin.cpi_u_index
        self.upsert_table_df(tab_sbase, ["cpi_period"], df_rows)
        logger.info(
            f"pfin.cpi_u_index upsert complete: {len(df_rows)} months "
            f"({df_rows['cpi_period'].min()} .. {df_rows['cpi_period'].max()})"
        )
        return

    def backfill_cpi_u_index(self, start_year=CPI_U_BASE_YEAR):
        """
        One-shot idempotent historical backfill of pfin.cpi_u_index so a row exists
        for every month from Dec-CPI_U_BASE_YEAR (2015) through the current month
        (SELF-230 AC4). Idempotent because the underlying write is an UPSERT on
        cpi_period — re-running rewrites the same values, never duplicates.

        Implemented as a year-by-year loop (start_year -> current year): each year is
        fetched + upserted independently, so a transient BLS failure in one year does
        not lose the years already written, and a re-run resumes cleanly. Not wired
        into the nightly update_table_all() path — it is invoked once (initial load)
        or on demand; the nightly update_table_cpi_u_index() keeps recent months
        fresh thereafter. (Coolify cron scheduling is deferred per the SELF-230
        ratified Phase-7 deferral.)
        """
        current_year = date.today().year
        logger.info("==== " * 16)
        logger.info(
            f"==== Backfilling pfin.cpi_u_index: {start_year} -> {current_year} "
            "(AC4 one-shot; idempotent upsert)"
        )
        for year in range(start_year, current_year + 1):
            logger.info(f"CPI-U backfill year {year}...")
            self.update_table_cpi_u_index(start_year=year, end_year=year)
        logger.info(
            f"pfin.cpi_u_index backfill complete ({start_year} -> {current_year})."
        )
        return

    def update_table_asset(self, sym_list=None):
        """
        Fetch asset date from the FMP API. Insert new data into SupaBase...

        args:
            sym_list:      (optional) list of symbols to fetch and update
                           When set to None, this method performs a stock-screen
                           API call to populate the sym_list.
        """
        logger.info("==== " * 16)
        logger.info("==== Updating pfin.asset Table")

        logger.info("Figure out what's already in pfin.asset...")
        tab_sbase = self.base.by_module.pfin.asset
        df_sbase = self.fetch_table_df(tab_sbase)
        # print(f"  Existing Symbols: {df_sbase['symbol'].to_list()}")

        logger.info("Querying for asset category...")
        tab_acat = self.base.by_module.pfin.asset_cat
        stmt = (
            sqla.select(tab_acat.id)
            .where(tab_acat.cat == "Equity")
            .where(tab_acat.sub_cat == "UNKNOWN")
        )
        ldict = self._fetch_sbase_ldict(stmt)
        asset_cat_id = ldict[0]["id"]
        # print(f"pfin.asset_cat.id = {asset_cat_id}\n")

        # print("Generating a symbol list to process...")
        if not sym_list:
            logger.info("Generating a symbol list to process...")
            df_slist = self.fmp_client.get_screened_stocks(
                self._stock_screener_min_mkt_cap, self._stock_screener_result_limit
            )
            sym_list = df_slist["symbol"].to_list()

        logger.info("Fetching data from Financial Modeling Prep...")
        df_fmp = self.fmp_client.fetch_fmp_list_df(
            self.fmp_client.search_symbol, "query", query=sym_list, limit=1
        )
        df_fmp = df_fmp.rename({"name": "description"})
        df_fmp = df_fmp.with_columns(
            [
                pl.lit(asset_cat_id).alias("asset_cat_id"),
                pl.lit(True).alias("has_financials"),
                pl.lit(True).alias("has_chart"),
            ]
        )
        df_fmp = utils.clean_empty_str_df(df_fmp)

        logger.info("Merging columns to (inner join) to limit what gets sent to DB...")
        (common_cols, df_old, df_new) = self._calc_common_cols_df(
            tab_sbase, df_sbase, df_fmp
        )
        # print(common_cols)

        logger.info("Determining entries to insert...")
        key_list = ["symbol"]
        df_insert = self._isolate_new_rows_df(key_list, df_old, df_new)
        logger.info(f"Rows to insert:\n{df_insert}")

        self.insert_table_df(tab_sbase, df_insert)
        return

    def update_table_equity_profile(self, sym_list=None):
        """
        Fetch extended Equity Profile data from FMP using the equity-profile API.
        Insert new entries into SupaBase, otherwise update existing entries with
        fresh data.
        """
        logger.info("==== " * 16)
        logger.info("==== Updating pfin.equity_profile Table")

        logger.info("Figure out what's already in pfin.equity_profile...")
        tab_sbase = self.base.by_module.pfin.equity_profile
        df_sbase = self.fetch_table_df(tab_sbase)
        # print(df_sbase)

        logger.info("Compiling set of symbol profiles to fetch from FMP...")
        asset_map = self._fetch_asset_map_financials()
        if sym_list:
            # [richmosko]: Only use subset of symbols
            asset_map = {sym: asset_map[sym] for sym in sym_list}
        id_list = list(asset_map.values())
        sym_list = list(asset_map.keys())
        # print(sym_list)

        logger.info("Fetching data from Financial Modeling Prep...")
        key_list = ["symbol"]
        df_fmp = self.fmp_client.fetch_fmp_list_df(
            self.fmp_client.profile, "symbol", symbol=sym_list, limit=1
        )
        df_fmp = df_fmp.rename({"symbol": "asset_id"})
        df_fmp = df_fmp.with_columns(pl.Series("asset_id", id_list))
        df_fmp = utils.clean_empty_str_df(df_fmp)
        # print(df_fmp['asset_id'].to_list())

        logger.info("Merging columns to (inner join) to limit what gets sent to DB...")
        (common_cols, df_old, df_new) = self._calc_common_cols_df(
            tab_sbase, df_sbase, df_fmp
        )
        # print(common_cols)

        logger.info("Determining entries to insert...")
        key_list = ["asset_id"]
        df_insert = self._isolate_new_rows_df(key_list, df_old, df_new)
        logger.info(f"Rows to insert:\n{df_insert}")

        logger.info("Determining entries to update...")
        df_update = self._isolate_updated_rows_df(key_list, df_old, df_new)
        # [richmosko]: primary key already present in FK asset_id
        logger.info(f"Rows to update:\n{df_update}")

        self.insert_table_df(tab_sbase, df_insert)
        self.update_table_df(tab_sbase, key_list, df_update)
        return

    def update_table_reporting_period(self, sym_list=None):
        """
        Fetch reporting-period data from FMP using the income-statement API.
        Insert new entries into SupaBase, otherwise update existing entries with
        fresh data.
        """
        YEARS_TO_FETCH = 5
        PERIODS_TO_FETCH = YEARS_TO_FETCH * 4

        logger.info("==== " * 16)
        logger.info("==== Updating pfin.reporting_period Table")

        logger.info("Figure out what's already in pfin.reporting_period..")
        tab_sbase = self.base.by_module.pfin.reporting_period
        df_sbase = self.fetch_table_df(tab_sbase)
        # print(df_sbase)

        logger.info("Generating a set of symbols to fetch from FMP...")
        asset_map = self._fetch_asset_map_financials()
        if sym_list:
            # [richmosko]: Only use subset of symbols
            asset_map = {sym: asset_map[sym] for sym in sym_list}
        id_list = list(asset_map.values())
        sym_list = list(asset_map.keys())
        # print(asset_map)

        logger.info("Fetching data from Financial Modeling Prep...")
        df_fmp = self.fmp_client.fetch_fmp_list_df(
            self.fmp_client.income_statement,
            "symbol",
            symbol=sym_list,
            limit=PERIODS_TO_FETCH,
            period="quarter",
        )
        df_fmp = utils.clean_empty_str_df(df_fmp)
        df_fmp = df_fmp.rename({"symbol": "asset_id"})
        df_fmp = df_fmp.with_columns(
            pl.col("asset_id")
            .replace(asset_map)
            .str.to_integer(strict=False)
            .alias("asset_id")
        )
        df_fmp = df_fmp.with_columns(
            pl.col("fiscal_year").str.to_integer(strict=False).alias("fiscal_year")
        )
        df_fmp = df_fmp.rename({"date": "end_date"})
        df_fmp = df_fmp.with_columns(
            pl.col("end_date").str.to_date(strict=False).alias("end_date")
        )
        df_fmp = df_fmp.with_columns(
            pl.col("filing_date").str.to_date(strict=False).alias("filing_date")
        )
        df_fmp = df_fmp.with_columns(
            pl.col("accepted_date")
            .str.to_datetime(strict=False, time_zone="UTC")
            .alias("accepted_date")
        )

        logger.info(
            "Create generic 'future' reporting periods for EPS & Rev estimates..."
        )
        # tmp_date_now = datetime.now(timezone.utc)
        tmp_date_fut = datetime.fromisoformat(self._tmp_date_fut).replace(
            tzinfo=timezone.utc
        )
        tmp_year_fut = self._tmp_year_fut
        tmp_period_fut = self._tmp_period_fut
        for asset_id in id_list:
            new_row = {
                "asset_id": asset_id,
                "filing_date": tmp_date_fut.date(),
                "accepted_date": tmp_date_fut,
                "fiscal_year": tmp_year_fut,
                "period": tmp_period_fut,
            }
            df_row = pl.DataFrame(new_row)
            df_fmp = pl.concat([df_fmp, df_row], how="diagonal")
        # print(df_fmp)

        logger.info("Merging columns to (inner join) to limit what gets sent to DB...")
        (common_cols, df_old, df_new) = self._calc_common_cols_df(
            tab_sbase, df_sbase, df_fmp
        )
        # print(common_cols)

        logger.info("Determining entries to insert...")
        key_list = ["asset_id", "fiscal_year", "period"]
        df_insert = self._isolate_new_rows_df(key_list, df_old, df_new)
        logger.info(f"Rows to insert:\n{df_insert}")

        logger.info("Determining entries to update...")
        df_update = self._isolate_updated_rows_df(key_list, df_old, df_new)
        # [richmosko]: add back primary key for update
        df_prikey = df_sbase.select(key_list + ["id"])
        df_update = df_update.join(df_prikey, on=key_list, how="left")
        logger.info(f"Rows to update:\n{df_update}")

        self.insert_table_df(tab_sbase, df_insert)
        self.update_table_df(tab_sbase, "id", df_update)
        return

    def update_table_income_statement(self, sym_list=None):
        """
        Fetch income-statement data from the FMP API.
        Insert new entries into SupaBase, otherwise update existing entries with
        fresh data.
        """
        YEARS_TO_FETCH = 5
        PERIODS_TO_FETCH = YEARS_TO_FETCH * 4

        logger.info("==== " * 16)
        logger.info("==== Updating pfin.income_statement Table")

        logger.info("Figure out what's already in pfin.reporting_period..")
        tab_rp = self.base.by_module.pfin.reporting_period
        df_rp = self.fetch_table_df(tab_rp)
        df_rp_map = df_rp[["id", "asset_id", "fiscal_year", "period"]]
        # print(df_rp_map)

        tab_sbase = self.base.by_module.pfin.income_statement
        df_sbase = self.fetch_table_df(tab_sbase)
        # print(df_sbase)

        logger.info("Generating a set of symbols to fetch from FMP...")
        asset_map = self._fetch_asset_map_financials()
        if sym_list:
            # [richmosko]: Only use subset of symbols
            asset_map = {sym: asset_map[sym] for sym in sym_list}
        # id_list = list(asset_map.values())
        sym_list = list(asset_map.keys())
        # print(asset_map)

        logger.info("Fetching income_statement data from Financial Modeling Prep...")
        df_fmp = self.fmp_client.fetch_fmp_list_df(
            self.fmp_client.income_statement,
            "symbol",
            symbol=sym_list,
            limit=PERIODS_TO_FETCH,
            period="quarter",
        )
        df_fmp = utils.clean_empty_str_df(df_fmp)
        df_fmp = df_fmp.rename({"symbol": "asset_id"})
        df_fmp = df_fmp.with_columns(
            pl.col("asset_id")
            .replace(asset_map)
            .str.to_integer(strict=False)
            .alias("asset_id")
        )
        df_fmp = df_fmp.with_columns(
            pl.col("fiscal_year").str.to_integer(strict=False).alias("fiscal_year")
        )
        df_fmp = df_fmp.rename({"date": "end_date"})
        df_fmp = df_fmp.with_columns(
            pl.col("end_date").str.to_date(strict=False).alias("end_date")
        )
        df_fmp = df_fmp.with_columns(
            pl.col("filing_date").str.to_date(strict=False).alias("filing_date")
        )
        df_fmp = df_fmp.with_columns(
            pl.col("accepted_date")
            .str.to_datetime(strict=False, time_zone="UTC")
            .alias("accepted_date")
        )
        uq_cols = ["asset_id", "fiscal_year", "period"]
        df_fmp = df_rp_map.join(df_fmp, on=uq_cols, how="inner")
        df_fmp = df_fmp.drop(uq_cols)
        df_fmp = df_fmp.rename({"id": "reporting_period_id"})
        # print(df_fmp['reporting_period_id'].to_list())

        logger.info("Merging columns to (inner join) to limit what gets sent to DB...")
        (common_cols, df_old, df_new) = self._calc_common_cols_df(
            tab_sbase, df_sbase, df_fmp
        )
        # print(common_cols)

        logger.info("Determining entries to insert...")
        key_list = "reporting_period_id"
        df_insert = self._isolate_new_rows_df(key_list, df_old, df_new)
        logger.info(f"Rows to insert:\n{df_insert}")

        logger.info("Determining entries to update...")
        df_update = self._isolate_updated_rows_df(key_list, df_old, df_new)
        # [richmosko]: primary key already present in FK reporting_period_id
        logger.info(f"Rows to update:\n{df_update}")

        self.insert_table_df(tab_sbase, df_insert)
        self.update_table_df(tab_sbase, key_list, df_update)
        return

    def update_table_balance_sheet_statement(self, sym_list=None):
        """
        Fetch balance-sheet-statement data from the FMP API.
        Insert new entries into SupaBase, otherwise update existing entries with
        fresh data.
        """
        YEARS_TO_FETCH = 5
        PERIODS_TO_FETCH = YEARS_TO_FETCH * 4

        logger.info("==== " * 16)
        logger.info("==== Updating pfin.balance_sheet_statement Table")

        logger.info("Figure out what's already in pfin.reporting_period..")
        tab_rp = self.base.by_module.pfin.reporting_period
        df_rp = self.fetch_table_df(tab_rp)
        df_rp_map = df_rp[["id", "asset_id", "fiscal_year", "period"]]
        # print(df_rp_map)

        logger.info("Figure out what's already in pfin.balance_sheet_statement..")
        tab_sbase = self.base.by_module.pfin.balance_sheet_statement
        df_sbase = self.fetch_table_df(tab_sbase)
        # print(df_sbase)

        logger.info("Generating a set of symbols to fetch from FMP...")
        asset_map = self._fetch_asset_map_financials()
        if sym_list:
            # [richmosko]: Only use subset of symbols
            asset_map = {sym: asset_map[sym] for sym in sym_list}
        # id_list = list(asset_map.values())
        sym_list = list(asset_map.keys())
        # print(asset_map)

        logger.info(
            "Fetching balance_sheet_statement data from Financial Modeling Prep..."
        )
        df_fmp = self.fmp_client.fetch_fmp_list_df(
            self.fmp_client.balance_sheet_statement,
            "symbol",
            symbol=sym_list,
            limit=PERIODS_TO_FETCH,
            period="quarter",
        )
        df_fmp = utils.clean_empty_str_df(df_fmp)
        df_fmp = df_fmp.rename({"symbol": "asset_id"})
        df_fmp = df_fmp.with_columns(
            pl.col("asset_id")
            .replace(asset_map)
            .str.to_integer(strict=False)
            .alias("asset_id")
        )
        df_fmp = df_fmp.with_columns(
            pl.col("fiscal_year").str.to_integer(strict=False).alias("fiscal_year")
        )
        df_fmp = df_fmp.rename({"date": "end_date"})
        df_fmp = df_fmp.with_columns(
            pl.col("end_date").str.to_date(strict=False).alias("end_date")
        )
        df_fmp = df_fmp.with_columns(
            pl.col("filing_date").str.to_date(strict=False).alias("filing_date")
        )
        df_fmp = df_fmp.with_columns(
            pl.col("accepted_date")
            .str.to_datetime(strict=False, time_zone="UTC")
            .alias("accepted_date")
        )
        uq_cols = ["asset_id", "fiscal_year", "period"]
        df_fmp = df_rp_map.join(df_fmp, on=uq_cols, how="inner")
        df_fmp = df_fmp.drop(uq_cols)
        df_fmp = df_fmp.rename({"id": "reporting_period_id"})
        # print(df_fmp['reporting_period_id'].to_list())

        logger.info("Merging columns to (inner join) to limit what gets sent to DB...")
        (common_cols, df_old, df_new) = self._calc_common_cols_df(
            tab_sbase, df_sbase, df_fmp
        )
        # print(common_cols)

        logger.info("Determining entries to insert...")
        key_list = "reporting_period_id"
        df_insert = self._isolate_new_rows_df(key_list, df_old, df_new)
        logger.info(f"Rows to insert:\n{df_insert}")

        logger.info("Determining entries to update...")
        df_update = self._isolate_updated_rows_df(key_list, df_old, df_new)
        # [richmosko]: primary key already present in FK reporting_period_id
        logger.info(f"Rows to update:\n{df_update}")

        self.insert_table_df(tab_sbase, df_insert)
        self.update_table_df(tab_sbase, key_list, df_update)
        return

    def update_table_cash_flow_statement(self, sym_list=None):
        """
        Fetch cash-flow-statement data from the FMP API.
        Insert new entries into SupaBase, otherwise update existing entries with
        fresh data.
        """
        YEARS_TO_FETCH = 5
        PERIODS_TO_FETCH = YEARS_TO_FETCH * 4

        logger.info("==== " * 16)
        logger.info("==== Updating pfin.cash_flow_statement Table")

        logger.info("Figure out what's already in pfin.reporting_period..")
        tab_rp = self.base.by_module.pfin.reporting_period
        df_rp = self.fetch_table_df(tab_rp)
        df_rp_map = df_rp[["id", "asset_id", "fiscal_year", "period"]]
        # print(df_rp_map)

        logger.info("Figure out what's already in pfin.cash_flow_statement..")
        tab_sbase = self.base.by_module.pfin.cash_flow_statement
        df_sbase = self.fetch_table_df(tab_sbase)
        # print(df_sbase)

        logger.info("Generating a set of symbols to fetch from FMP...")
        asset_map = self._fetch_asset_map_financials()
        if sym_list:
            # [richmosko]: Only use subset of symbols
            asset_map = {sym: asset_map[sym] for sym in sym_list}
        # id_list = list(asset_map.values())
        sym_list = list(asset_map.keys())
        # print(asset_map)

        logger.info("Fetching cash_flow_statement data from Financial Modeling Prep...")
        df_fmp = self.fmp_client.fetch_fmp_list_df(
            self.fmp_client.cash_flow_statement,
            "symbol",
            symbol=sym_list,
            limit=PERIODS_TO_FETCH,
            period="quarter",
        )
        df_fmp = utils.clean_empty_str_df(df_fmp)
        df_fmp = df_fmp.rename({"symbol": "asset_id"})
        df_fmp = df_fmp.with_columns(
            pl.col("asset_id")
            .replace(asset_map)
            .str.to_integer(strict=False)
            .alias("asset_id")
        )
        df_fmp = df_fmp.with_columns(
            pl.col("fiscal_year").str.to_integer(strict=False).alias("fiscal_year")
        )
        df_fmp = df_fmp.rename({"date": "end_date"})
        df_fmp = df_fmp.with_columns(
            pl.col("end_date").str.to_date(strict=False).alias("end_date")
        )
        df_fmp = df_fmp.with_columns(
            pl.col("filing_date").str.to_date(strict=False).alias("filing_date")
        )
        df_fmp = df_fmp.with_columns(
            pl.col("accepted_date")
            .str.to_datetime(strict=False, time_zone="UTC")
            .alias("accepted_date")
        )
        uq_cols = ["asset_id", "fiscal_year", "period"]
        df_fmp = df_rp_map.join(df_fmp, on=uq_cols, how="inner")
        df_fmp = df_fmp.drop(uq_cols)
        df_fmp = df_fmp.rename({"id": "reporting_period_id"})
        # print(df_fmp['reporting_period_id'].to_list())

        logger.info("Merging columns to (inner join) to limit what gets sent to DB...")
        (common_cols, df_old, df_new) = self._calc_common_cols_df(
            tab_sbase, df_sbase, df_fmp
        )
        # print(common_cols)

        logger.info("Determining entries to insert...")
        key_list = "reporting_period_id"
        df_insert = self._isolate_new_rows_df(key_list, df_old, df_new)
        logger.info(f"Rows to insert:\n{df_insert}")

        logger.info("Determining entries to update...")
        df_update = self._isolate_updated_rows_df(key_list, df_old, df_new)
        # [richmosko]: primary key already present in FK reporting_period_id
        logger.info(f"Rows to update:\n{df_update}")

        self.insert_table_df(tab_sbase, df_insert)
        self.update_table_df(tab_sbase, key_list, df_update)
        return

    def update_table_earning(self, sym_list=None):
        """
        Fetch earnings data from the FMP API.
        Insert new entries into SupaBase, otherwise update existing entries with
        fresh data.

        The alignment with reporting_period(s) needs to be handled uniquely, as the
        reference dates in earnings do not match the filing or accepted dates in
        the actual 10Q or income_statement data. The latest one is close though... so
        the older quarters are backfilled based on that match. Future earnings estimates
        are stored in an arbitrary future date to denote that the data is incomplete and
        so that the actual quarterly updates don't create duplicate quarters with different
        refernece dates.
        """

        YEARS_TO_FETCH = 5
        PERIODS_TO_FETCH = YEARS_TO_FETCH * 4

        logger.info("==== " * 16)
        logger.info("==== Updating pfin.earning Table")

        logger.info("Figure out what's already in pfin.reporting_period...")
        tab_rp = self.base.by_module.pfin.reporting_period
        df_rp = self.fetch_table_df(tab_rp)
        df_rp_map = df_rp[["id", "asset_id", "accepted_date"]]
        # print(df_rp_map)

        logger.info(
            "Find the current report date for each asset_id in pfin.reporting_period..."
        )
        asset_id_list = df_rp_map["asset_id"].unique().to_list()
        latest_rpt = {}
        for asset_id in asset_id_list:
            df_tmp = df_rp_map.filter(pl.col("asset_id") == asset_id)
            df_tmp = df_tmp.sort("accepted_date", descending=True)
            # [richmosko]: skip the 1st date which is reserved for future estimates...
            if len(df_tmp) > 1:
                latest_rpt[asset_id] = df_tmp.item(1, "accepted_date")
            else:
                # Doesn't seem to have released financial statements...
                latest_rpt[asset_id] = datetime.now(timezone.utc)
        # print(f"  Latest Reports: {latest_rpt}")

        logger.info("Figure out what's already in pfin.earning...")
        tab_sbase = self.base.by_module.pfin.earning
        df_sbase = self.fetch_table_df(tab_sbase)
        # print(df_sbase)

        logger.info("Generating a set of symbols to fetch from FMP...")
        asset_map = self._fetch_asset_map_financials()
        if sym_list:
            # [richmosko]: Only use subset of symbols
            asset_map = {sym: asset_map[sym] for sym in sym_list}
        id_list = list(asset_map.values())
        sym_list = list(asset_map.keys())
        # print(asset_map)

        logger.info("Fetching earning data from Financial Modeling Prep...")
        df_fmp = self.fmp_client.fetch_fmp_list_df(
            self.fmp_client.earnings,
            "symbol",
            symbol=sym_list,
            limit=(PERIODS_TO_FETCH + 2),
        )
        df_fmp = utils.clean_empty_str_df(df_fmp)
        df_fmp = df_fmp.rename({"symbol": "asset_id"})
        df_fmp = df_fmp.rename({"date": "accepted_date"})
        df_fmp = df_fmp.with_columns(
            pl.col("asset_id")
            .replace(asset_map)
            .str.to_integer(strict=False)
            .alias("asset_id")
        )
        df_fmp = df_fmp.with_columns(
            pl.col("accepted_date").str.to_date(strict=False).alias("ref_date")
        )
        df_fmp = df_fmp.with_columns(
            pl.col("accepted_date")
            .str.to_datetime(strict=False, time_zone="UTC")
            .alias("accepted_date")
        )
        df_fmp = df_fmp.with_columns(pl.lit(None).alias("reporting_period_id"))
        # print(df_fmp)

        logger.info("Match earnings reports to posted reporting_periods...")
        # sort and add a temporary row_idx as primary keys
        df_rp_map = df_rp_map.sort("accepted_date", descending=True).with_row_index(
            name="row_idx"
        )
        df_fmp = df_fmp.sort("accepted_date", descending=True).with_row_index(
            name="row_idx"
        )

        fmp_drop_list = []
        for asset_id in id_list:
            cond_fmp_asset_id = pl.col("asset_id") == asset_id
            cond_fmp_filing_date = pl.col("accepted_date") <= latest_rpt[
                asset_id
            ] + timedelta(weeks=2)
            # filter for the conditions above, and get the row_idx values as lists
            fmp_idx = df_fmp.filter(cond_fmp_asset_id & cond_fmp_filing_date)[
                "row_idx"
            ].to_list()
            rpm_idx = df_rp_map.filter(cond_fmp_asset_id & cond_fmp_filing_date)[
                "row_idx"
            ].to_list()
            # since the lengths have to match, truncate the the shorter length and remember dropped idxs
            joint_len = min([len(fmp_idx), len(rpm_idx)])
            fmp_drop_list.extend(fmp_idx[joint_len:])
            fmp_idx = fmp_idx[:joint_len]
            rpm_idx = rpm_idx[:joint_len]
            # get the list of reporting_period.id(s) from the row indexes
            rpm_list = df_rp_map.filter(pl.col("row_idx").is_in(rpm_idx))[
                "id"
            ].to_list()
            df_map = pl.DataFrame({"row_idx": fmp_idx, "reporting_period_id": rpm_list})
            # now find the index rows in df_fmp and replace them with rpm_list
            if len(df_map):
                df_fmp = df_fmp.update(df_map, on="row_idx")

        logger.info(
            f"Dropping long dated earnings with no reporting_periods: {fmp_drop_list}..."
        )
        df_fmp = df_fmp.filter(~pl.col("row_idx").is_in(fmp_drop_list))

        logger.info(
            "Set remaining unmatched earnings reports to future reporting_periods..."
        )
        # tmp_date_now = datetime.now(timezone.utc)
        tmp_date_fut = (
            datetime.fromisoformat(self._tmp_date_fut)
            .replace(tzinfo=timezone.utc)
            .date()
        )
        df_fmp = df_fmp.with_columns(
            pl.when(pl.col("reporting_period_id").is_null())
            .then(pl.lit(tmp_date_fut))
            .otherwise(pl.col("accepted_date"))
            .alias("accepted_date")
        )
        uq_cols = ["asset_id", "accepted_date"]
        df_rp_map = (
            df_rp_map.filter(pl.col("accepted_date") == tmp_date_fut)
            .rename({"id": "reporting_period_id"})
            .drop("row_idx")
        )
        df_fmp = df_fmp.update(df_rp_map, on=uq_cols)
        df_fmp = df_fmp.unique(subset=["reporting_period_id"], keep="last")
        df_fmp = df_fmp.drop(["asset_id", "accepted_date", "row_idx"])
        # print(df_fmp.filter(pl.col('asset_id') == 111))
        logger.info(
            f"  Null reporting_period_id(s) found: {
                len(df_fmp.filter(pl.col('reporting_period_id').is_null()))
            }"
        )
        # print(df_fmp)

        logger.info("Merging columns to (inner join) to limit what gets sent to DB...")
        (common_cols, df_old, df_new) = self._calc_common_cols_df(
            tab_sbase, df_sbase, df_fmp
        )
        # print(common_cols)

        logger.info("Determining entries to insert...")
        key_list = "reporting_period_id"
        df_insert = self._isolate_new_rows_df(key_list, df_old, df_new)
        logger.info(f"Rows to insert:\n{df_insert}")

        logger.info("Determining entries to update...")
        df_update = self._isolate_updated_rows_df(key_list, df_old, df_new)
        # [richmosko]: primary key already present in FK reporting_period_id
        logger.info(f"Rows to update:\n{df_update}")

        self.insert_table_df(tab_sbase, df_insert)
        self.update_table_df(tab_sbase, key_list, df_update)
        return

    def update_table_eod_price(self, sym_list=None):
        """
        Fetch end of day price data from the FMP API.
        Insert new entries into SupaBase, otherwise update existing entries with
        fresh data in case the historical data was revised.
        """

        YEARS_TO_FETCH = 5
        DAYS_TO_FETCH = YEARS_TO_FETCH * 365

        logger.info("==== " * 16)
        logger.info("==== Updating pfin.eod_price Table")

        logger.info("Figure out what's already in pfin.eod_price...")
        tab_sbase = self.base.by_module.pfin.eod_price
        df_sbase = self.fetch_table_df(tab_sbase)
        # print(df_sbase)

        logger.info("Generating a set of symbols to fetch from FMP...")
        asset_map = self._fetch_asset_map_chart()
        if sym_list:
            # [richmosko]: Only use subset of symbols
            asset_map = {sym: asset_map[sym] for sym in sym_list}
        # id_list = list(asset_map.values())
        sym_list = list(asset_map.keys())
        # print(asset_map)

        logger.info("Fetching EOD historical data from Financial Modeling Prep...")
        date_5y_ago = datetime.now() - timedelta(days=DAYS_TO_FETCH)
        date_5y_ago = date_5y_ago.strftime("%Y-%m-%d")
        df_fmp = self.fmp_client.fetch_fmp_list_df(
            self.fmp_client.historical_full,
            "symbol",
            symbol=sym_list,
            start_date=date_5y_ago,
        )
        df_fmp = utils.clean_empty_str_df(df_fmp)
        df_fmp = df_fmp.rename({"symbol": "asset_id"})
        df_fmp = df_fmp.with_columns(
            pl.col("asset_id")
            .replace(asset_map)
            .str.to_integer(strict=False)
            .alias("asset_id")
        )
        df_fmp = df_fmp.rename({"date": "end_date"})
        df_fmp = df_fmp.with_columns(
            pl.col("end_date").str.to_date(strict=False).alias("end_date")
        )
        # print(df_fmp)

        logger.info("Merging columns to (inner join) to limit what gets sent to DB...")
        (common_cols, df_old, df_new) = self._calc_common_cols_df(
            tab_sbase, df_sbase, df_fmp
        )
        # print(common_cols)

        logger.info("Determining entries to insert...")
        key_list = ["asset_id", "end_date"]
        df_insert = self._isolate_new_rows_df(key_list, df_old, df_new)
        logger.info(f"Rows to insert:\n{df_insert}")

        logger.info("Determining entries to update...")
        df_update = self._isolate_updated_rows_df(key_list, df_old, df_new)
        # [richmosko]: add back primary key for update
        df_prikey = df_sbase.select(key_list + ["id"])
        df_update = df_update.join(df_prikey, on=key_list, how="left")
        logger.info(f"Rows to update:\n{df_update}")

        self.insert_table_df(tab_sbase, df_insert)
        self.update_table_df(tab_sbase, "id", df_update)
        return

    def _fetch_asset_map_financials(self):
        """
        Generate an asset => asset_id map (for items with financial statements)

        returns:
            asset_map:     dictionary of symbol(s) and mapped asset_id(s)
        """
        tab_asset = self.base.by_module.pfin.asset
        tab_asset_cat = self.base.by_module.pfin.asset_cat
        stmt = (
            sqla.select(tab_asset.symbol, tab_asset.id)
            .join(tab_asset_cat)
            .where(tab_asset_cat.cat == "Equity")
            .where(tab_asset.has_financials)
        )
        return self._fetch_asset_map(stmt)

    def _fetch_asset_map_chart(self):
        """
        Generate an asset => asset_id map (for items with price charts)

        returns:
            asset_map:     dictionary of symbol(s) and mapped asset_id(s)
        """
        tab_asset = self.base.by_module.pfin.asset
        tab_asset_cat = self.base.by_module.pfin.asset_cat
        stmt = (
            sqla.select(tab_asset.symbol, tab_asset.id)
            .join(tab_asset_cat)
            .where(tab_asset_cat.cat == "Equity")
            .where(tab_asset.has_chart)
        )
        return self._fetch_asset_map(stmt)

    def _fetch_asset_map(self, stmt):
        """
        Generate list of symbols to work on based on the provuded select statememt
        args:
            stmt:          sqlalchemy select statement to query DB table

        returns:
            asset_map:     dictionary of symbol(s) and mapped asset_id(s)
        """
        ldict = self._fetch_sbase_ldict(stmt)
        asset_map = {}
        for item in ldict:
            sym = item["symbol"]
            xid = item["id"]
            asset_map[sym] = xid
        return asset_map

    def _set_dtype_df(self, tab_sbase, df_sbase):
        """
        Set the initial datatypes for columns in a polars dataframe from the
        sqlalchemy reflected table.

        args:
            tab_sbase:     reflected sqlalchemy table
            df_sbase:      polars dataframe of  ^^^^^ table

        returns:
            df_dtype:      schema corrected polars dataframe
        """
        # c_dict = pfb.get_column_dict(tab_sbase)
        # df_schema = df_sbase.schema
        logger.info("...TODO: METHOD NOT YET IMPLEMENTED...")
        # TODO: Creating a big case statement for all the data types is a big
        #       undertaking... Not urgent to impleent this right away.
        return None
