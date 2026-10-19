# Changelog

## 1.3.0
- New `scripts/merge-guard.js`, a second `PreToolUse` (Bash) hook for Claude Code and Codex: `gh pr merge` (with `--auto` too), `gh api …/pulls/<n>/merge`, `glab mr merge` and `glab api …/merge_requests/<n>/merge` look up the head they would merge and pass only when that SHA is in `<git common dir>/reviewed-heads` (the `code-review` skill's patch appends it once a review leaves nothing to fix) or the command attests it with `SHIP_REVIEWED=<sha>` (`$env:SHIP_REVIEWED='<sha>'` in PowerShell) after the user confirmed a review done another way. A record or attestation of an older head does not cover new commits. New `tests/merge-guard.test.js`, run in CI.

## 1.2.0
- Deny a Bash command containing `\\` on Windows (Git Bash, MSYS, Cygwin): Claude Code's Bash tool turns it into `\` before bash runs the command, even inside single quotes and quoted heredocs. The reason points at writing the program to a file and running it by path. The Codex adapter is exempt: `codex.js` sets `GUARDS_HOST=codex` for both its bash and pwsh paths.

## 1.1.0
- Codex plugin manifest and hook adapter. Windows unified exec is parsed with PowerShell AST; POSIX shells reuse the existing Bash guard. No hook trust is granted automatically.

## 1.0.0
- `PreToolUse` (Bash) guard. Denies `git add -A` / `--all` / `.` / `:/` and `git commit -a` / `--all` (also clustered, `-am`), pointing at staging the changed paths by name; and `chezmoi apply --force` without a target, pointing at `chezmoi diff <target>` then `chezmoi apply --force <target>`. Every segment of a compound command is checked, `git -C <dir>` and other global options are skipped, quoted strings and heredoc bodies are data. New `tests/bash-guard.sh`, run in CI.
