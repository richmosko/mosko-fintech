"""
Project:       pfin_back_etl
Author:        Rich Mosko

Description:
    Common utility functions

"""

# library imports
import logging
import os
import dotenv
import re
import requests
import json
import polars as pl
import sqlalchemy.ext.automap as sqla_automap

logger = logging.getLogger("pfin_etl")


def col_to_snake(col_list):
    col_dict = {}
    for col in col_list:
        col_dict[col] = re.sub(r"([a-z])([A-Z])", r"\1_\2", col).lower()
    return col_dict


def ldict_to_df(ldict, tab):
    cols = tab.columns.keys()
    df = pl.DataFrame(schema=cols) if not ldict else pl.DataFrame(ldict)
    return df


def clean_empty_str_df(df):
    df_clean = df.with_columns(pl.col(pl.String).replace("", None))
    return df_clean


def apply_schema_df(df_src, df_tgt):
    """
    Cast datatypes from one polars dataframe(df_from) to another DF(df_to)

    args:
        df_src:            polars dataframe source to extract schema(datatypes)
        df_tgt:            polars dataframe target to apply schema(datatypes)

    returns:
        df_cast:           df_tgt with casted datatypes (polars DF)
    """
    schema_src = df_src.schema
    schema_tgt = df_tgt.schema
    for key in schema_tgt.keys():
        if key in schema_src:
            schema_tgt[key] = schema_src[key]
    df_cast = df_tgt.cast(schema_tgt)
    return df_cast


# ---------------------------------------------------------------------------
# CREDENTIAL LOADING — BACKLOG §7.6 S12. Shape ruled 2026-08-09.
# ---------------------------------------------------------------------------
# THE LOADER RAISES FOR NOTHING; THE ACCESSOR RAISES AT THE POINT OF USE.
#
# It used to hard-require FMP_API_KEY and BLS_API_KEY at load time, and both
# workers load through here. Measured: `nav_daily.py` contains ZERO references
# to either key and makes ZERO external API calls — it computes NAV from the
# database. So the NAV cron had to be handed two credentials it has no business
# holding, cutting against least-privilege and the secrets non-overlap
# commitment, or die on its first scheduled run before doing any work.
#
# Chosen over a `require=(...)` argument on one function: a requirement-set
# parameter keeps one function answering two questions, and every new caller
# has to remember to pass the right set — where FORGETTING IT SILENTLY LOOSENS
# THE CHECK rather than tripping it. Splitting makes "which credentials does
# this job need?" answerable by WHICH FUNCTION IT CALLS, and moving the raise
# to the accessor keeps the failure loud and located at the consumer.

#: Per-key env-name preference, highest priority first. A key absent from this
#: mapping is read from its own name only.
_API_KEY_SOURCES = {
    # BLS_API_KEY_TEST is preferred when present. NOT a security control and
    # not a fence — nothing can inspect a local .env and nothing should try.
    #
    # What it buys: the secrets manifest's whole convention rests on DISTINCT
    # NAMES CARRYING THE TIER, and the code defeated that at the local boundary
    # — `BLS_API_KEY_TEST` had no reader, so a dev machine necessarily held a
    # PRODUCTION-NAMED credential whatever value was in it. With this, a dev's
    # .env holds the test key under the TEST name, the production name is
    # absent from developer machines entirely, and "is there a production-named
    # credential on this laptop?" becomes a question with a checkable right
    # answer of NO. The discipline becomes auditable by SHAPE rather than by
    # trust.
    "BLS_API_KEY": ("BLS_API_KEY_TEST", "BLS_API_KEY"),
}


