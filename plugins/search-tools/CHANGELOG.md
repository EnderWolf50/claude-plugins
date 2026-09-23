# Changelog

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
