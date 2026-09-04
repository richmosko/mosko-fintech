---
name: reference-fn-create-manual-purchase-journaled-fixture
description: pfin.fn_create_manual_purchase (088) is the real production write path for a journaled asset purchase — p_cost_basis is TOTAL not per-unit, and it auto-mints day-1 eod_price; bump eod_price separately for a later gain.
metadata:
  type: reference
---

`pfin.fn_create_manual_purchase(p_account_id bigint, p_trade_date date, p_quantity numeric,
p_cost_basis numeric, p_security_id bigint default null, p_asset_type text default null,
p_asset_name text default null, p_symbol text default null, p_sub_cat_id bigint default null,
p_description text default null, p_note text default null) returns (trans_id, security_id,
priced, price)` — SECURITY INVOKER, must run under the OWNING tenant's context (auth.uid()
required, not postgres). To mint a new owned asset: pass `p_security_id null` +
`p_asset_type`/`p_asset_name` (+ optional `p_symbol`).

**`p_cost_basis` is the TOTAL cost basis for the whole purchase, not per-unit** —
`v_price := round(p_cost_basis / p_quantity, 4)`. A call with `p_quantity=10,
p_cost_basis=1000` records a $100.00/unit day-1 `eod_price(manual_valuation)` row
automatically. Both `account_trans.quantity` (numeric(28,8)) and `.cost_basis`
(numeric(20,4)) land at their FULL column precision — comparing against a bare `'10'` text
literal fails; compare against `'10.00000000'` or cast/compare numerics directly, not text.

To create a genuine UNREALIZED GAIN for a downstream tax-liability leg: after the purchase,
insert a SEPARATE, LATER `eod_price` row for the same `asset_id` at a higher price (a
different `price_date`, any `source` — e.g. `market_feed`) — the purchase RPC only ever
writes the DAY-1 price, never a later market update. `fn_account_unrealized_gl` (049) reads
D-first LOCF, so the later row wins for any `as_of` on/after it.

Used to build SELF-269's "journaled positive-gain" close-gate fixture (2026-09-04) — the
first Unrealized fixture in the tree reached through the real production write path rather
than a raw `account_trans` INSERT (every prior fixture — 104's L11/L12, 105's PI/R9 blocks —
uses the raw-INSERT shortcut).
