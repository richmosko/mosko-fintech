---
name: trade-class-annotation-needs-security-id
description: A Trade-class annotation is refused unless security_id is present — so a Trade row reaches fn_cashflow_items ONLY as a split child, which is the only route a Revenue-class fence fixture can use
metadata:
  type: reference
---

`fn_account_trans_annotation_trade_constraints` (`030`, ADR-031 Amendment 1 s2a) enforces
`security_id present <=> cat = 'Trade'` on `pfin.account_trans_annotation`. And `093`'s
`fn_cashflow_items` excludes every row with `security_id is not null`.

**The two together make the transaction-grain route structurally unreachable:** a
`Trade / STC` or `Trade / BTC` row can never appear in `fn_cashflow_items` as an
`item_kind = 'transaction'`. Measured 2026-09-04 while fixturing `104` — the direct
annotation INSERT is refused with `Trade consistency violation ... (M1-evt / SELF-293)`.

**The one route that works is the SPLIT CHILD.** `pfin.account_trans_split` carries its own
`sub_cat_id` and `fn_account_trans_split_matched_sub_cat` (`029`/`084`) does **not**
class-check, so a split child on a NON-security parent may carry a Trade prototype and
`fn_cashflow_items` emits it as `item_kind = 'split_child'`. That is how the
`tax_relevant AND cat = 'Revenue'` fence in `104` is actually reachable, and it is the only
fixture shape that makes an L-REV-style leg non-vacuous.

**How to apply:** any battery leg proving a cat-based fence over `fn_cashflow_items` must
seed through the split branch. A fixture attempting the transaction grain **fails to seed**,
and if the seeding error is swallowed the leg goes green for the wrong reason. Same family
as [[project_p4_split_child_journaled_cat_residual]] — the split child is repeatedly the
grain a class fence does not reach.
