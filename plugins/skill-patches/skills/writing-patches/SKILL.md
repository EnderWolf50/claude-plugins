---
name: writing-patches
description: Extend a skill you do not own with a `<skill>.patch`. Use when changing an upstream or plugin skill, or adding repo-specific rules to one.
---

# Writing a skill patch

The skill-patches plugin injects `<skill>.patch/SKILL.md` as context right after skill `<skill>` runs. The patch carries your additions; the skill's own files stay untouched, so its updates never overwrite them.

## Patch or edit

- Find the skill's owner: its source in `~/.agents/.skill-lock.json` when the `skills` CLI installed it, or the plugin that ships it.
- Your own skill: edit it.
- Someone else's skill (plugin, upstream repo): write a patch and leave its files as they are.
- Look for an existing `<skill>.patch` in `~/.claude/skills` and `~/.agents/skills` first; extend it.

## Format

Create `<skill>.patch/SKILL.md`:

```markdown
---
name: tdd.patch
description: Patch for tdd: run the project's test script, not the runner directly
disable-model-invocation: true
user-invocable: false
---

When running tdd:
- Run tests with `pnpm test -- <file>`, not `vitest` directly. Done when the script exits 0.
- After the last green step, run `pnpm lint`. Done when it reports nothing.
```

- `disable-model-invocation: true` and `user-invocable: false` keep the patch out of the skill list and the `/` menu; it arrives only through the hook.
- Open the body with "When running `<skill>`:" and list steps: additions, or overrides of named steps of the skill. Give each step a completion criterion.
- Keep the body short: Claude Code caps a hook's context at 10,000 characters.

## Where it lives

- `~/.claude/skills/<skill>.patch/` or `~/.agents/skills/<skill>.patch/`. Patches are global only; a project repository holds none.
- A rule that holds in some repos only becomes a condition the agent checks: "in a public repo, ...", "when the repo's AGENTS.md says ...". The project keeps its specifics in its own AGENTS.md or docs.

## Inject on a tool call

To have the patch arrive when an agent uses the skill's MCP tools without invoking the skill, add `patch-tools:` to the frontmatter: space-separated globs matched against the tool name.

```markdown
patch-tools: mcp__*tempad-dev__* mcp__other__read
```

It is injected once, on the first matching call, and again after the session is compacted. Only MCP tools (`mcp__*`) match.
