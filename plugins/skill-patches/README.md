# skill-patches

Codex: add the `EnderWolf50/claude-plugins` marketplace and install `skill-patches@enderwolf50`.
Review its hooks in `/hooks`. The Codex adapter handles `$skill` mentions in submitted prompts,
concrete `SKILL.md` reads observed through shell calls, and `patch-tools` MCP globs. Global
patches only; symlinks are deduplicated. Changed patch content reinjects,
and compaction resets session marks. Implicit skill context with no observable file read still needs the global instruction fallback;
Codex has no `Skill` or `UserPromptExpansion` event. No CC hook behavior is removed.

Extend a skill you do not own (a plugin's, a shared repo's) without editing it. When skill `S` runs, this plugin injects your `S.patch` skill next to it, so your additions survive the skill's updates.

| Hook | Fires when | Skill name from |
|---|---|---|
| `PostToolUse` (`Skill`) | Claude invokes a skill | `tool_input.skill`, a `plugin:` prefix dropped (`search-tools:reference` → `reference`) |
| `UserPromptExpansion` | you type `/S` or `/S args` (this path skips the Skill tool) | `command_name`, a `plugin:` prefix dropped; a `/S` mentioned inside a prompt does not count |
| `PostToolUse` (`mcp__*`) | Claude first calls an MCP tool a patch names in `patch-tools:` (see [Inject on a tool call](#inject-on-a-tool-call)) | the patch's own directory name |

Lookup, in this order; every file found is injected:

1. `~/.claude/skills/S.patch/SKILL.md`
2. `~/.agents/skills/S.patch/SKILL.md`

Patches are global only: a project's `.claude/skills` and `.agents/skills` are not read. The context Claude gets is `Patch for skill S (overrides the skill where they conflict):` followed by each patch body, frontmatter stripped. No patch: the hook prints nothing and exits 0. Needs `bash` and `jq`.

## Write a patch

The plugin ships the `writing-patches` skill: when to patch rather than edit, the `S.patch/SKILL.md` format, where it lives and the 10,000-character context cap. Ask your agent to write a patch and it loads that skill; it is the single source for the how-to.

## Inject on a tool call

An agent can use a skill's MCP tools without invoking the skill. A patch that names those tools in `patch-tools:` (space-separated globs matched against the tool name) is injected after the first matching call, headed `Patch for skill S, injected on the first <tool> call`. Once per session: a patch already injected, through its skill or an earlier tool call, is not repeated until the session is compacted (`SessionStart`, `compact`, clears the marks, since the summary may drop the patch). Only MCP tools (`mcp__*`) are matched; the session marks live under `$TMPDIR/skill-patches/<session_id>/`.

## Install

```
claude plugin marketplace add EnderWolf50/claude-plugins
claude plugin install skill-patches@enderwolf50
```

## Test

```
bash plugins/skill-patches/tests/inject.sh
```
