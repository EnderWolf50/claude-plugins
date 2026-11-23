# Sourced by the guards' bash scripts. The rule text lives in rules.json beside this file, the one
# source for the denials and for the session context.
case "${BASH_SOURCE[0]}" in
  */*|*\\*) guards_rules="${BASH_SOURCE[0]%[/\\]*}/rules.json" ;;
  *)        guards_rules=rules.json ;;
esac

# rule <key>: the denial text of one rule, its do, how and why.
rule() {
  jq -r --arg k "$1" '.[$k] | [.do, .how, .why] | map(select(. != null)) | join(" ")' "$guards_rules" | tr -d '\r'   # Windows jq writes CRLF
}

# deny <reason>: print the PreToolUse denial and stop.
deny() {
  jq -n --arg why "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $why
    }
  }'
  exit 0
}

# windows: Git Bash, MSYS or Cygwin. GUARDS_PLATFORM stands in for uname in tests.
windows() {
  case "${GUARDS_PLATFORM:-$(uname -s)}" in MINGW*|MSYS*|CYGWIN*) return 0 ;; esac
  return 1
}
