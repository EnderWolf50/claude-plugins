# search-tools

Keeps a [tgrep](https://github.com/microsoft/tgrep) (trigram-indexed grep) server alive for large repos only while a [Claude Code](https://code.claude.com) session is using them, and ships a reference skill for the search tools Claude routes between: `tgrep`, `ast-grep`, `semble`, `ripgrep`.

Why: on a 13k-file repo a brute-force `tgrep`/`rg` takes ~14 s; against a running `tgrep serve` the same search takes ~40 ms, and the server's file watcher keeps the index fresh. Nobody wants to start and stop that server by hand.

| Hook | Does |
|---|---|
| `SessionStart` | Reaps orphaned servers, then starts `tgrep serve <root>` when the repo has >= 5000 text files or already has a `.tgrep/` |
| `SessionEnd` | Kills every server whose root no other live session has as cwd |

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
- `/search-tools:reap` — sweep unused servers by hand and list what is still running.

## Knobs

| Env | Default | Meaning |
|---|---|---|
| `TGREP_SERVE_MIN_FILES` | `5000` | text-file count (via `tgrep count-files`) above which a repo gets a server |

Opt a smaller repo in by creating `<root>/.tgrep/` (or running `tgrep index <root>` once). The hook adds `.tgrep/` to `.git/info/exclude`, never to the shared `.gitignore`.

## Files

```
.claude-plugin/plugin.json      manifest
hooks/hooks.json                SessionStart start / SessionEnd stop
scripts/tgrep-serve.sh          start | stop | reap
skills/reference/SKILL.md       search-tools:reference
skills/reap/SKILL.md            /search-tools:reap
```

Logs: `$CLAUDE_PLUGIN_DATA/logs/<root>.log`.
