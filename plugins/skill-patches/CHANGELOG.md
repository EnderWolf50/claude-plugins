# Changelog

## 2.0.0
- A patch is `S.patch/SKILL.md` (frontmatter `name: S.patch`), was `S-patch`. Rename existing patch directories; `S-patch` is no longer read.

## 1.0.1
- A patch reached through two paths that resolve to one file (`~/.claude/skills/<s>-patch` symlinked to `~/.agents/skills/<s>-patch`) is injected once.

## 1.0.0
- When skill S runs, every `S-patch/SKILL.md` found (global `~/.claude/skills`, `~/.agents/skills`, then project `.claude/skills`, `.agents/skills`) is injected as context, frontmatter stripped. Fires on the Skill tool (`PostToolUse`, a `plugin:` prefix dropped) and when you type `/S` (`UserPromptExpansion`, `command_name`). Silent when no patch exists. New `tests/inject.sh`, run in CI.
