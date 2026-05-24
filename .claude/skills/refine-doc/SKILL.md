---
name: refine-doc
description: Reads `docs/<DOC>/comments.md` (an in-process review sidecar — gitignored), addresses each per-section comment in the corresponding HTML doc, and removes the addressed comments from the sidecar as it goes. Use after reviewing a doc in the browser and jotting feedback into the sidecar. Composable with `/start-doc-update` → `/finish-doc-update` for landing the doc changes. Takes the doc name as argument: PRD, ARCH, or SECURITY.
---

# refine-doc

Walks a doc's `comments.md` sidecar and applies each comment to the matching `<section>` of the HTML doc.

mosko-fintech adaptation of `richmosko/project_template`'s `/refine-doc` per [ADR-010](../../../DECISIONS.md#adr-010). Differences from template:

- **Section-ID examples** use mosko's `sec-N` + `appendix-X` scheme rather than template's semantic IDs (`goals`, `non-goals`, etc.). Behavior unchanged — IDs are read from the DOM at runtime.
- **No `/merge-pr` reference** in the suggested PR flow. mosko merges via the GitHub UI or `gh pr merge`.

## Inputs

- `$ARGUMENTS` — the doc name (`PRD`, `ARCH`, or `SECURITY`). Case-sensitive. Required.

## The `comments.md` format

Comments live in `docs/<DOC>/comments.md` (gitignored). Each comment block is an H2 with a `§<section-id>` anchor pointing at a `<section id="...">` in the corresponding `docs/<DOC>/index.html`:

```markdown
# PRD Comments

Working notes for review of `docs/PRD/index.html`. Comments are removed when
`/refine-doc` addresses them.

---

## §sec-1

The vision paragraph reads as too solo-focused — pull forward the
"replaces existing spreadsheet workflow" framing from Appendix A.

Also: is the "what success looks like at 30 days" framing strong enough,
or should we replace with the M0 / M1 gate language from MILESTONES?

## §sec-6

Should "mobile-native app" stay as a permanent non-goal, or be re-classified
as V2+ trajectory? See ADR-002 §3.0 — feels worth re-examining.
```

- Section IDs are the existing `id="..."` attributes on `<section>` elements in the HTML doc. In mosko's PRD: `sec-overview`, `sec-1` … `sec-8`, `appendix-a` … `appendix-c`. In `docs/SECURITY/index.html`: similar `sec-N` scheme.
- The `§` prefix marks an H2 as a section reference (vs. regular markdown headings the user may have for their own structure — those are ignored by this skill).
- Free-form markdown allowed under each H2: paragraphs, lists, code blocks, blockquotes.
- Multiple comments to the same section can be stacked H2s with the same anchor, or paragraphs under one H2. Both are handled.

## Steps

### 1. Pre-flight

- Verify `$ARGUMENTS` is one of `PRD`, `ARCH`, `SECURITY`. **Bail** with usage hint otherwise.
- Verify `docs/<DOC>/index.html` exists. **Bail** if missing.
- Read `docs/<DOC>/comments.md`. If the file doesn't exist or contains no `## §...` blocks, **bail** with: "No comments to refine in `docs/<DOC>/comments.md` — write some `## §<section-id>` blocks first."

### 2. Parse the sidecar

Extract `(section-id, comment-body)` pairs from the file. Use a regex that matches H2s of the form `^## §([a-z][a-z0-9-]*)\s*$` and captures everything up to the next `## §` H2 (or EOF) as the comment body.

Preserve the file's preamble (anything before the first `## §`) and any unrelated H2s (those without the `§` prefix) — they'll be written back unchanged in step 5.

### 3. Validate section IDs against the HTML doc

For each parsed section-id, verify a matching `<section id="<id>">` exists in `docs/<DOC>/index.html`. Collect unknowns into a list — don't fail; report them in step 6.

### 4. Address each comment, in file order

For each `(section-id, comment-body)` pair where the section exists:

- Read the `<section>` block from the HTML doc.
- Read the comment carefully. Determine the intent:
  - **Content edit** — add/refine/remove prose, table rows, list items.
  - **Structural change** — add a subsection, add a Mermaid diagram, restructure a table.
  - **Needs Founder/CTO clarification** — the comment asks an open question the lead can't answer without owner input (e.g., "Should we support self-hosted?"). In this case, **do not edit the section**; mark the comment as deferred (see below).