def load_db_params(env_prefix):
    """Database connection parameters only. RAISES FOR NOTHING.

    This is everything a worker needs to construct a connection — and for
    `nav_daily`, everything it needs at all.
    """
    dotenv.load_dotenv()
    params = {
        "DB_USER": os.getenv(env_prefix + "DB_USER"),
        "DB_HOST": os.getenv(env_prefix + "DB_HOST"),
        "DB_PORT": os.getenv(env_prefix + "DB_PORT"),
        "DB_NAME": os.getenv(env_prefix + "DB_NAME"),
        "DB_PASSWORD": os.getenv(env_prefix + "DB_PASSWORD"),
        # OPTIONAL, and the default is the security-load-bearing part. Unset ->
        # "require", so production is unchanged and an environment that simply
        # forgot to set it still demands TLS. Only an EXPLICIT value can weaken
        # the transport, and only to a value on build_database_url()'s allowlist.
        "DB_SSLMODE": os.getenv(env_prefix + "DB_SSLMODE"),
    }
    return params


def load_api_keys():
    """External-API credentials. RAISES FOR NOTHING — absent keys are None.

    A worker that never calls the API never notices the key is missing, which
    is the whole point: absence is only an error at the point of USE.
    """
    dotenv.load_dotenv()
    keys = {}
    for key_name in ("FMP_API_KEY", "BLS_API_KEY"):
        for source in _API_KEY_SOURCES.get(key_name, (key_name,)):
            value = os.getenv(source)
            if value is not None:
                keys[key_name] = value
                logger.info(f"{key_name} value found (from {source})...")
                break
        else:
            keys[key_name] = None
    return keys


def require_api_key(params, key_name):
    """Return `params[key_name]`, raising HERE if it is absent.

    THE POINT-OF-USE RAISE. Call this at the moment the key is about to be
    used, never at construction — so the error names the job that actually
    needed the credential, and a job that does not need it constructs and runs.
    """
    value = (params or {}).get(key_name)
    if value is None:
        raise ValueError(
            f"{key_name} is required by this operation but is not set. "
            f"Looked at: {', '.join(_API_KEY_SOURCES.get(key_name, (key_name,)))}. "
            f"Note this is raised AT THE POINT OF USE — a worker that does not "
            f"call this API does not need the credential and will not raise."
        )
    return value


def load_env_variables(env_prefix):
    """DB params + API keys in one dict. RAISES FOR NOTHING (see S12 above).

    Retained because both workers and the test-suite call it; the behaviour
    change is that absent API keys are now None rather than a ValueError at
    load time. Prefer `load_db_params()` in a worker that makes no API calls.
    """
    params = load_db_params(env_prefix)
    params.update(load_api_keys())
    return params


# libpq's sslmode vocabulary. An explicit value must be one of these; anything else
# RAISES rather than being passed through, because a typo ("requre") would otherwise
# reach libpq as an error at connect time — far from the misconfiguration — and a
# silently-substituted default would be worse still: it would change the transport
# posture without anyone being told.
_SSLMODES = ("disable", "allow", "prefer", "require", "verify-ca", "verify-full")
_SSLMODE_DEFAULT = "require"


def build_database_url(params):
    """Build the psycopg2 SQLAlchemy URL from a loaded params dict (as returned by
    load_env_variables). Single source of the connection string so every engine —
    the ETL system engine (_sbase_setup) and the SELF-214 per-tenant NAV worker —
    constructs it identically.

    TLS: `sslmode` defaults to **require** and is overridable via `<prefix>DB_SSLMODE`.

    ⚠ THE DEFAULT IS THE SECURITY-LOAD-BEARING PART, NOT THE OVERRIDE. Unset, absent,
    or empty -> "require": production is unchanged, and an environment that forgot to
    set it still demands TLS. Only an EXPLICIT value can weaken the transport, and only
    to a member of _SSLMODES; anything else raises rather than silently falling back.

    WHY IT IS CONFIGURABLE AT ALL (BACKLOG §7.6 S11). It was hard-coded to "require",
    and the local Supabase CLI stack offers no TLS — so the ETL could not be pointed at
    the local stack AT ALL, and the barrier sat at connect time, before any logic. That
    made every worker unrunnable locally without editing this file, which is plausibly
    why the assembled NAV path went unrun until SELF-214 S10 forced it. A verification
    gate you must patch the code under test to execute does not get executed.

    args:    params (dict with DB_USER / DB_PASSWORD / DB_HOST / DB_PORT / DB_NAME,
             and optionally DB_SSLMODE)
    returns: database_url (str) for TenantBoundConnection.system()/.for_tenant().
    raises:  ValueError if DB_SSLMODE is set to something outside _SSLMODES.
    """
    sslmode = (params.get("DB_SSLMODE") or "").strip() or _SSLMODE_DEFAULT
    if sslmode not in _SSLMODES:
        raise ValueError(
            f"DB_SSLMODE={sslmode!r} is not a valid libpq sslmode. "
            f"Expected one of {_SSLMODES}. Refusing to guess: an unrecognised value "
            f"must not silently become the default, because that would change the "
            f"transport posture without saying so."
        )
    url = f"postgresql+psycopg2://{params['DB_USER']}:{params['DB_PASSWORD']}@"
    url += f"{params['DB_HOST']}:{params['DB_PORT']}/{params['DB_NAME']}"
    url += f"?sslmode={sslmode}"
    return url


