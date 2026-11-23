# guards

Codex: add the `EnderWolf50/claude-plugins` marketplace and install `guards@enderwolf50`.
Review its hook in `/hooks` before relying on it. The Codex adapter reuses the Bash guard on
POSIX shells and uses PowerShell's AST on Windows, including quoted executable paths,
compound commands and here-strings. It inspects literal command names and arguments; dynamic
commands and specialized tool paths are outside its coverage. It is a workflow guard, not a sandbox.

The Codex adapter applies the git, chezmoi and kill rules and adds them to the context at `SessionStart` and `SubagentStart`; the `\\` rewrite and the heredoc rule are Claude Code only.

A `PreToolUse` hook on the Bash tool that denies commands which change more than the agent knows about. Each denial names the narrower command to run instead, so the retry lands on it.

| Denied | Reason given to the agent | Why |
|---|---|---|
| `git add -A`, `--all`, `.`, `:/` | stage the paths you created or changed by name | an agent committed files it did not create: the user's work in progress and other sessions' changes |
| `git commit -a`, `--all`, `-am …` | same, then `git commit` without `-a` | `-a` commits every tracked change, not only the agent's |
| `chezmoi apply --force` with no target | `chezmoi diff <target>`, then `chezmoi apply --force <target>`, per drifted target | a whole-tree force apply overwrote local edits nobody had reviewed |
| `taskkill /IM` (`//IM`, `-IM`), `pkill`, `killall` | find the PID (`pgrep -af <pattern>`, or `Get-CimInstance Win32_Process` with a `CommandLine` filter), check it, then `kill <pid>` / `Stop-Process -Id` / `taskkill /PID` | a kill by name also stops the user's own processes and other sessions' servers of that name |

On Windows, in Claude Code only, a command containing `\\` is rewritten rather than denied: the Bash tool turns `\\` into `\` before bash runs the command, inside single quotes and quoted heredocs too. The hook sees the command as the agent wrote it, writes it byte for byte to `$TMPDIR/claude-guards/cmd.XXXXXX` and hands the tool `source '<file>'` instead (`updatedInput`, other fields kept), with a note in the agent's context naming the file. `source` runs the file in the tool's own shell, from the same directory, so a `cd` in it carries over as it would have. The rewrite leaves the permission decision to the normal flow, so your allow and ask rules see `source '<file>'`, not the command inside. A deny rule in the same command still wins, and if the file cannot be written the command is denied with the old reason (write it to a file with the Write tool, run it by path). Files older than a day are deleted on the next rewrite. If search-tools also rewrites the same command (a `grep -r` with a `\\`), which rewrite runs is up to Claude Code.

A second `PreToolUse` hook, on the PowerShell tool (Claude Code only), denies a bash heredoc (`<<EOF`, `<<'EOF'`, `<<-EOF`): PowerShell has no such syntax, so the command failed to parse or ran the body as commands. The reason points at a PowerShell here-string (`@'` ... `'@`, the closing `'@` at column 0) or a script file written with the Write tool. It also denies a kill by name: `Stop-Process -Name` (or `-ProcessName`, abbreviated, `-Name:x`, and the `kill` and `spps` aliases), `taskkill /IM`, `pkill` and `killall`. Quoted strings (also across lines), comments and here-string bodies are data.

A `SessionStart` hook (`startup`, `resume`, `clear`, `compact`) and a `SubagentStart` hook add the rules to the agent's context up front, one positive line each: stage by path, give `chezmoi apply --force` a target, kill by PID and, on Windows, the `\\` rewrite and the PowerShell here-string. The text, here and in every denial, comes from `scripts/rules.json`.

Passes: `git add <paths>`, `git add -p`, `git commit -m …`, `chezmoi apply` (it prompts on drift), `chezmoi apply --force <target>`, `chezmoi apply --force --dry-run`, `kill <pid>`, `taskkill /PID <pid>` and `Stop-Process -Id <pid>`.

Every segment of a compound command (`&&`, `||`, `;`, `|`, `&`, subshells) is checked on its own, so `make && git add -A` is denied too. `git -C <dir>`, `git -c k=v` and other global options before the subcommand are skipped. For the deny rules, quoted strings and heredoc bodies are data: `git commit -m "fix git add -A"` passes. The `\\` rewrite looks at the whole command, since the Bash tool halves it everywhere; it keys on `uname -s`, so a `bash` on PATH that reports `Linux` (WSL's `bash.exe`) skips it. Needs `bash` and `jq`.

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
bash plugins/guards/tests/session-context.sh
python .github/test-codex.py
```
