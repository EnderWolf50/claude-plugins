#!/usr/bin/env bash
# PostToolUse and UserPromptExpansion hook: when skill S runs, inject every S.patch/SKILL.md
# (frontmatter stripped) as additionalContext. Global patches first, project patches last.
#   Skill tool (model-invoked): tool_input.skill
#   UserPromptExpansion (user typed /S): command_name
#   any other tool (hooks.json matches MCP tools): every patch whose frontmatter `patch-tools:` glob
#     matches tool_name, once per session; a patch already injected through its skill is skipped.
# A `plugin:` prefix is dropped.
# Silent (no output, exit 0) when no patch applies.

set -u
command -v jq >/dev/null 2>&1 || exit 0

# \x1f, not tab: tab is IFS whitespace, so an empty field would shift the ones after it
IFS=$'\x1f' read -r event tool name session < <(jq -r '[
  .hook_event_name // "",
  .tool_name // "",
  if .hook_event_name == "UserPromptExpansion" then (.command_name // "") | ltrimstr("/")
  else (.tool_input.skill // "") end,
  .session_id // ""
] | join("\u001f")' 2>/dev/null | tr -d '\r')
case "$session" in *[!A-Za-z0-9_-]*) session="" ;; esac
marks="${TMPDIR:-/tmp}/skill-patches/$session"

dirs=("$HOME/.claude/skills" "$HOME/.agents/skills")
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ "$CLAUDE_PROJECT_DIR" != "$HOME" ]; then
  dirs+=("$CLAUDE_PROJECT_DIR/.claude/skills" "$CLAUDE_PROJECT_DIR/.agents/skills")
fi

# collect <name>: every <name>.patch body into $body
collect() {
  local d f real part seen=""
  body=""
  for d in "${dirs[@]}"; do
    f="$d/$1.patch/SKILL.md"
    [ -f "$f" ] || continue
    # ~/.claude/skills/* is often a symlink to ~/.agents/skills/*: one file, injected once
    real="$(cd "$(dirname "$f")" && pwd -P)/SKILL.md"
    case "$seen" in *"|$real|"*) continue ;; esac
    seen="$seen|$real|"
    # drop a leading --- frontmatter block
    part="$(awk 'NR == 1 && /^---[ \t\r]*$/ { fm = 1; next } fm && /^---[ \t\r]*$/ { fm = 0; next } !fm' "$f")"
    body="$body"$'\n\n'"$part"
  done
}
mark() { [ -z "$session" ] || { mkdir -p "$marks" && : > "$marks/$1"; }; }
emit() { jq -n --arg e "$event" --arg c "$1" '{hookSpecificOutput: {hookEventName: $e, additionalContext: $c}}'; }

if [ "$tool" = Skill ] || [ "$event" = UserPromptExpansion ]; then
  name="${name##*:}"
  case "$name" in ''|*[!A-Za-z0-9_.-]*|.*) exit 0 ;; esac
  collect "$name"
  [ -n "$body" ] || exit 0
  mark "$name"
  emit "Patch for skill $name (overrides the skill where they conflict):$body"
  exit 0
fi

[ -n "$tool" ] || exit 0
out=""
done_names=""
for d in "${dirs[@]}"; do
  for f in "$d"/*.patch/SKILL.md; do
    [ -f "$f" ] || continue
    globs="$(awk 'NR == 1 && /^---[ \t\r]*$/ { fm = 1; next } fm && /^---[ \t\r]*$/ { exit } fm && sub(/^patch-tools:[ \t]*/, "") { print }' "$f" | tr -d '\r')"
    hit=""
    set -f # each glob matches a tool name, not files
    for g in $globs; do case "$tool" in $g) hit=1 ;; esac; done
    set +f
    [ -n "$hit" ] || continue
    name="$(basename "$(dirname "$f")")"; name="${name%.patch}"
    case "$done_names" in *"|$name|"*) continue ;; esac
    done_names="$done_names|$name|"
    [ -n "$session" ] && [ -e "$marks/$name" ] && continue
    collect "$name"
    mark "$name"
    out="$out"$'\n\n'"Patch for skill $name, injected on the first $tool call (overrides the skill where they conflict):$body"
  done
done
[ -n "$out" ] || exit 0
emit "${out#$'\n\n'}"
