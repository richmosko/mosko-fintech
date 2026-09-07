---
name: account-trans-fk-restrict-pins-parent-account
description: pfin.account has no delete-blocking trigger of its own, but any account with ≥1 account_trans row can never be deleted — account_trans is append-only (its own immutability trigger) AND FK-RESTRICTs the account. Reverse-and-replace zeroes the balance; the row itself is permanent.
metadata:
  type: reference
---

Discovered while cleaning up a test-fixture account after the P10 pre-condition walk
(2026-09-07, main @ df7d015). `pfin.account` itself carries no DELETE-blocking trigger — a
brand-new account with zero transactions (`account_id` 4294 in that walk) deletes cleanly with a
plain `DELETE FROM pfin.account WHERE account_id = ...`.

But the moment an account has even ONE `pfin.account_trans` row, it becomes permanently
undeletable: `account_trans.account_id REFERENCES pfin.account(account_id) ON DELETE RESTRICT`,
and `account_trans` rows themselves can never be removed (its own append-only/immutability
trigger — same class as [[reference_pg_visible_in_snapshot_poisoning_dblink_and_trigger_exceptions]]'s
account_trans findings, and the P2-walk precedent of reverse-and-replace via
`is_reverse=true, replaces_trans_id=...`). So a seeded account with a real transaction (4293 in
that same walk) can be zeroed out (insert a reversal, net balance $0) but the ACCOUNT ROW ITSELF
is permanent — there is no sanctioned path back to a pre-seed state once a transaction has
touched it.

**How to apply**: before seeding a throwaway test account for a one-off walk/proof, decide
up front whether it needs a transaction. If it does, treat the account as PERMANENT fixture
residue from the moment the first transaction lands — plan to zero its balance via
reverse-and-replace rather than expecting to delete it afterward, and flag the permanent residue
explicitly in the hand-off report (a later walk or Sec review on the same tenant's Accounts page
will see it). If a throwaway account genuinely doesn't need a transaction, it's fully deletable
and leaves zero residue — prefer that shape when the test doesn't require a real balance.
