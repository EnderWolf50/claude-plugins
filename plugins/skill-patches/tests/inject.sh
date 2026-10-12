#!/usr/bin/env bash
# inject.sh: a hook event in; the patch text out (additionalContext), or nothing. Run:
#   bash plugins/skill-patches/tests/inject.sh

set -u
here="$(cd "$(dirname "$0")" && pwd)"
hook="$here/../scripts/inject.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home" CLAUDE_PROJECT_DIR="$tmp/proj"

patch() { # patch <skills dir> <skill> <body>
  mkdir -p "$1/$2.patch"
  printf -- '---\nname: %s.patch\ndescription: Patch for %s: test\n---\n%s\n' "$2" "$2" "$3" > "$1/$2.patch/SKILL.md"
}
patch "$HOME/.claude/skills" tdd "When running tdd: GLOBAL"
patch "$CLAUDE_PROJECT_DIR/.claude/skills" tdd "When running tdd: PROJECT"
patch "$CLAUDE_PROJECT_DIR/.agents/skills" review "When running review: PROJECT-ONLY"
patch "$HOME/.agents/skills" reference "When running reference: AGENTS-GLOBAL"
patch "$HOME/.agents/skills" linked "When running linked: ONCE"
ln -s "$HOME/.agents/skills/linked.patch" "$HOME/.claude/skills/linked.patch"

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
# typed /<command> <args>: the UserPromptExpansion input Claude Code sends
typed() { MSYS_NO_PATHCONV=1 jq -nc --arg n "$1" --arg a "$2" \
  '{hook_event_name: "UserPromptExpansion", expansion_type: "slash_command", command_name: $n, command_args: $a, prompt: ("/" + $n + " " + $a)}'; }
both=$'Patch for skill tdd (overrides the skill where they conflict):\n\nWhen running tdd: GLOBAL\n\nWhen running tdd: PROJECT'

check "no patch: silent"            "$(skill grilling)"                ""
check "global and project, in order" "$(skill tdd)"                    "$both"
# Git Bash on Windows copies on `ln -s` (no symlink without MSYS=winsymlinks), so the case only runs where a link exists
if [ -L "$HOME/.claude/skills/linked.patch" ]; then
check "symlinked global: injected once" "$(skill linked)"            $'Patch for skill linked (overrides the skill where they conflict):\n\nWhen running linked: ONCE'
else echo "skip symlinked global: ln -s made a copy"; fi
check "project only"                "$(skill review)"                  $'Patch for skill review (overrides the skill where they conflict):\n\nWhen running review: PROJECT-ONLY'
check "global (~/.agents) only, plugin prefix dropped" "$(skill search-tools:reference)" \
  $'Patch for skill reference (overrides the skill where they conflict):\n\nWhen running reference: AGENTS-GLOBAL'
check "typed /skill args"           "$(typed tdd 'fix the parser')"    "$both"
check "typed /skill alone"          "$(typed tdd '')"                  "$both"
check "typed /plugin:skill"         "$(typed x:review now)"            $'Patch for skill review (overrides the skill where they conflict):\n\nWhen running review: PROJECT-ONLY'
check "typed command, no patch: silent" "$(typed clear '')"            ""
check "path-like command: silent"   "$(typed 'tdd/../x' '')"           ""
check "UserPromptSubmit mentioning /tdd: silent" "$(MSYS_NO_PATHCONV=1 jq -nc '{hook_event_name: "UserPromptSubmit", prompt: "/tdd and please run /tdd"}')" ""
check "traversal name: silent"      "$(skill '../tdd')"                ""
CLAUDE_PROJECT_DIR="" check "unset project dir: global only" "$(skill tdd)" \
  $'Patch for skill tdd (overrides the skill where they conflict):\n\nWhen running tdd: GLOBAL'

exit $fail