- Apply the change in place using `Edit`. Preserve the section's `id` attribute, hint paragraph, and any structural elements (Mermaid diagrams, tables, etc.) unless the comment explicitly asks to change them.
- Record the outcome: `addressed` or `deferred (needs clarification: <reason>)`.

When a single section has multiple comments stacked, address them in source order. Each one's edit lands before the next is read, so later comments see the updated section.

### 5. Rewrite `comments.md`

- **Addressed** blocks are removed from the file.
- **Deferred** blocks remain in place, with a one-line annotation appended after the block's body:
  ```
  > [refine-doc deferred YYYY-MM-DD]: <one-line reason from step 4>
  ```
  (Use the absolute current date.)
- **Unknown-section** blocks remain in place, with a one-line annotation:
  ```
  > [refine-doc unknown-section YYYY-MM-DD]: §<id> not found in docs/<DOC>/index.html — check the section ID, or update the HTML to add it.
  ```
- Preamble and non-`§` H2 blocks are preserved unchanged.
- If after removals/annotations the file is effectively empty (only preamble + horizontal rule), leave the preamble in place so the next review cycle has a starting structure.

### 6. Report

Print a summary to the user:

```
/refine-doc <DOC> — summary

Addressed (<N>):
  §sec-1          — pulled forward "replaces spreadsheet workflow" framing;
                    swapped 30-day language for M0/M1 gate phrasing
  §sec-3          — tightened metric 2 wording per comment

Deferred (<M>) — need Founder/CTO input:
  §sec-6          — "mobile-native app permanent non-goal vs V2+ trajectory?"
                    requires a scope decision (touches ADR-002 §3.0)

Unknown sections (<K>):
  §discoverability — not a section in docs/<DOC>/index.html

Next:
  - Review the diff to docs/<DOC>/index.html
  - Answer the deferred questions and re-run /refine-doc <DOC>
  - /finish-doc-update to PR the changes
```

### 7. Suggest commit / PR shape (don't do it)

This skill is **read-and-edit only** — it doesn't commit or push. Compose well with the existing flow:

```
/start-doc-update <doc>-address-review-comments   # create the branch first if not already on one
/refine-doc <DOC>                                  # this skill
/finish-doc-update                                 # commits, pushes, opens PR
# merge via GitHub UI or `gh pr merge --squash <pr#>`
```

Recommended commit / PR title (per mosko convention):

```
docs(<area>): refine <DOC> per review comments
```

Where `<area>` matches the branch prefix area (e.g. `phase/research-*` → `docs(research)`, `meta/*` → `docs(meta)`). PR body should list the addressed sections (from the step-6 summary) so the diff has context.

## Failure modes

- **Missing arg**: bail with `Usage: /refine-doc <PRD|ARCH|SECURITY>`.
- **Invalid arg**: same.
- **No comments file or empty**: bail with a clear "nothing to do" message.
- **HTML doc missing**: bail; suggest the doc hasn't been drafted yet (e.g. `docs/ARCH/index.html` is scaffolded but content lands in Phase 3).
- **All comments target unknown sections**: don't edit anything; just annotate and report.
- **Edit conflict** (Edit tool rejects because surrounding text shifted between reads): catch and re-read; if still failing, leave the comment in place with a `> [refine-doc edit-failed YYYY-MM-DD]: <reason>` annotation so the user can intervene.

## Notes

- `comments.md` is gitignored at `docs/*/comments.md`. Comments are working notes; the resolution is the doc change itself, which lands via PR.
- This skill is **single-shot per file**. It walks the sidecar once and updates it. Re-run after each round of new comments.
- If you want to preserve a comment for historical reference, copy it into `DECISIONS.md` before running `/refine-doc` — once addressed, it's gone from the sidecar.
- The skill does not invent sections. If a comment proposes content that doesn't fit any existing section, defer with a note: "comment proposes new content; consider adding a `<section id="...">` to the HTML doc first."
- **Pass 1 only:** this skill (the hand-edit authoring path) ships in PR 1 of the comments-sidecar feature port. Pass 2 (browser widget + local server + `/serve-docs` skill) lands in a follow-up PR per [ADR-010](../../../DECISIONS.md#adr-010).
