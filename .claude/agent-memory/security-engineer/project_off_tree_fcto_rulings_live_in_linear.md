---
name: off-tree-fcto-rulings-live-in-linear
description: A recurring class in this project — an F/CTO ratify recorded ONLY in a Linear issue description or comment, invisible to every grep. Check Linear before calling a decision unmade or an obligation undischarged.
metadata:
  type: project
---

**Some F/CTO rulings in this project exist only in Linear and appear nowhere in the repo. Before
concluding a decision is unmade, an obligation undischarged, or a mechanism unspecified, check the
issue — the repo is not the complete record for decisions that produced no diff.**

**Why:** this is a **named, repeating failure class**, not an accident. ADR-062 opens by recording
the first instance verbatim — *"The original Option-A ratify existed **only in a Linear issue
description**. That is not a durable record: it is not greppable from the tree, it does not travel
with the migration, and it was re-litigated at the V1.3 pre-flight because nobody could find it."*
At the **V1.4 pre-flight I hit it twice more in one sitting**:

- **F/CTO Gate B Option A, ratified 2026-06-03** — `account.tax_jurisdiction` enum as the IRS/FTB
  account-identification mechanism. Measured: `tax_jurisdiction` and *"Gate B Option A"* appear in
  **none** of `DECISIONS.md`, `supabase/`, `api/`, `docs/`, `BACKLOG.md`, `MILESTONES.md`. I raised
  it as an **open ruling needing an F/CTO call** when it had been settled for three months.
- **The `is_tax_payment` marking pass** — ADR-062 Decision 3's stated HARD PRECONDITION. F/CTO
  ruled the enumeration's outcome to be **zero rows marked** on 2026-08-25, recorded in a SELF-245
  comment. Since the ruling changed nothing, the tree shows exactly what an un-run enumeration
  would show, and I reported it as undischarged.

**How to apply:**
- **When an obligation is phrased as a DECISION** (*"F/CTO enumerates / marks / confirms / rules
  X"*) rather than a CHANGE, its discharge may be an empty diff. Ask for the issue before
  reporting it open. Route the Linear read through `linear-liaison`.
- **The tell in the other direction:** an AC or issue description citing a ratify with a **date and
  an option letter** (*"Gate B Option A locked 2026-06-03"*) that returns nothing on a repo grep.
  That is a real ruling with no durable home — not a fabrication, and not something to re-decide.
- **Report it as a RECORD finding, not a DECISION finding.** The remedy is an ADR at the PR that
  realizes the ruling, per ADR-062's own precedent. Do not re-open the underlying call.
- **Both error directions cost:** calling a discharged obligation open wastes a sitting item;
  calling a settled decision open invites its re-litigation. Neither is caught by measuring harder.

Related: [[triage-a-multileg-bypass-leg-by-leg]] (the absence-vs-omission rule this produced),
[[claim-about-the-world-vs-decision-about-what-we-do]], [[relay-from-the-tree-not-the-report]].