def sqla_modulename_for_table(tablename, declarativetable, reflecttable):
    """
    This function needs to be defined with the above input arguments
    for sqlalchemy to automap the table names including the schemas
    when referencing through the 'by_module' class:
        ie: base.by_module.pfin.reporting_period

    used in the _sbase_setup() member function of PfinSBaseConn

    returns: schema (string of schema name to use)
    """
    if reflecttable.schema:
        return reflecttable.schema
    else:
        # Default module name if no schema is present
        return "public"


# ---------------------------------------------------------------------------
# Automap relationship-name collision guard (BACKLOG §7.6 S13).
# ---------------------------------------------------------------------------
# SQLAlchemy's automap names a generated SCALAR relationship after the REFERRED
# TABLE. When a table carries both an FK to table T and a column literally named
# T, the generated relationship and the mapped column claim the same attribute
# name, and automap RAISES rather than disambiguating:
#
#   ArgumentError: when configuring property 'tax_character' on
#   Mapper[user_taxonomy(user_taxonomy)], column 'tax_character' conflicts with
#   property '<_RelationshipDeclared ... tax_character>'
#
# That fires inside base.prepare(), i.e. during SBaseConn.__init__ — so
# PFinBackend() cannot be CONSTRUCTED and no ETL method is reachable at all.
# pfin.user_taxonomy (migration 009) + pfin.tax_character (011) is the instance
# that was found, ~50 migrations after it was introduced.
#
# THE GUARD IS GENERAL ON PURPOSE. A hard-coded exception for tax_character
# would fix one name and leave the next one to be discovered the same way — by
# a production entry point failing to start. This is a property of the SCHEMA
# SHAPE (any FK-to-T alongside a column named T), not of one table.
#
# THE COLUMN ALWAYS WINS. `tax_character` is a ratified domain term on a locked
# migration surface and the defect is in the mapper, not the model, so attribute
# access for the COLUMN is unchanged: `user_taxonomy.tax_character` is still the
# text column. It is the RELATIONSHIP that is renamed. Its new name is derived
# from the FK's own local column names:
#
#     pfin.user_taxonomy  ->  .tax_character        the text column (unchanged)
#                         ->  .tax_character_ref    the FK relationship to
#                                                   pfin.tax_character
#
# WHY THE FK COLUMNS AND NOT A FIXED SUFFIX. The disambiguator has to stay
# unique when one table holds several FKs to the same target — pfin.lot_match
# holds two to pfin.account_trans (buy_trans_id / sell_trans_id). Keying the
# fallback on the constraint's own columns keeps it unique without any
# cross-call state, so the hooks stay pure functions of their arguments and a
# second prepare() on a fresh base produces identical names.
#
# NON-COLLIDING NAMES ARE LEFT ALONE. The hooks delegate to automap's own
# defaults and only intervene on an actual collision, so every existing
# `base.by_module.<schema>.<table>.<rel>` access site is unaffected.

# Declarative attribute names a generated relationship must not take even though
# they are not columns; the column scan below would not catch them.
_SQLA_RESERVED_ATTRS = frozenset({"metadata", "registry"})


