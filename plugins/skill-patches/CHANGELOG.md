# Changelog

## 2.2.1
- Codex MCP patch globs also match server names whose hyphens were normalized to underscores.

## 2.2.0
- Codex hooks inject patches for explicit $skill mentions, observed concrete SKILL.md reads and matching MCP tools. Deduplicate per session/content; compaction resets markers. Keep instruction fallback for implicit skills without an observable read.

## 2.1.0
- A patch whose frontmatter has `patch-tools: <glob> ...` is also injected on the first call of a matching MCP tool in a session (`PostToolUse`, matcher `Skill|mcp__.*`), so it applies when an agent uses the skill's tools without invoking the skill. Once per session, a patch injected through its skill included; compacting the session (`SessionStart` matcher `compact`) clears the marks so it is injected again.

## 2.0.0
- A patch is `S.patch/SKILL.md` (frontmatter `name: S.patch`), was `S-patch`. Rename existing patch directories; `S-patch` is no longer read.

## 1.0.1
- A patch reached through two paths that resolve to one file (`~/.claude/skills/<s>-patch` symlinked to `~/.agents/skills/<s>-patch`) is injected once.

## 1.0.0
- When skill S runs, every `S-patch/SKILL.md` found (global `~/.claude/skills`, `~/.agents/skills`, then project `.claude/skills`, `.agents/skills`) is injected as context, frontmatter stripped. Fires on the Skill tool (`PostToolUse`, a `plugin:` prefix dropped) and when you type `/S` (`UserPromptExpansion`, `command_name`). Silent when no patch exists. New `tests/inject.sh`, run in CI.
