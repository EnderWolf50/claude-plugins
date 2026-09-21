# search-tools

Keeps a [tgrep](https://github.com/microsoft/tgrep) (trigram-indexed grep) server alive for large repos only while a [Claude Code](https://code.claude.com) session is using them, and ships a reference skill for the search tools Claude routes between: `tgrep`, `ast-grep`, `semble`, `ripgrep`.

Why: on a 13k-file repo a brute-force `tgrep`/`rg` takes ~14 s; against a running `tgrep serve` the same search takes ~40 ms, and the server's file watcher keeps the index fresh. Nobody wants to start and stop that server by hand.

| Hook | Does |
|---|---|
| `SessionStart` | Reaps orphaned servers, then starts `tgrep serve <root>` when the repo is opted in (`.tgrep/` exists) or has >= 5000 text files and is not opted out |
| `SessionEnd` | Kills every server whose root no other live session has as cwd |
| `PreToolUse` (Bash) | Refuses `grep -r` / `-R` / `--recursive` (also `egrep`/`fgrep`) with a one-line reason pointing at `rg`; stream filters (`cmd \| grep x`), `git grep`, `rg`, `tgrep`, `ast-grep` pass. `SEARCH_TOOLS_ALLOW_GREP=1` disables it |

"Live session" = a `~/.claude/sessions/<pid>.json` whose pid is in the process table, so a killed terminal or a crash never pins a server: the next session start or end anywhere reaps it. Killing is safe — `tgrep serve` reconciles the on-disk index against the tree on restart.

Windows only (Git Bash, `tasklist`/`taskkill`, PowerShell CIM). Needs `tgrep`, `jq` and Git Bash on `PATH`; silently does nothing when `tgrep` is missing.

## Install

```
claude plugin marketplace add EnderWolf50/claude-plugins
claude plugin install search-tools@enderwolf50
```

Or, from a local checkout: `claude --plugin-dir D:\claude-search-tools`.

Then add the routing to your `~/.claude/CLAUDE.md` (the plugin owns the machinery, you own the policy):

```markdown
## Code search

Route by what the question asks for:

| Ask | Tool |
|---|---|
| **Intent** — where is X implemented, how does Y work | semble (`mcp__semble__search`; CLI `semble search "<query>" <repo>`) |
| **Literal** — every occurrence of a string or regex, all callers of a symbol | `rg`. Large repo (this plugin runs `tgrep serve` for it): `tgrep` from `<root>` with the same flags |
| **Shape** — a construct with variable parts (`foo($$$ARGS)`), a mechanical rewrite | `ast-grep run -p '<pattern>' -l <lang>`; `-r '<fix>'` shows a diff, `-U` applies it |

Before the first `tgrep` or `ast-grep` call in a session, load the `search-tools:reference` skill.
```

## Skills

- `search-tools:reference` (model-invoked) — flags and gotchas: why a search brute-forced, `$$$` metavariables, `-r` vs `-U`, semble `content=` modes.
- `/search-tools:tgrep [on | off | status | reap]` — `on` opts the current repo in (builds the index, serves now, any size); `off` opts it out (stops the server, deletes `.tgrep/`, skipped on every session start until `on`); `status` (default) is the health check: policy, server state, whether a search from the root actually hits the server, log tail, every server on the machine; `reap` sweeps servers no live session uses.

## Knobs

| Env | Default | Meaning |
|---|---|---|
| `TGREP_SERVE_MIN_FILES` | `5000` | text-file count (via `tgrep count-files`) above which a repo gets a server |

Opt-in / opt-out state: `<root>/.tgrep/` present = in; a line in `$CLAUDE_PLUGIN_DATA/opt-out` = out (wins). `/search-tools:tgrep on|off` maintains both. The hook adds `.tgrep/` to `.git/info/exclude`, never to the shared `.gitignore`.

## Files

```
.claude-plugin/plugin.json      manifest
hooks/hooks.json                SessionStart / SessionEnd / PreToolUse(Bash)
scripts/tgrep-serve.sh          start | stop | on | off | status | reap
scripts/no-recursive-grep.sh    PreToolUse guard
skills/reference/SKILL.md       search-tools:reference
skills/tgrep/SKILL.md           /search-tools:tgrep
```

Logs: `$CLAUDE_PLUGIN_DATA/logs/<root>.log`. Opt-outs: `$CLAUDE_PLUGIN_DATA/opt-out`.
