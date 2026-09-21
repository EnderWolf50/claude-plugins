# Changelog

## 1.1.0
- `/search-tools:tgrep on | off | status | reap` replaces `/search-tools:reap`: per-repo opt-in/opt-out (opt-out list in `$CLAUDE_PLUGIN_DATA/opt-out`), and a health check that proves a search from the root hits the server.
- New `PreToolUse` (Bash) hook refuses recursive `grep` (`-r`/`-R`/`--recursive`, also `egrep`/`fgrep`) and points at `rg`; `SEARCH_TOOLS_ALLOW_GREP=1` disables it.
- Data dir default moved to `$CLAUDE_PLUGIN_DATA` (`~/.claude/search-tools` when unset).

## 1.0.0
- Initial release: SessionStart/SessionEnd hooks that run `tgrep serve` for large repos and reap servers no live session uses; `search-tools:reference` and `/search-tools:reap` skills.
