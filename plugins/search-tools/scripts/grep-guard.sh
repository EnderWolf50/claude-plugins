#!/usr/bin/env bash
# PreToolUse (Bash) hook: grep is a stream filter, rg is the file searcher.
#
# Refused → retry lands on rg:
#   - any grep / egrep / fgrep that is not directly after a pipe (`grep x file`,
#     `cd d && grep x f`, `xargs grep`, `if grep -q x f`), i.e. one reading files
#   - any grep with a recursive flag (-r / -R / --recursive / --dereference-recursive)
# Allowed: `cmd | grep x`, `git grep`, rg, tgrep, ast-grep.
# Set SEARCH_TOOLS_ALLOW_GREP=1 to disable.

set -u
[ "${SEARCH_TOOLS_ALLOW_GREP:-}" = "1" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

cmd="$(jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -n "$cmd" ] || exit 0

verdict="$(printf '%s' "$cmd" | awk -v RS='\001' '
{
  s = $0
  while (match(s, /[ef]?grep([^A-Za-z0-9_-]|$)/)) {
    pre  = substr(s, 1, RSTART - 1)
    prev = (RSTART > 1) ? substr(s, RSTART - 1, 1) : ""
    rest = substr(s, RSTART)
    s    = substr(s, RSTART + RLENGTH)
    if (prev ~ /[A-Za-z0-9_.\/-]/) continue          # tgrep, ast-grep, path/grep
    if (pre ~ /(^|[^A-Za-z0-9_])git[ \t]+$/) continue # git grep
    # the flags of this invocation: up to the next pipe / ; / &&
    inv = rest; sub(/[|;&].*/, "", inv)
    if (inv ~ /[ \t]-[A-Za-z]*[rR]/ || inv ~ /--(dereference-)?recursive/) { print "recursive"; exit }
    sub(/[ \t\n]+$/, "", pre)
    if (pre == "" || pre !~ /\|$/ || pre ~ /\|\|$/) { print "file"; exit }
  }
}')"

case "$verdict" in
  recursive) why="Tree search: use rg — \`rg -n <pattern> [path]\` (same flags as grep, respects .gitignore, faster). On a large repo with a tgrep server, run \`tgrep\` from the repo root instead." ;;
  file)      why="grep on files: use rg with the same flags — \`rg -n -i -E '<pattern>' <file>\`. grep stays for stream filters only (\`cmd | grep x\`)." ;;
  *)         exit 0 ;;
esac

jq -n --arg why "$why" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $why
  }
}'
exit 0
