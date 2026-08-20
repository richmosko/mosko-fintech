---
name: reserved-id-range-needs-a-maxvalue
description: Partitioning an id space between two tables by a reserved offset does nothing without a MAXVALUE on the lower sequence — the ranges are disjoint only until the lower one advances into the upper one
metadata:
  type: reference
---

Two `generated always as identity` tables do **not** get disjoint id spaces from an
offset alone. A high `start with` on the upper table and an uncapped lower table are
disjoint *by distance*, not by definition: the lower sequence keeps advancing and will
eventually mint into the reserved range. Sec vetoed exactly this shape once already — two
sequences set past the same union maximum **advance in parallel from the same point**, so
the very next insert on each side mints the same value.

**The construction that works has two halves:**

```sql
-- upper table
id bigint generated always as identity (start with 1000000000 minvalue 1000000000 no cycle)
-- lower table
alter table <lower> alter column id set maxvalue 999999999;   -- the fence
```

Plus, when rows are *moved* into the upper table below its own range with
`overriding system value`, a guard asserting the lower sequence has **already advanced
past the maximum moved id** — otherwise a future lower-table insert re-mints an id a
moved row already holds, and the offset fence cannot see it (both values sit below it).

⚠ **Assert the CONSTRUCTION, never an overlap count.** *"The two id spaces do not
overlap"* is true on a fresh stack because nothing has been inserted — an assertion with
nothing watching what falsifies it. The real leg reads `pg_sequence`:
lower `seqmax` < upper `seqmin`.

⚠ **What this delivers and what it cannot.** It delivers *no id resolves in more than one
table*. It does **not** deliver *"the id names its table without a lookup"* — undeliverable
for ids minted before the partition existed, and a reader designed against the stronger
form is wrong for exactly the historical rows an audit trail exists to serve. Comment the
offset and the cap as SECURITY INVARIANTS: an unexplained magic constant is the first
thing a later simplification removes.

Realized at `084` (the GL split); the hazard it closes is the FK-less audit snapshot at
`031`, which nothing follows and nothing would object to a re-key of.

Related: [[gl-taxonomy-split-ratified]] · [[an-assertion-with-no-watcher]] ·
[[watcher-not-fence-for-by-construction-properties]]
