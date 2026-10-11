# Changelog

## 1.0.0
- When skill S runs, every `S-patch/SKILL.md` found (global `~/.claude/skills`, `~/.agents/skills`, then project `.claude/skills`, `.agents/skills`) is injected as context, frontmatter stripped. Fires on the Skill tool (`PostToolUse`, a `plugin:` prefix dropped) and when you type `/S` (`UserPromptExpansion`, `command_name`). Silent when no patch exists. New `tests/inject.sh`, run in CI.
