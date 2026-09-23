---
name: tgrep
description: Manage the tgrep server for the current repo — `on` (opt in and serve now), `off` (opt out, stop, drop the index), `status` (health check, default), `reap` (stop servers no session uses).
disable-model-invocation: true
---

# /search-tools:tgrep [on | off | status | reap]

Run, with `status` when no argument was given:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/tgrep-serve.sh" $ARGUMENTS
```

Show the output, then one line of interpretation:

- `status` — say whether searches from this root hit the server (`health: OK` / `DEGRADED` / `no server`), and what the policy line means: `automatic` is decided by the file count against `TGREP_SERVE_MIN_FILES`; `opted in` / `opted out` override it. Every root in the machine-wide list appears twice on Windows (scoop shim + real exe) — normal. `reap: blocked by <file> (<reason>)` means a session file that may belong to a live session cannot be read, so no server is reaped until it is fixed or removed (or, with no readable pid, until it is a day old); name the file and the reason.
- `on` — the repo is now served on every session start regardless of size; the index is at `<root>/.tgrep` (ignored via `.git/info/exclude`).
- `off` — the repo is skipped on every session start until `on`; `tgrep` there brute-forces like `rg`.
- `reap` — list what survived; anything left is in use by a live session.

Health `DEGRADED` with a running server means the search ran from a subdirectory or the index path moved: searches must run from `<root>` (or pass `--index-path <root>/.tgrep`).
