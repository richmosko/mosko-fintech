---
name: sourcing-a-credential-file-is-code-execution
description: A credential file read with `source`/`.` is a code-execution channel, and the leak comes from the interpreter's own error message — so no-echo discipline inside the script cannot prevent it.
metadata:
  type: feedback
---

**`source`/`.` on a credential file is not a data read. It is `bash -c` over the file.** A bare value
with no `NAME=` prefix is executed as a command word, and **bash itself prints it** in
`file: line 1: <value>: command not found`. The disclosure came from the interpreter, not from any
`echo` in the script — which is why every no-echo control we had was irrelevant.

**Why:** this was the third credential-into-transcript instance in one workstream, and all three came
from a path that had **never been executed once** before it ran against a real secret. The writer and
the reader had agreed *in source* for weeks; nothing exercised the agreement against the box's actual
file until the first live fire. Sinks were the operator's terminal, the agent transcript on their Mac,
and the SSH stderr channel.

**How to apply:**
- **Read by name, never source**: `grep -m1 "^NAME=" file | cut -d= -f2-` inside `$( )`. Command
  substitution captures stdout and nothing evals it, so a value containing `$(...)`, backticks or `;`
  is inert. **Then check the CONSUMER** — that is the half that re-opens it: an unquoted expansion, an
  `eval`, or interpolation into an `ssh`/`sh -c` string hands the value to a shell after all. Verify the
  consumer quotes it and stays local. See [[credential-in-host-argv-and-the-named-vehicle]].
- **Rotation discharges the disclosure, not the class.** Say both. The class closes in the reader.
- **Rotate in the right ORDER**: revoke now, fix, deploy the fix to the box, *then* mint. Rotating first
  burns the new secret on the next run of the unfixed reader.
- **Grade the class tree-wide, not the two named files** — grep every script for `source`/`.` of any
  file, and for a lingering `set -a` block.
- **A read-back assertion in the WRITER is not the fence**: it asserts the writer's output and cannot
  fail when the reader regresses to `source`. Require a fence over the reader plus a negative control
  (old malformed shape → fails closed with a named error; new shape → reads).
- **Standing requirement**: any new read path for a real credential gets one dry run against a **dummy
  value of the same shape** before its first live read.