def _sqla_reserved_names(local_cls):
    """Attribute names already claimed on `local_cls` that a generated
    relationship must not collide with (its mapped columns, plus the declarative
    names above)."""
    return set(local_cls.__table__.columns.keys()) | _SQLA_RESERVED_ATTRS


def _sqla_fk_qualifier(constraint):
    """Constraint-unique disambiguator: the FK's own local column names.

    Unique per constraint, so several FKs from one table to one target resolve
    to distinct fallback names without any shared state.
    """
    return "_".join(col.name for col in constraint.columns)


def _sqla_fk_count_to_target(child_table, parent_table):
    """How many FKs `child_table` declares against `parent_table`.

    Compared by (schema, name) rather than object identity: reflection can
    yield distinct Table objects for the same relation across MetaData
    instances, and an identity check would silently return 1 and disable the
    guard — failing OPEN, in a way no error would report.
    """
    key = (parent_table.schema, parent_table.name)
    return sum(
        1
        for fk in child_table.foreign_key_constraints
        if (fk.referred_table.schema, fk.referred_table.name) == key
    )


def _sqla_meaning_name(constraint):
    """A meaning-carrying name from the FK's own columns: buy_trans_id -> buy_trans.

    The bare target-table name is the ambiguity, so the FK's columns are what
    carry the meaning — `buy_trans` and `sell_trans` say which leg, where
    `account_trans` says only which table.
    """
    qualifier = _sqla_fk_qualifier(constraint)
    return qualifier[:-3] if qualifier.endswith("_id") else qualifier


def _sqla_disambiguate(default_name, local_cls, fallback_base):
    """Return `default_name` unless it is already claimed on `local_cls`, in
    which case return `fallback_base` (numerically suffixed if that is claimed
    too). Pure: no state carried between calls."""
    reserved = _sqla_reserved_names(local_cls)
    if default_name not in reserved:
        return default_name
    candidate = fallback_base
    n = 2
    while candidate in reserved:
        candidate = f"{fallback_base}{n}"
        n += 1
    return candidate


def sqla_name_for_scalar_relationship(base, local_cls, referred_cls, constraint):
    """automap hook — see the collision-guard block above.

    The argument signature is fixed by SQLAlchemy. Wired in core.py's
    SBaseConn._sbase_setup() at base.prepare(). Delegates to automap's own
    default so upstream naming is tracked, and only renames on a real collision.
    """
    default = sqla_automap.name_for_scalar_relationship(
        base, local_cls, referred_cls, constraint
    )
    # BACKLOG §7.6 S15. Automap names the relationship after the REFERRED
    # TABLE, so a table with TWO FKs to one target produces the SAME name
    # twice and the second silently overwrites the first. Unlike S13 there is
    # no error and no warning: the mapping is present and means something
    # other than it reads. Measured on `pfin.lot_match` -> `pfin.account_trans`
    # (buy_trans_id / sell_trans_id) — the scalar resolved to the SELL leg and
    # the nominal reverse collection to the BUY leg, so the two were NOT
    # reverses of each other and the buy side was unreachable.
    #
    # ⚠ THE S13 GUARD BELOW CORRECTLY DECLINES TO ACT HERE, which is why this
    # is a separate condition rather than a widening of it: that guard fires on
    # a relationship-vs-COLUMN collision, and there is none — `lot_match` has
    # no `account_trans` column. Nothing was claimed, so nothing looked wrong.
    if _sqla_fk_count_to_target(local_cls.__table__, referred_cls.__table__) > 1:
        default = _sqla_meaning_name(constraint)
    fallback = f"{_sqla_fk_qualifier(constraint)}_ref"
    return _sqla_disambiguate(default, local_cls, fallback)


