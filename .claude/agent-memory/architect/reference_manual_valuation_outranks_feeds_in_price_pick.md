---
name: manual-valuation-outranks-feeds-in-price-pick
description: 078's price pick ranks manual_valuation ABOVE every feed, so writing an 087-style companion eod_price onto an already-held position retroactively restates the whole holding at cost
metadata:
  type: reference
---

`078`'s price pick is `order by price_date desc, <source-rank CASE>, price_id desc`, and the
CASE puts **`manual_valuation` at rank 1** — ahead of `market_feed` / `spot_feed` / `fx_feed`
(all 2) and `provider_implied` (3).

**Consequence that is NOT visible from any one file:** the `087` F3 remedy — "every
instrument-bound position also writes its `eod_price` row, `round(cost_basis/quantity,4)`,
`source='manual_valuation'`" — is only safe on an asset with **no existing position**. Applied
to a purchase that adds to an **already-held** asset it restates **every prior lot** at the new
purchase's per-unit cost, for every `as_of` until a later-dated row exists, and on the trade
date it *outranks a same-day feed price*. Unrealized G/L on the old lots silently vanishes.
Call it **F4**; it is the inverse of F3 (F3 = write the price or it's $0; F4 = write the price
and you corrupt what's already there).

⚠ The safe formulation is a **post-condition over the price the reader will PICK** (non-zero at
the trade date), not over a row's existence — a presence-watcher passes on both F3-b (zero-valued
row) and a skipped-write-over-a-worthless-row.

**Companion boundary, same neighbourhood:** an authenticated user **cannot mint a GLOBAL
`pfin.asset` row.** `016 asset_insert WITH CHECK (users_id = auth.uid())` fails on
`users_id NULL`, and `020` grants global INSERT to **`service_role` only**. So a manual account
cannot record a purchase of a ticker the provider-sync worker has never registered. ⚠ The
tempting workaround — mint a **per-user** row for a public ticker — is a one-way door:
`asset_global_symbol_uniq` is `unique(symbol) WHERE users_id IS NULL`, so a per-user `AAPL` is
legal and **shadows** the global one; un-merging means re-pointing `security_id` on the
immutable append-only ledger (`004`).

Related: [[feedback_mirror_a_function_from_the_catalog_not_the_file]] (the live
`fn_create_manual_trans` is `040`'s 8-arg body, not `038`'s).

---

**⚠ THERE IS NO MARKET-PRICE FEED IN V1 — measured, and it is invisible from any single file.**
`grep` across `supabase/migrations/*.sql` and `workers/**/src` finds **no INSERT writing
`source='market_feed'`**. The value exists in `016`'s and `019`'s CHECK vocabularies and as rank 2
in every price-pick `CASE`, with **no writer**. The only price writers that exist:

- **`provider_implied`** — the worker (`mapper.ts`), `marketValue / quantity`, only for securities
  held in a **provider-linked** account.
- **`manual_valuation`** — `authenticated`, and `019 eod_price_insert` admits it **only on an asset
  the caller OWNS**, which structurally excludes GLOBAL rows.

⇒ A global asset held only in a **manual** account is **unpriceable** — no path exists to give it a
price — until some provider-linked account somewhere holds the same security.
⇒ `pricingSourceForAssetType()` in `resolution.ts` labels equity/etf/fund/bond as `'market_feed'`,
so **every auto-registered security claims a feed that does not exist.** The label is aspirational.

⚠ **`019 eod_price_insert`'s own `comment on` calls it "OWD-E — Sec-classified cross-tenant-write
gate."** Relaxing it to let users price GLOBAL assets is veto-grade: `eod_price_select` makes global
prices readable by **every** tenant, and `manual_valuation` outranks every feed — so one tenant would
move another's NAV and override their provider price. ⚠ **Routing that same write through the worker
does NOT fix it.** `service_role` settles *who may write*, never *whose number it is*.
