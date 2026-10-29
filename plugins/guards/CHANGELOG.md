# Changelog

## 2.1.0
- New `scripts/powershell-guard.sh`, a `PreToolUse` hook on the PowerShell tool for Claude Code: denies a bash heredoc (`<<EOF`, `<<'EOF'`, `<<-EOF`) in a PowerShell command, pointing at a PowerShell here-string (closing `'@` at column 0) or a script file written with the Write tool. Here-string bodies and quoted strings are data. New `tests/powershell-guard.sh`, run in CI. The Codex adapter is unchanged.

## 2.0.0
- Removed `scripts/merge-guard.js` and its tests: a PR merge no longer waits for a recorded code review. `SHIP_REVIEWED` and `reviewed-heads` are no longer read.

## 1.3.0
- New `scripts/merge-guard.js`, a `PreToolUse` hook on the Bash and PowerShell tools for Claude Code and on Codex's shell: `gh pr merge` (with `--auto` too), `gh api -X PUT …/pulls/<n>/merge`, `glab mr merge` / `accept` and `glab api --method PUT …/merge_requests/<n>/merge`, wherever they sit in a segment, after a global `-R`, or inside `bash -c` / `pwsh -c` / `eval` / `iex`, look up the head they would merge and pass only when that SHA is in `<git common dir>/reviewed-heads` (the `code-review` skill's patch appends it once a review leaves nothing to fix) or the command attests it with `SHIP_REVIEWED=<sha>` (`$env:SHIP_REVIEWED='<sha>'` in PowerShell) after the user confirmed a review done another way. A record or attestation of an older head does not cover new commits. A GraphQL merge (in the command or in the query file it reads), `xargs` feeding the PR number and a `gh alias set` that merges hide the head and are denied. The lookup runs where the command does (after `cd` / `Set-Location`) with the command's own variables (`GH_REPO`). New `tests/merge-guard.test.js`, run in CI.

## 1.2.0
- Deny a Bash command containing `\\` on Windows (Git Bash, MSYS, Cygwin): Claude Code's Bash tool turns it into `\` before bash runs the command, even inside single quotes and quoted heredocs. The reason points at writing the program to a file and running it by path. The Codex adapter is exempt: `codex.js` sets `GUARDS_HOST=codex` for both its bash and pwsh paths.

## 1.1.0
- Codex plugin manifest and hook adapter. Windows unified exec is parsed with PowerShell AST; POSIX shells reuse the existing Bash guard. No hook trust is granted automatically.

## 1.0.0
- `PreToolUse` (Bash) guard. Denies `git add -A` / `--all` / `.` / `:/` and `git commit -a` / `--all` (also clustered, `-am`), pointing at staging the changed paths by name; and `chezmoi apply --force` without a target, pointing at `chezmoi diff <target>` then `chezmoi apply --force <target>`. Every segment of a compound command is checked, `git -C <dir>` and other global options are skipped, quoted strings and heredoc bodies are data. New `tests/bash-guard.sh`, run in CI.
