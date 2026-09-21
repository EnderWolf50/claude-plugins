---
name: reference
description: Flags and gotchas for tgrep, ast-grep, semble and ripgrep. Load before the first tgrep or ast-grep call in a session, or when a tgrep search unexpectedly brute-forces or reports 0 matches.
---

# Search tools — reference

Routing (which tool for which ask) lives in your `CLAUDE.md`; this file holds what `--help` does not confess. Versions verified 2026-09-21.

## tgrep 1.0.9 — trigram-indexed ripgrep

- Flags mirror `rg` (`-i -w -F -g -t -A/-B/-C -l -c -o --json --vimgrep -P`): keep the command, swap the binary.
- `tgrep serve <root>` builds the index itself and keeps it fresh with a file watcher. This plugin's hooks manage it: `start` (SessionStart) serves any repo with >= 5000 text files or an existing `.tgrep/` (override: `TGREP_SERVE_MIN_FILES`); `stop` (SessionEnd) and every `start` reap servers whose root no live session has as cwd, so a killed terminal or crash leaves nothing behind past the next session. `/search-tools:tgrep status` is the health check, `on`/`off` opt a repo in or out, `reap` sweeps by hand. Logs: `$CLAUDE_PLUGIN_DATA/logs/`.
- Index lives in `<root>/.tgrep`; the hook adds `.tgrep/` to `.git/info/exclude`.
- The index is found only when the search runs **from `<root>`** (or with `--index-path <root>/.tgrep`). From a subdirectory it silently brute-forces — `--stats` says "Brute-force search" when that happened; scope with `-g 'sub/**'` from the root instead.
- Without a server the index is a snapshot: files written after `tgrep index` are invisible until the next `tgrep index <root>`. `tgrep status <root>` shows whether a server (watcher) is up.

## ast-grep 0.45.1 (alias `sg`) — structural search and rewrite

- A pattern is a valid snippet of the target language. `$NAME` matches one node; `$$$NAME` matches zero or more (arguments, statements).
- `-l <lang>` when the tree mixes languages or the pattern alone is ambiguous; otherwise inferred from the file extension.
- `-r '<fix>'` prints a diff and writes nothing; `-U` (`--update-all`) applies it. Metavariables carry over into the fix.
- Single-quote the pattern in Bash and PowerShell so `$` survives.
- Context a snippet cannot express (`inside`, `has`, `kind`, `not`) goes in a YAML rule: `ast-grep scan --inline-rules '<yaml>'` for a one-off, `sgconfig.yml` + `ast-grep scan` for a kept rule, `ast-grep test` to check it.
- `ast-grep outline <path>` lists symbols, imports, exports and members — a file's shape without reading it.
- `--json=stream` for machine-readable output.

## semble 0.6.0 — semantic search

- MCP: `mcp__semble__search(query, repo, content?)`, `mcp__semble__find_related(file_path, line, repo, content?)`. `repo` is the project root, or an explicit https URL for a remote repo.
- CLI: `semble search "<query>" <repo> [--content docs|config|all] [--top-k N] [--max-snippet-lines N]`; `semble find-related <file> <line> <repo>`.
- Hits carry ~10 lines of context (signature + first body lines): enough to confirm the location and go read there.

## ripgrep 15.2.0

- The built-in Grep tool is ripgrep. Call `rg` directly in Bash for the flags the tool hides (`--files`, `--replace`, `-U`, `--stats`).
- A tree search from Bash is `rg -n <pattern> [path]`; this plugin's PreToolUse hook refuses `grep -r` so the retry lands on `rg`. Stream filters (`cmd | grep x`) pass.
