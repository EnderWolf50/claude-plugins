# guards

Codex: add the `EnderWolf50/claude-plugins` marketplace and install `guards@enderwolf50`.
Review its hook in `/hooks` before relying on it. The Codex adapter reuses the Bash guard on
POSIX shells and uses PowerShell's AST on Windows, including quoted executable paths,
compound commands and here-strings. The merge rule is one Node script for both hosts, with its own
tokenizer that reads bash or PowerShell quoting. It inspects literal command names and arguments; dynamic
commands and specialized tool paths are outside its coverage. It is a workflow guard, not a sandbox.

A `PreToolUse` (Bash) hook that denies commands which change more than the agent knows about. Each denial names the narrower command to run instead, so the retry lands on it.

| Denied | Reason given to the agent | Why |
|---|---|---|
| `git add -A`, `--all`, `.`, `:/` | stage the paths you created or changed by name | an agent committed files it did not create: the user's work in progress and other sessions' changes |
| `git commit -a`, `--all`, `-am …` | same, then `git commit` without `-a` | `-a` commits every tracked change, not only the agent's |
| `chezmoi apply --force` with no target | `chezmoi diff <target>`, then `chezmoi apply --force <target>`, per drifted target | a whole-tree force apply overwrote local edits nobody had reviewed |
| `gh pr merge` (`--auto` too), `gh api -X PUT …/pulls/<n>/merge`, `glab mr merge`, `glab api --method PUT …/merge_requests/<n>/merge`, when the head they merge has no review on record; a GraphQL merge, or `xargs` feeding the PR number | run the `code-review` skill on that head; or ask the user, and once they confirm this exact head was reviewed another way, prefix `SHIP_REVIEWED=<sha>`; merge with `gh pr merge <n>` so the head is visible | agents merged pull requests whose final commits nobody had reviewed |
| any `\\` in the command, Claude Code on Windows only | write the program or text to a file with the Write tool, run it by path | the Bash tool turns `\\` into `\` before bash runs the command, inside single quotes and quoted heredocs too |

Passes: `git add <paths>`, `git add -p`, `git commit -m …`, `chezmoi apply` (it prompts on drift), `chezmoi apply --force <target>`, and `chezmoi apply --force --dry-run`.

Every segment of a compound command (`&&`, `||`, `;`, `|`, `&`, subshells) is checked on its own, so `make && git add -A` is denied too. `git -C <dir>`, `git -c k=v` and other global options before the subcommand are skipped. For the git and chezmoi rules, quoted strings and heredoc bodies are data: `git commit -m "fix git add -A"` passes. The `\\` rule looks at the whole command, since the Bash tool halves it everywhere; it keys on `uname -s`, so a `bash` on PATH that reports `Linux` (WSL's `bash.exe`) skips it. Needs `bash` and `jq`; the merge rule needs `node`.

You can still run any of these yourself with `!` in the prompt; the hook only sees the agent's Bash tool calls.

## Install

```
claude plugin marketplace add EnderWolf50/claude-plugins
claude plugin install guards@enderwolf50
```

## Test

```
bash plugins/guards/tests/bash-guard.sh
node --test plugins/guards/tests/merge-guard.test.js
```

The merge rule (`scripts/merge-guard.js`, Node) looks the head SHA up with `gh pr view` / `glab mr view` (or the API for an API merge), so it needs `node` and those CLIs logged in; a failed lookup is denied with its error, and all lookups share a 25 s budget inside the 30 s hook timeout. It runs on the Bash and PowerShell tools, finds `gh`/`glab` anywhere in a segment (after `command`, `sudo`, `then`, `{`, …) and inside `bash -c` / `pwsh -c` scripts, follows `cd` before the merge, and skips heredoc bodies. The attestation is text the agent writes: the rule names the head and tells it to ask the user first, but it cannot tell whether the user did. The record is `$(git rev-parse --git-common-dir)/reviewed-heads`, one `<sha> <date> <who>` per line, shared by every worktree and never committed.
