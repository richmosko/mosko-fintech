---
name: mermaid-semicolon-terminates-inside-quotes
description: Mermaid gotchas in the vendored 11.15.0 runtime — `;` terminates a statement even inside quoted labels — plus how to RENDER-verify a block (edge ids, error-icon, local HTTP server) and why a direction fix is never just the diagram.
metadata:
  type: reference
---

The vendored `docs/_assets/mermaid.min.js` lexes `;` as a **statement separator before quoting is applied**. So this is a syntax error, not a label:

    Note over DB: "RLS applies; auth.uid() is the tenant"

The whole diagram fails with a bomb graphic reading **"Syntax error in text"** and a version number — **no line number in the visible output**, and the surrounding prose renders fine, so the page looks 95% correct.

**Measured 2026-09-05 (ARCH §3.2, SELF-345).** The parser message, obtained only via a harness, was *"Parse error on line 10: …applies; auth.uid() is the tenant" DB- … Expecting 'SOLID_OPEN_ARROW', …"* — i.e. it had already closed the statement at the `;` and was trying to read the rest of the string as a new arrow. An inner `:` in a message is a second, weaker suspect; removing both is cheapest.

**Get the real error instead of bisecting by guess.** `read_console_messages` returned nothing for this page even after a reload. What worked was a throwaway harness that loads the vendored runtime and puts the error in `document.title`, then reading the title from `tabs_context_mcp`:

```html
<script src="/docs/_assets/mermaid.min.js"></script>
<script>
mermaid.initialize({startOnLoad:false});
mermaid.parse(SRC).then(()=>document.title="PARSE_OK")
  .catch(e=>document.title="PARSE_ERR "+String(e.str||e.message));
</script>
```

Extend it to loop over **every** `<pre class="mermaid">` block in the file and report the failing indices — one page load then covers the whole document, which is what caught that a second diagram was also affected.

**How to apply.**
- Keep `;` and inner `:` out of mermaid label/Note/message text entirely. Use a comma or an em dash.
- ⚠ A literal `#` is written `#35;` — **no leading ampersand**. That is mermaid's own entity syntax and it renders as `#`. Do not "fix" it to `&#35;` (which is correct in the surrounding HTML prose but wrong inside the block) and do not strip it to a bare `#`.
- Participant labels written `participant X as "Label"` render **with the quotes visible**. That is this file's established house style; leave it rather than restyling.
- **Always render the page after editing a diagram** ([[feedback_body_gate_rendered_extract]]) — a mermaid defect is invisible to `grep`, to a diff, and to every SQL/HTML lint.

⚠ Related trap from the same session: extracting "the diagram" with a content regex grabbed the **wrong block** (an overview flowchart that also mentioned the same participants). Filter on `startswith('sequenceDiagram')`, not on words in the body — and see [[feedback_the_fence_scans_the_prose_about_the_fence]] for the general shape.

---

## Render-verifying a block: read back the STRUCTURE, not the source (2026-09-05)

`mermaid.parse` only proves **syntax**. To assert a block actually says what you
meant — e.g. that an edge was reversed — call `mermaid.render` and read the **emitted
edge ids** (`L_app_pdf_0`, `L_webend_pdfend_0`); the id encodes source→target, so it
is a direction assertion rather than a re-reading of the text you just wrote. Also
check for `.error-icon` in the returned SVG: mermaid renders an error *graphic*
rather than throwing, so a "successful" render can still be a failure.

**Harness that works here:** copy the vendored `docs/_assets/mermaid.min.js` into the
scratchpad, write a page that renders each extracted block, and serve it with
`python3 -m http.server <port>` — ⚠ **`file://` navigation is refused by the Chrome
MCP**, so a local HTTP server is required. Read results out of `document.title` (set
it from the script) or via `javascript_tool`.

⚠ **Extract blocks by `<pre class="mermaid">` and filter on the FIRST LINE**
(`flowchart`, `sequenceDiagram`), never by a content regex — a content match grabbed
the wrong block once and hid a third stale site.

## A direction is not a diagram — the sweep this belongs to

When a ruling reverses a direction, the drawing is the most **visible** carrier, not
the only one. Amending ARCH §3.2's diagram left **twelve** other sites asserting the
superseded PDF-worker direction (a second Mermaid edge, four prose sentences, three
table cells, a route row, an interface row, a container row); a Sec review named
seven, and the rest surfaced only by grepping **the identifier** — the endpoint path
— rather than the prose. Treat a reviewer's list of sites as a **lower bound**.
