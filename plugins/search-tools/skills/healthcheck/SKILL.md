---
name: healthcheck
description: Check that every tool search-tools needs is installed — the hook dependencies for this OS (tgrep, jq, and cygpath/PowerShell/taskkill on Windows or ps/kill/realpath on Linux and macOS) and the routed search tools (rg, ast-grep, semble).
disable-model-invocation: true
---

# /search-tools:healthcheck

Run:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/healthcheck.sh"
```

Show the output, then one line of interpretation:

- `result: OK` — every hook dependency is present. Mention any `MISSING` routed tool (that search route is unavailable) and any version flagged `reference verified X` (the `search-tools:reference` notes may be stale for it).
- `result: FAIL` — name the missing required tool and its install line. A missing `tgrep` means the SessionStart hook exits silently and no repo is ever served.
