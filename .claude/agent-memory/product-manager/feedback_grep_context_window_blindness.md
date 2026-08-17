---
name: grep-context-window-blindness
description: grep -o '.{N}PATTERN.{N}' silently drops matches within N chars of line start/end — never use fixed-width context windows as a CP9 sweep probe; use bare-pattern grep and filter after
metadata:
  type: feedback
---

Never use `grep -o '.\{N\}PATTERN.\{N\}'` as a completeness probe: the context windows are hard requirements, not up-to, so any match within N chars of a line boundary is structurally invisible — headings and list-item leads (which start near column 0) are exactly the class it drops.

**Why:** 2026-08-17 L1 cash-ruling label sweep — my `grep -o '.\{60\}Cash.\{60\}'` probe returned 11 hits and I filtered them all correctly, but the BACKLOG §7.20 item-1 HEADING (`**1. Seed delta: a "Cash"-labeled…`, match ~20 chars from line start) never appeared in the probe output at all. Team-lead's re-grep on bare quote forms caught it. The instrument could not observe the property ([[instrument-cannot-observe-the-property]] — this is the PM-local instance).

**How to apply:** For any label/identifier sweep (CP9), probe with the bare pattern (`grep -n '"Cash"\|'"'"'Cash'"'"''`) and hand-filter survivors; add context via `-o` only as a *reading* aid on the already-complete hit list, never as the hit list itself. A filtered-clean result from a windowed probe is a claim about the window, not the file.