def sqla_name_for_collection_relationship(base, local_cls, referred_cls, constraint):
    """automap hook for the one-to-many side — see the collision-guard block.

    Here `local_cls` is the PARENT (referred) class and `constraint` lives on the
    CHILD table, so the fallback names the child table as well as its columns.
    No collision of this shape exists in the schema today (measured at migration
    062); the hook is wired because the default name is `<child>_collection` and
    a parent column of that name would fail identically.
    """
    default = sqla_automap.name_for_collection_relationship(
        base, local_cls, referred_cls, constraint
    )
    # S15, reverse side. The default is `<child>_collection`, which collapses
    # identically when the child holds two FKs to this parent — and the two
    # sides collapse INDEPENDENTLY, which is what made the scalar and its
    # nominal reverse resolve to DIFFERENT legs.
    if _sqla_fk_count_to_target(constraint.table, local_cls.__table__) > 1:
        default = (
            f"{constraint.table.name}_{_sqla_meaning_name(constraint)}_collection"
        )
    fallback = f"{constraint.table.name}_{_sqla_fk_qualifier(constraint)}_collection"
    return _sqla_disambiguate(default, local_cls, fallback)


def sqla_resolve_referred_schema(table, to_metadata, constraint, referred_schema):
    """
    Dynamically determines the target schema for a foreign key reference
    in sqlalchemy. Used when creating a temp table for a staging update.
    """
    if referred_schema == "source_schema":
        return "target_schema"  # Map 'source_schema' to 'target_schema'
    return referred_schema


