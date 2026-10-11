#!/usr/bin/env bash
# PostToolUse (Skill) and UserPromptSubmit hook: when skill S runs, inject every S-patch/SKILL.md
# (frontmatter stripped) as additionalContext. Global patches first, project patches last.
#   Skill tool:       tool_input.skill, a `plugin:` prefix dropped
#   UserPromptSubmit: a prompt that starts with /S
# Silent (no output, exit 0) when no patch exists.

set -u
command -v jq >/dev/null 2>&1 || exit 0

IFS=$'\t' read -r event name < <(jq -r '[
  .hook_event_name // "",
  if .hook_event_name == "UserPromptSubmit"
  then ((.prompt // "") | capture("^/(?<s>[^\\s/]+)(\\s|$)").s // "")
  else (.tool_input.skill // "") end
] | @tsv' 2>/dev/null | tr -d '\r')
name="${name##*:}"
case "$name" in ''|*[!A-Za-z0-9_.-]*|.*) exit 0 ;; esac

dirs=("$HOME/.claude/skills" "$HOME/.agents/skills")
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ "$CLAUDE_PROJECT_DIR" != "$HOME" ]; then
  dirs+=("$CLAUDE_PROJECT_DIR/.claude/skills" "$CLAUDE_PROJECT_DIR/.agents/skills")
fi

body=""
for d in "${dirs[@]}"; do
  f="$d/$name-patch/SKILL.md"
  [ -f "$f" ] || continue
  # drop a leading --- frontmatter block
  part="$(awk 'NR == 1 && /^---[ \t\r]*$/ { fm = 1; next } fm && /^---[ \t\r]*$/ { fm = 0; next } !fm' "$f")"
  body="$body"$'\n\n'"$part"
done
[ -n "$body" ] || exit 0

jq -n --arg e "$event" --arg c "Patch for skill $name (overrides the skill where they conflict):$body" \
  '{hookSpecificOutput: {hookEventName: $e, additionalContext: $c}}'
