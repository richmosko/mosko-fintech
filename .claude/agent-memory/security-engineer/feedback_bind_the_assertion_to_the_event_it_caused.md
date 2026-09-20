---
name: bind-the-assertion-to-the-event-it-caused
description: An assertion that selects "the latest X" instead of "the X this run caused" reads a prior run's evidence — fail-closed only until a prior run looks valid
metadata:
  type: feedback
---

When a control polls for the result of an action it triggered, grade the **selector**, not only the evidence. `rows[0]` / "the latest execution" / "the most recent row" is a **positional** selector; what the control needs is an **identity** one — the row the action created.

**Why:** the migrator's first real fire polled `rows[0]` before its own execution row existed (dispatch lag) and parsed a **previous** run's output. It failed closed **only because the older rows predated the tagged command and carried no tags** — and that very fire created the precondition that removes the accident. On a re-fire against the same image, a stale row's sha, ledger top and newest-file all match, so **every assertion passes on evidence from a run this fire did not cause**, and the deploy gate opens on a prior success. **Report this class as a latent FAIL-OPEN, not as "fail-closed, note the shape."**

**How to apply:**
- Prefer an **identity** binding: the id the trigger call returns. If the trigger returns nothing, **take the SET DIFFERENCE of ids from the list before and after** — that is still identity, and it needs no cooperation from the trigger endpoint.
- Treat a **timestamp-ordering** binding as a weaker fallback: it depends on the column's precision (a vendor-schema premise) and on nothing else creating a row in the TOCTOU window — a process lock does not close that against a human using the vendor UI.
- Fail closed on **zero** (after the ceiling) and on **two or more**, with distinct messages; "the event never appeared" is a different fault from "it ran and failed".
- Sweep the whole chain for other "latest X" reads, and **say which ones are correctly scoped** so they are not "fixed" — "the newest file in THIS image" and "the ledger top AFTER this run" are the intended semantics.

Related: [[feedback_an_accepted_residual_must_not_silently_widen]] (the ratified text said "the execution's OWN message" — a binding the build never had), [[feedback_a_gate_on_a_status_already_ruled_unreliable]], [[feedback_conditional_lock_with_named_fallback]].
