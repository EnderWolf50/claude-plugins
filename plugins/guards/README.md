# guards

A `PreToolUse` (Bash) hook that denies commands which change more than the agent knows about. Each denial names the narrower command to run instead, so the retry lands on it.

| Denied | Reason given to the agent | Why |
|---|---|---|
| `git add -A`, `--all`, `.`, `:/` | stage the paths you created or changed by name | an agent committed files it did not create: the user's work in progress and other sessions' changes |
| `git commit -a`, `--all`, `-am …` | same, then `git commit` without `-a` | `-a` commits every tracked change, not only the agent's |
| `chezmoi apply --force` with no target | `chezmoi diff <target>`, then `chezmoi apply --force <target>`, per drifted target | a whole-tree force apply overwrote local edits nobody had reviewed |

Passes: `git add <paths>`, `git add -p`, `git commit -m …`, `chezmoi apply` (it prompts on drift), `chezmoi apply --force <target>`, and `chezmoi apply --force --dry-run`.

Every segment of a compound command (`&&`, `||`, `;`, `|`, `&`, subshells) is checked on its own, so `make && git add -A` is denied too. `git -C <dir>`, `git -c k=v` and other global options before the subcommand are skipped. Quoted strings and heredoc bodies are data: `git commit -m "fix git add -A"` passes. Needs `bash` and `jq`.

You can still run any of these yourself with `!` in the prompt; the hook only sees the agent's Bash tool calls.

## Install

```
claude plugin marketplace add EnderWolf50/claude-plugins
claude plugin install guards@enderwolf50
```

## Test

```
bash plugins/guards/tests/bash-guard.sh
```
