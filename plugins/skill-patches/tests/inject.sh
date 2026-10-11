#!/usr/bin/env bash
# inject.sh: a hook event in; the patch text out (additionalContext), or nothing. Run:
#   bash plugins/skill-patches/tests/inject.sh

set -u
here="$(cd "$(dirname "$0")" && pwd)"
hook="$here/../scripts/inject.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home" CLAUDE_PROJECT_DIR="$tmp/proj"

patch() { # patch <skills dir> <skill> <body>
  mkdir -p "$1/$2-patch"
  printf -- '---\nname: %s-patch\ndescription: Patch for %s: test\n---\n%s\n' "$2" "$2" "$3" > "$1/$2-patch/SKILL.md"
}
patch "$HOME/.claude/skills" tdd "When running tdd: GLOBAL"
patch "$CLAUDE_PROJECT_DIR/.claude/skills" tdd "When running tdd: PROJECT"
patch "$CLAUDE_PROJECT_DIR/.agents/skills" review "When running review: PROJECT-ONLY"
patch "$HOME/.agents/skills" reference "When running reference: AGENTS-GLOBAL"

fail=0
# check <name> <event json> <expected additionalContext, or empty for no output>
check() {
  local out got
  out="$(printf '%s' "$2" | bash "$hook")"; local rc=$?
  # Windows jq writes CRLF
  got="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null | tr -d '\r')"
  [ -z "$out" ] || [ "$(printf '%s' "$out" | jq -r .hookSpecificOutput.hookEventName | tr -d '\r')" = "$(printf '%s' "$2" | jq -r .hook_event_name | tr -d '\r')" ] || got="$got (wrong hookEventName)"
  [ $rc -eq 0 ] || got="$got (exit $rc)"
  if [ "$got" = "$3" ]; then echo "ok   $1"
  else printf 'FAIL %s\n  want: %s\n  got:  %s\n' "$1" "$3" "$got"; fail=1; fi
}
skill() { jq -nc --arg s "$1" '{hook_event_name: "PostToolUse", tool_name: "Skill", tool_input: {skill: $s}}'; }
prompt() { jq -nc --arg p "$1" '{hook_event_name: "UserPromptSubmit", prompt: $p}'; }
both=$'Patch for skill tdd (overrides the skill where they conflict):\n\nWhen running tdd: GLOBAL\n\nWhen running tdd: PROJECT'

check "no patch: silent"            "$(skill grilling)"                ""
check "global and project, in order" "$(skill tdd)"                    "$both"
check "project only"                "$(skill review)"                  $'Patch for skill review (overrides the skill where they conflict):\n\nWhen running review: PROJECT-ONLY'
check "global (~/.agents) only, plugin prefix dropped" "$(skill search-tools:reference)" \
  $'Patch for skill reference (overrides the skill where they conflict):\n\nWhen running reference: AGENTS-GLOBAL'
check "/skill args prompt"          "$(prompt '/tdd fix the parser')"  "$both"
check "/skill alone"                "$(prompt '/tdd')"                 "$both"
check "/plugin:skill prompt"        "$(prompt '/x:review now')"        $'Patch for skill review (overrides the skill where they conflict):\n\nWhen running review: PROJECT-ONLY'
check "mid-text /skill: silent"     "$(prompt 'please run /tdd on this')" ""
check "plain prompt: silent"        "$(prompt 'hello')"                ""
check "path-like prompt: silent"    "$(prompt '/tdd/../x')"             ""
check "traversal name: silent"      "$(skill '../tdd')"                ""
CLAUDE_PROJECT_DIR="" check "unset project dir: global only" "$(skill tdd)" \
  $'Patch for skill tdd (overrides the skill where they conflict):\n\nWhen running tdd: GLOBAL'

exit $fail
