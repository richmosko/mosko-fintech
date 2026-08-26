---
name: is-tax-payment-expense-scope-gap
description: ADR-062 scopes is_tax_payment to Expense-class prototypes; the two Transfer-class tax seed rows are outside it BY DESIGN (F/CTO-ruled 2026-08-25) — the class filter, not the flag, excludes them
metadata:
  type: project
---

`is_tax_payment` (ADR-062, realized at `091`) is **scoped to Expense-class posting
prototypes** — both column comments say so, and ADR-062 Decision 3 scopes the F/CTO
marking enumeration the same way. But `041` seeded `Tax - US Federal` and
`Tax - California` under **`cat='Transfer'`**, not `Expense`. So the two rows a
tax-payment marking most obviously wants are **outside the flag's declared scope**.

**Why:** ADR-062 was drafted against the PRD §2.3.4 discretionary-expenses filter,
which filters `cat = 'Expense'` before reading the flag. The scope statement is
correct for that consumer and silently insufficient for the intent.

**How to apply:** raised at the `091` handoff and **RULED same day (F/CTO,
2026-08-25, recorded on SELF-245): this is BY DESIGN, not a gap.** PRD §2.3.4
charts "the Expenses scope of §2.3.2" minus marked buckets — Transfer-class tax
payments never enter that scope, so the class filter excludes them structurally
and the flag exists only for Expense-class buckets that function as tax payments
(property tax was explicitly ruled to stay in its recorded Expense buckets;
marking pass complete with zero rows marked). Do NOT re-raise this as a defect,
and do NOT quietly mark Transfer rows `true` — that contradicts a ratified scope
in two catalog comments. The three alternative shapes (widen scope / handle
Transfer in the filter / reclassify the rows) become live only if product intent
changes. Related: [[feedback_pm_draft_ac_vs_schema]],
[[project_prd_predates_gl_recalibration]].