def fetch_cpi_df(api_key, startyear, endyear, series_id_lst):
    """
    Fetch Consumer Price Index data from the Brureau of Labor Statistics.

    args:
        startyear:         starting year to fetch in 'yyyy' format
        endyear:           ending year to fetch in 'yyyy' format
        series_id_lst:     list of series IDs to fetch. id: ['CUUR0000SA0']

    returns:
        df_cpi:            polars dataframe of CPI index data. Columns of note:
                           `series_value` (Float64, NULL where BLS published no
                           usable value) and `series_value_raw` (String, the
                           token BLS actually emitted — e.g. the literal '-').

    ⚠ INPUT CONTRACT — READ THIS BEFORE ADDING A CONSUMER.

    0. ⚠ VALUE-NULL PERIODS ARE RETURNED, NOT DROPPED — and that is the whole
       point of this function's second consumer. BLS publishes a period it has
       no value for with the literal token "-" (measured: 2025-M10, a real
       non-publication). The `strict=False` cast below turns that into null.
       This function KEEPS the row and hands it to its callers, because
       `pfin.cpi_u_nonpublication` (migration 063, ADR-049 Decision 1) exists
       precisely to record those periods and CANNOT BE POPULATED BY ANY WRITER
       if the transport discards them first.
       ⚠ THE DROP THAT USED TO LIVE HERE IS GONE ON PURPOSE. Do not restore it,
       and do not add a `drop_value_nulls=True` parameter "for safety" — a
       filter with a default is where this class of defect lives, and the 053
       write path never needed one: `PFinBackend._map_cpi_u_index_df` already
       re-checks `series_value` non-null AND finite, so it is unaffected by the
       lift. `053` still forbids storing a valueless period (NOT NULL plus a
       finiteness CHECK), so the drop is still correct THERE. It was never
       correct HERE, where it destroyed the row for every consumer at once.
       `series_value_raw` is carried for the same reason: the cast overwrote the
       token in place, so `063.published_value_raw` had no possible source.

    1. This returns RAW BLS PERIOD CODES. That includes NON-MONTHLY ones —
       `M13` (annual average) and `S01`/`S02` (semiannual) — WHENEVER THE
       REQUEST ASKS FOR THEM (`annualaverage` / `aspects`). The payload built
       above sets neither, which is why only M01–M12 come back today.
       MEASURED at the live API for 2015–2026: 138 rows, every one M01–M12.
    2. NO MONTHLY-GRAIN FILTERING HAPPENS HERE, AND THAT IS DELIBERATE. This
       function is a faithful transport of what BLS returned; deciding which
       periods are meaningful belongs to the consumer that knows its own grain.
    3. THE LIVE CONSUMER'S GUARD IS ELSEWHERE — `PFinBackend._map_cpi_u_index_df`
       in `core.py` filters to `month` non-null and 1..12 (and re-checks
       `series_value` non-null and finite). It is documented in that function's
       own docstring and pinned by a test that deliberately injects an `M13`
       row. Dropping `M13` there is CORRECT, not a swallow: an annual average
       is not a monthly observation, and a monthly series should discard it.
    3a. ⚠ THE STORED SERIES IS LEGITIMATELY NON-CONTIGUOUS, AND A CONSUMER MUST
       TOLERATE A MISSING PERIOD. `2025-M10` is absent from `pfin.cpi_u_index`
       and that is CORRECT — not a gap to backfill, interpolate, or "fix".
       Measured by direct query (ADR-049) rather than inferred from a row count:
       BLS published the period with the literal '-', the cast above nulls it,
       and `053`'s NOT NULL forbids storing it. Exactly one such gap exists
       across Jan-2015 → Jun-2026, so 137-of-138 is one real gap rather than a
       coincidental total. ⚠ **The measurement settled WHY the gap exists; it did
       not remove the requirement to handle one.** The CPI-U overlay and every
       other consumer of this series must not assume contiguous months.

    4. ⚠ A NEW CONSUMER DOES NOT INHERIT THAT GUARD AND MUST APPLY ITS OWN.
       The protection lives in one consumer and is invisible from here, which
       is why this note exists. `update_table_cpi` is the only other caller and
       applies no grain filter — it targets `pfin.cpi`, which no V1 migration
       creates, so nothing live depends on that today.

    ⚠ THE SECOND-CONSUMER TRIGGER HAS FIRED, AND IT DID NOT MEAN "ADD A FENCE."
    This note used to say: replace it with a fence when a SECOND LIVE CONSUMER
    exists, and that zero were pending. One exists now —
    `PFinBackend._map_cpi_u_nonpublication_df`, the writer for `063`. Sec ruled
    the consequence on 2026-08-10 (recorded in `063`'s header, the sole durable
    copy) and it runs OPPOSITE to the instinct the old sentence invites, because
    the trigger conflated two dimensions the second consumer splits apart. The
    two consumers AGREE on grain (both want month 1..12) and are EXACTLY OPPOSED
    on value (053's writer wants only valued rows; 063's wants only the
    valueless ones). Therefore:
      · GRAIN fence — PERMITTED but OPTIONAL, and deliberately NOT taken here.
        Both consumers apply their own month projection; asserting the grain in
        the transport would still break the `M13` test that caught the earlier
        over-correction, and point 2 above refuses it on contract grounds.
      · VALUE fence — FORBIDDEN. It would destroy `063`'s entire subject.
      · The EXISTING value drop — LIFTED (point 0). That was the mandatory work.
    ⚠ THE ENFORCEABLE HALF IS NOT IN THIS FUNCTION. The counts logged below are
    observability, not a gate — a reconciliation that only this function can see
    cannot prove the rows reached a table. The gate is
    `PFinBackend._prepare_cpi_u_frames`, which asserts
    `periods returned by transport = rows for 053 + rows for 063 + non-monthly
    periods` and raises on imbalance. If you change the shape of what this
    function returns, that assertion is what will tell you.
    """
    headers = {"Content-type": "application/json"}
    data = json.dumps(
        {
            "registrationkey": api_key,
            "seriesid": series_id_lst,
            "startyear": startyear,
            "endyear": endyear,
        }
    )
    p = requests.post(
        "https://api.bls.gov/publicAPI/v2/timeseries/data/", data=data, headers=headers
    )
    json_data = json.loads(p.text)

    logger.info(f"JSON STATUS: {json_data['status']}")
    if json_data["status"] != "REQUEST_SUCCEEDED":
        raise Exception("BLS CPI fetch request unsuccessful")

    df_list = []
    for series in json_data["Results"]["series"]:
        df = pl.DataFrame(series["data"])
        df = df.rename(col_to_snake(df.columns))
        df = df.with_columns(pl.lit(series["seriesID"]).alias("series_id"))
        df = df.rename({"period": "month"})
        df = df.with_columns(
            [
                pl.col("month")
                .str.strip_chars("M")
                .cast(pl.Int64, strict=False)
                .alias("month"),
                pl.col("year").cast(pl.Int64, strict=False).alias("year"),
                pl.col("value").cast(pl.Float64, strict=False).alias("value"),
                # ⚠ THE RAW TOKEN, CAPTURED BEFORE THE CAST DESTROYS IT.
                # Every expression in a single `with_columns` evaluates against
                # the INPUT frame, so this sees the pre-cast string even though
                # the line above overwrites `value` in place. That in-place
                # overwrite is why `063.published_value_raw` — nullable, <= 64
                # chars, and documented as "what the source actually emitted" —
                # had no possible source until now. Do not reorder these into
                # separate `with_columns` calls: the second would see the cast
                # column and this would silently become all-null, which is a
                # legal value for that column and would therefore be INVISIBLE.
                pl.col("value").cast(pl.String).alias("value_raw"),
            ]
        )
        # ⚠ WHAT USED TO BE HERE, AND WHY IT IS NOT.
        # `df = df.drop_nulls(subset=["value"])` stood on this spot from the
        # monorepo import (`20ca752`) until 2026-08-10. It entered unreasoned
        # (`git log -S` returned exactly one commit, so the scope was never
        # CHOSEN in either direction), was made non-silent by BACKLOG §7.6 S20,
        # and is now LIFTED by S21 because it made `pfin.cpi_u_nonpublication`
        # (063 / ADR-049) unpopulable by any writer — the row it removed IS that
        # table's subject, and it never left this function.
        #
        # ⚠ WHAT REPLACES IT IS NOT A WEAKER DROP — IT IS A PARTITION.
        # Nothing is discarded here. The valueless rows are REPORTED and
        # RETURNED; deciding what to do with them belongs to the consumer that
        # knows its own table. `053` still refuses to store them (NOT NULL plus
        # a finiteness CHECK) and `_map_cpi_u_index_df` still filters them out
        # for that path — the drop moved to where the constraint lives, which is
        # where it was always correct.
        #
        # ⚠ THESE COUNTS ARE OBSERVABILITY, NOT THE GATE. S20's note said the
        # reconciliation is the load-bearing half, and that is still true — but
        # a count this function computes about its own return value cannot
        # notice a row lost AFTER it returns, which is exactly what happened.
        # The gate is `PFinBackend._prepare_cpi_u_frames`, which balances what
        # this function returned against what actually reaches both tables.
        # Emitted UNCONDITIONALLY, including when nothing is valueless:
        # otherwise its absence would be ambiguous and "nothing to report" would
        # look identical to "the logging broke".
        n_returned = len(df)
        valueless = df.filter(pl.col("value").is_null())
        n_valueless = len(valueless)
        for row in valueless.iter_rows(named=True):
            month = row.get("month")
            period = f"{row.get('year')}-{month:02d}" if month is not None else (
                f"{row.get('year')}-M?? (non-monthly or unparsable period code)"
            )
            logger.warning(
                f"BLS {series['seriesID']}: period {period} was published with "
                f"NO USABLE VALUE (raw token {row.get('value_raw')!r}). The "
                f"series has a REAL GAP here; it is NOT a fetch failure. The "
                f"row is RETAINED and returned so the non-publication record "
                f"(pfin.cpi_u_nonpublication) can be written from it."
            )
        logger.info(
            f"BLS {series['seriesID']}: {n_returned} period(s) returned, "
            f"{n_returned - n_valueless} with a published value, "
            f"{n_valueless} published with no usable value (retained)."
        )
        df = df.rename({"value": "series_value", "value_raw": "series_value_raw"})
        df = df.drop("footnotes")
        df = df.with_columns(pl.format("{}-{}-14", "year", "month").alias("ref_date"))
        df_list.append(df)
    df_cpi = pl.concat(df_list, how="vertical_relaxed")
    return df_cpi
