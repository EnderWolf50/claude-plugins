# Changelog

## 1.2.0
- Deny a Bash command containing `\\` on Windows (Git Bash, MSYS, Cygwin): Claude Code's Bash tool turns it into `\` before bash runs the command, even inside single quotes and quoted heredocs. The reason points at writing the program to a file and running it by path. The Codex adapter is exempt (`GUARDS_PLATFORM=codex`).

## 1.1.0
- Codex plugin manifest and hook adapter. Windows unified exec is parsed with PowerShell AST; POSIX shells reuse the existing Bash guard. No hook trust is granted automatically.

## 1.0.0
- `PreToolUse` (Bash) guard. Denies `git add -A` / `--all` / `.` / `:/` and `git commit -a` / `--all` (also clustered, `-am`), pointing at staging the changed paths by name; and `chezmoi apply --force` without a target, pointing at `chezmoi diff <target>` then `chezmoi apply --force <target>`. Every segment of a compound command is checked, `git -C <dir>` and other global options are skipped, quoted strings and heredoc bodies are data. New `tests/bash-guard.sh`, run in CI.
