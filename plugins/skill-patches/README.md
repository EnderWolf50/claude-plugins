# skill-patches

Extend a skill you do not own (a plugin's, a shared repo's) without editing it. When skill `S` runs, this plugin injects your `S-patch` skill next to it, so your additions survive the skill's updates.

| Hook | Fires when | Skill name from |
|---|---|---|
| `PostToolUse` (`Skill`) | Claude invokes a skill | `tool_input.skill`, a `plugin:` prefix dropped (`search-tools:reference` → `reference`) |
| `UserPromptExpansion` | you type `/S` or `/S args` (this path skips the Skill tool) | `command_name`, a `plugin:` prefix dropped; a `/S` mentioned inside a prompt does not count |

Lookup, in this order; every file found is injected:

1. `~/.claude/skills/S-patch/SKILL.md`
2. `~/.agents/skills/S-patch/SKILL.md`
3. `$CLAUDE_PROJECT_DIR/.claude/skills/S-patch/SKILL.md`
4. `$CLAUDE_PROJECT_DIR/.agents/skills/S-patch/SKILL.md`

The context Claude gets is `Patch for skill S (overrides the skill where they conflict):` followed by each patch body, frontmatter stripped. Project patches come last, so they win over global ones. No patch: the hook prints nothing and exits 0. Needs `bash` and `jq`.

## Write a patch

Create `S-patch/SKILL.md` in one of the directories above, for example `~/.claude/skills/tdd-patch/SKILL.md`:

```markdown
---
name: tdd-patch
description: Patch for tdd: run the project's test script, not the runner directly
disable-model-invocation: true
user-invocable: false
---

When running tdd:
- Run tests with `pnpm test -- <file>`, not `vitest` directly.
- After the last green step, run `pnpm lint` and fix what it reports.
```

- `disable-model-invocation: true` and `user-invocable: false` keep the patch out of the skill listing and the `/` menu; it only ever arrives through this hook.
- Write the body as "When running S:" steps: additions, or overrides of named steps of S. Claude reads it after the skill, labelled as an override.
- Keep it short: Claude Code caps a hook's context at 10,000 characters.

## Install

```
claude plugin marketplace add EnderWolf50/claude-plugins
claude plugin install skill-patches@enderwolf50
```

## Test

```
bash plugins/skill-patches/tests/inject.sh
```
