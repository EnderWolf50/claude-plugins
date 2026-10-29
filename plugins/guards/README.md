# guards

Codex: add the `EnderWolf50/claude-plugins` marketplace and install `guards@enderwolf50`.
Review its hook in `/hooks` before relying on it. The Codex adapter reuses the Bash guard on
POSIX shells and uses PowerShell's AST on Windows, including quoted executable paths,
compound commands and here-strings. It inspects literal command names and arguments; dynamic
commands and specialized tool paths are outside its coverage. It is a workflow guard, not a sandbox.

A `PreToolUse` hook on the Bash tool that denies commands which change more than the agent knows about. Each denial names the narrower command to run instead, so the retry lands on it.

| Denied | Reason given to the agent | Why |
|---|---|---|
| `git add -A`, `--all`, `.`, `:/` | stage the paths you created or changed by name | an agent committed files it did not create: the user's work in progress and other sessions' changes |
| `git commit -a`, `--all`, `-am …` | same, then `git commit` without `-a` | `-a` commits every tracked change, not only the agent's |
| `chezmoi apply --force` with no target | `chezmoi diff <target>`, then `chezmoi apply --force <target>`, per drifted target | a whole-tree force apply overwrote local edits nobody had reviewed |
| any `\\` in the command, Claude Code on Windows only | write the program or text to a file with the Write tool, run it by path | the Bash tool turns `\\` into `\` before bash runs the command, inside single quotes and quoted heredocs too |

A second `PreToolUse` hook, on the PowerShell tool (Claude Code only), denies a bash heredoc (`<<EOF`, `<<'EOF'`, `<<-EOF`): PowerShell has no such syntax, so the command failed to parse or ran the body as commands. The reason points at a PowerShell here-string (`@'` ... `'@`, the closing `'@` at column 0) or a script file written with the Write tool. Here-string bodies and quoted strings are data.

Passes: `git add <paths>`, `git add -p`, `git commit -m …`, `chezmoi apply` (it prompts on drift), `chezmoi apply --force <target>`, and `chezmoi apply --force --dry-run`.

Every segment of a compound command (`&&`, `||`, `;`, `|`, `&`, subshells) is checked on its own, so `make && git add -A` is denied too. `git -C <dir>`, `git -c k=v` and other global options before the subcommand are skipped. For the git and chezmoi rules, quoted strings and heredoc bodies are data: `git commit -m "fix git add -A"` passes. The `\\` rule looks at the whole command, since the Bash tool halves it everywhere; it keys on `uname -s`, so a `bash` on PATH that reports `Linux` (WSL's `bash.exe`) skips it. Needs `bash` and `jq`.

You can still run any of these yourself with `!` in the prompt; the hook only sees the agent's Bash tool calls.

## Install

```
claude plugin marketplace add EnderWolf50/claude-plugins
claude plugin install guards@enderwolf50
```

## Test

```
bash plugins/guards/tests/bash-guard.sh
bash plugins/guards/tests/powershell-guard.sh
```
