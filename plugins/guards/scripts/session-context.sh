#!/usr/bin/env bash
# SessionStart and SubagentStart hook (Claude Code): tells the agent up front what the guards
# check, one positive line per rule, from the `do` text of rules.json that the denials also use.
# Codex gets its context from codex.js, from the same file.

set -u
command -v jq >/dev/null 2>&1 || exit 0
case "${BASH_SOURCE[0]}" in */*|*\\*) . "${BASH_SOURCE[0]%[/\\]*}/rules.sh" ;; *) . ./rules.sh ;; esac

event="$(jq -r '.hook_event_name // "SessionStart"' 2>/dev/null | tr -d '\r')"
case "$event" in SessionStart|SubagentStart) ;; *) exit 0 ;; esac
if windows; then win=true; else win=false; fi

jq --arg event "$event" --argjson win "$win" '
  . as $r
  | ($r.context.all + (if $win then $r.context.claudeWindows else [] end))
  | map("- " + $r[.].do)
  | {hookSpecificOutput: {hookEventName: $event, additionalContext: ([$r.context.intro] + . | join("\n"))}}
' "$guards_rules"
