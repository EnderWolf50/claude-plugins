#!/usr/bin/env bash
# session-context.sh: a SessionStart or SubagentStart event in; the rules as additionalContext out. Run:
#   bash plugins/guards/tests/session-context.sh

set -u
here="$(cd "$(dirname "$0")" && pwd)"
hook="$here/../scripts/session-context.sh"
rules="$here/../scripts/rules.json"

fail=0
# check <event> <platform> <jq test on {out, rules}> <what>
check() {
  local out
  out="$(jq -n --arg e "$1" '{hook_event_name: $e, source: "startup"}' | GUARDS_PLATFORM="$2" bash "$hook")"
  if jq -n -e --argjson out "${out:-null}" --slurpfile r "$rules" "\$r[0] as \$rules | $3" >/dev/null 2>&1; then
    echo "ok   $1 $2: $4"
  else echo "FAIL $1 $2: $4 <- $out"; fail=1; fi
}

ctx='$out.hookSpecificOutput.additionalContext'
for event in SessionStart SubagentStart; do
  check "$event" Linux "\$out.hookSpecificOutput.hookEventName == \"$event\"" "names its event"
  check "$event" Linux "[\$rules.context.all[] as \$k | $ctx | contains(\$rules[\$k].do)] | all" "every shared rule"
  check "$event" Linux "$ctx | contains(\$rules.rewrite.do) | not" "no Windows lines off Windows"
  check "$event" MINGW64_NT-10.0 "[\$rules.context.claudeWindows[] as \$k | $ctx | contains(\$rules[\$k].do)] | all" "the Windows lines on Windows"
  check "$event" MINGW64_NT-10.0 "$ctx | length < 10000" "under the 10,000-character cap"
done
check PreToolUse Linux '$out == null' "prints nothing for other events"

exit $fail
