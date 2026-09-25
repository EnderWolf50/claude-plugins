# Changelog

## 1.3.2
- `/search-tools:healthcheck`: checks the hook dependencies for the current OS and the routed tools (`rg`, `ast-grep`, `semble` and its MCP server), prints an install line for anything missing, and flags versions that differ from the ones the reference skill was verified against. Exits 1 when a hook dependency is missing.
- `/search-tools:tgrep on` no longer exits 1 when the server it just spawned has not registered yet.

## 1.3.1
- Fix: 1.3.0's session-file guard stopped all reaping for good as soon as one session file was unreadable. Now only a *blocking session file* stops it: a live pid whose `cwd` cannot be read, or no readable pid and modified within a day. A dead session's broken file and day-old leftovers are ignored. An empty or truncated file no longer hides the others (each file is parsed on its own).
- `/search-tools:tgrep status` ends with `reap: OK` or `reap: blocked by …` (the blocking file and why, no session files, or a jq failure).
- A session ending never blocks its own reap: its file is left out before any check.
- `logs/reap.log` keeps its last 100 lines.

## 1.3.0
- Linux and macOS support. `$OSTYPE` picks the process snapshot (`ps` instead of PowerShell), `kill` instead of `taskkill`, and path normalization: symlinks resolved on both (Claude Code stores the physical cwd), case folded on macOS and Windows only. Background work (the SessionEnd reap, `tgrep serve`) starts under `setsid` where available. macOS is verified in CI only.
- Safety: when the session files look unreadable (no sessions dir, no file, a file without `pid` or `cwd`, broken JSON), nothing is reaped and `logs/reap.log` gets a line. Before, an unreadable sessions dir made every server an orphan.
- CI: `tests/orphans.sh` on Ubuntu, macOS and Windows.

## 1.2.3
- Fix: reaping killed servers whose root was in use. Windows `jq` ends lines with CRLF, so every session cwd but the last carried a trailing CR and never matched its root; a session start or end anywhere then killed the server of any other open repo unless its session file happened to sort last. The CR is now dropped before matching.
- Internal: the orphan-server decision in `tgrep-serve.sh` is now a pure function (`orphans`: snapshot + live sessions in, orphan servers out), and `off` stops its root's servers without consulting sessions. No behaviour change. New `tests/orphans.sh` pins the decision.

## 1.2.2
- SessionEnd hook no longer shows `Hook cancelled`: SessionEnd hooks share a 1.5 s budget (the plugin `timeout` does not raise it) and `stop` took ~3 s. It now parses stdin without forks and reaps in a detached `reap <session-id>`, returning in ~0.1 s. Sessions ending in the home directory now reap too.

## 1.2.1
- Guard narrowed back to what costs time: recursive grep and `xargs grep`. grep on a single file or a stream passes again (1.2.0 refused every grep that read a file).

## 1.2.0
- The Bash guard now refuses every `grep` that reads files (anything not directly after a pipe: `grep x file`, `xargs grep`, `if grep -q`), not only recursive ones; `cmd | grep x` still passes. Script renamed `grep-guard.sh`.

## 1.1.0
- `/search-tools:tgrep on | off | status | reap` replaces `/search-tools:reap`: per-repo opt-in/opt-out (opt-out list in `$CLAUDE_PLUGIN_DATA/opt-out`), and a health check that proves a search from the root hits the server.
- New `PreToolUse` (Bash) hook refuses recursive `grep` (`-r`/`-R`/`--recursive`, also `egrep`/`fgrep`) and points at `rg`; `SEARCH_TOOLS_ALLOW_GREP=1` disables it.
- Data dir default moved to `$CLAUDE_PLUGIN_DATA` (`~/.claude/search-tools` when unset).

## 1.0.0
- Initial release: SessionStart/SessionEnd hooks that run `tgrep serve` for large repos and reap servers no live session uses; `search-tools:reference` and `/search-tools:reap` skills.
