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
patch "$CLAUDE_PROJECT_DIR/.agents/skills" review "When running review: PROJECT"
patch "$HOME/.claude/skills" review "When running review: GLOBAL"
patch "$CLAUDE_PROJECT_DIR/.agents/skills" onlyproj "When running onlyproj: PROJECT-ONLY"
patch "$HOME/.agents/skills" reference "When running reference: AGENTS-GLOBAL"
patch "$HOME/.agents/skills" linked "When running linked: ONCE"
ln -s "$HOME/.agents/skills/linked.patch" "$HOME/.claude/skills/linked.patch"
mkdir -p "$HOME/.agents/skills/design.patch"
printf -- '---\nname: design.patch\npatch-tools: mcp__*tempad-dev__* mcp__other__read\n---\nWhen running design: TOOLS\n' > "$HOME/.agents/skills/design.patch/SKILL.md"
export TMPDIR="$tmp/t"

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
both=$'Patch for skill tdd (overrides the skill where they conflict):\n\nWhen running tdd: GLOBAL'

check "no patch: silent"            "$(skill grilling)"                ""
check "global injected, project patch not" "$(skill tdd)"                "$both"
# Git Bash on Windows copies on `ln -s` (no symlink without MSYS=winsymlinks), so the case only runs where a link exists
if [ -L "$HOME/.claude/skills/linked.patch" ]; then
check "symlinked global: injected once" "$(skill linked)"            $'Patch for skill linked (overrides the skill where they conflict):\n\nWhen running linked: ONCE'
else echo "skip symlinked global: ln -s made a copy"; fi
check "project-only patch: silent"  "$(skill onlyproj)"                ""
check "global (~/.agents) only, plugin prefix dropped" "$(skill search-tools:reference)" \
  $'Patch for skill reference (overrides the skill where they conflict):\n\nWhen running reference: AGENTS-GLOBAL'
check "typed /skill args"           "$(typed tdd 'fix the parser')"    "$both"
check "typed /skill alone"          "$(typed tdd '')"                  "$both"
check "typed /plugin:skill"         "$(typed x:review now)"            $'Patch for skill review (overrides the skill where they conflict):\n\nWhen running review: GLOBAL'
check "typed command, no patch: silent" "$(typed clear '')"            ""
check "path-like command: silent"   "$(typed 'tdd/../x' '')"           ""
check "UserPromptSubmit mentioning /tdd: silent" "$(MSYS_NO_PATHCONV=1 jq -nc '{hook_event_name: "UserPromptSubmit", prompt: "/tdd and please run /tdd"}')" ""
check "traversal name: silent"      "$(skill '../tdd')"                ""

# tool <tool_name> <session_id>
tool() { jq -nc --arg t "$1" --arg s "$2" '{hook_event_name: "PostToolUse", tool_name: $t, session_id: $s, tool_input: {}}'; }
on_tool() { printf 'Patch for skill design, injected on the first %s call (overrides the skill where they conflict):\n\nWhen running design: TOOLS' "$1"; }
t=mcp__plugin_tempad-dev_tempad-dev__get_code
check "patch-tools glob: injected"        "$(tool $t s1)"                    "$(on_tool $t)"
check "patch-tools: once per session"     "$(tool $t s1)"                    ""
check "patch-tools: second glob, new session" "$(tool mcp__other__read s2)"  "$(on_tool mcp__other__read)"
check "unmatched MCP tool: silent"        "$(tool mcp__semble__search s4)"   ""
skill_s3="$(jq -nc '{hook_event_name: "PostToolUse", tool_name: "Skill", session_id: "s3", tool_input: {skill: "tempad-dev:design"}}')"
check "skill run first"                   "$skill_s3"                        $'Patch for skill design (overrides the skill where they conflict):\n\nWhen running design: TOOLS'
check "then its tool: already injected"   "$(tool $t s3)"                    ""
check "no session id: injected"           "$(tool $t '')"                    "$(on_tool $t)"
check "compact: silent"                   "$(jq -nc '{hook_event_name: "SessionStart", source: "compact", session_id: "s1"}')" ""
check "after compact: injected again"     "$(tool $t s1)"                    "$(on_tool $t)"

exit $fail
