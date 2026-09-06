---
name: prove-a-delta-is-comment-string-only
description: To prove a migration edit changed nothing executable, normalize BOTH revisions with SQL string literals, dollar-quoted bodies and -- comments blanked, then diff — and inversion-prove the normalizer against a control edit
metadata:
  type: reference
---

"The delta is comment-only" is a claim about your *reading* of the diff, not about the
file. `git diff` cannot tell a `comment on function` string from executable DDL — both are
just changed lines. Prove it with an instrument instead.

**The instrument.** A ~30-line character-state scanner over the SQL: states `code` / `str`
/ `cmt`; in `str` (opened by `'`, `''` is an escape, closed by a lone `'`) emit only
newlines; in `cmt` (opened by `--`) emit only the closing newline; on `$tag$` in `code`
emit the tag twice and skip to its match, so dollar-quoted bodies collapse. Run it over
`git show HEAD:<file>` and over the worktree file, then `diff`. **Empty ⇒ comment/string-only.**
Line counts stay aligned because newlines are preserved, so a non-empty diff names the line.

**Then inversion-prove the normalizer**, or it is decoration: copy the OLD file, change one
genuinely executable line (a `drop function` signature works well), normalize the copy, and
confirm the diff goes NON-EMPTY and reports that line. A normalizer with an over-greedy
string state blanks the whole file and reports EMPTY for every input — indistinguishable
from success. Also sanity-check that the normalized output is non-empty and materially
shorter than the source (a heavily-commented migration collapsed 74 KB → 4 KB).

**Why:** applied on `111_audit_log.sql` when replacing a paragraph inside a `comment on
function` literal, where Sec's finding required "zero non-comment, non-string lines changed"
as a stated condition, not an assurance.

**How to apply:** any time a migration edit is claimed to be text-only — the `052`
comment-migration shape, a header-block correction, a `comment on` rewrite. Pairs with
[[feedback_catalog_comment_staleness_needs_the_catalog]]: the normalizer proves the SOURCE
delta is inert, and an `obj_description` read on a clean-applied scratch clone proves the
CATALOG actually serves the new text. Both, not either. See also
[[feedback_inversion_test_the_rationale_not_the_presence]].
