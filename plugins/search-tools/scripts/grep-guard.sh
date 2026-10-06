#!/usr/bin/env bash
# PreToolUse (Bash) hook: tree searches go to rg (or tgrep); grep keeps the rest.
#
# Refused → retry lands on rg:
#   - grep / egrep / fgrep with a recursive flag (-r / -R / --recursive / --dereference-recursive)
#   - `xargs grep` (a tree search in disguise: find | xargs grep)
# Allowed: grep on a file or a stream, git grep, rg, tgrep, ast-grep.
# Set SEARCH_TOOLS_ALLOW_GREP=1 to disable.

set -u
[ "${SEARCH_TOOLS_ALLOW_GREP:-}" = "1" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

cmd="$(jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -n "$cmd" ] || exit 0

# Only what runs is checked: heredoc bodies are dropped, then quoted strings emptied, so
# `python -c "print('grep -r')"` or a script fed through <<'EOF' is data, not a search.
verdict="$(printf '%s\n' "$cmd" | awk '
  inhd { t = $0; if (strip) sub(/^\t+/, "", t); if (t == delim) inhd = 0; next }
  {
    print
    if (match($0, /<<-?[ \t]*["\047]?[A-Za-z_][A-Za-z0-9_]*["\047]?/) && substr($0, RSTART - 1, 1) != "<") {
      d = substr($0, RSTART, RLENGTH); strip = (d ~ /^<<-/)
      sub(/^<<-?[ \t]*/, "", d); gsub(/["\047]/, "", d); delim = d; inhd = 1
    }
  }' | awk -v RS='\001' '
{
  s = $0
  gsub(/\047[^\047]*\047/, "\047\047", s)
  gsub(/"([^"\\]|\\.)*"/, "\"\"", s)
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
    if (pre ~ /(^|[^A-Za-z0-9_])xargs([ \t]+-[^ \t]+)*[ \t]+$/) { print "xargs"; exit }
  }
}')"

case "$verdict" in
  recursive) why="Tree search: use rg — \`rg -n <pattern> [path]\` (same flags as grep, respects .gitignore, faster). On a large repo with a tgrep server, run \`tgrep\` from the repo root instead." ;;
  xargs)     why="Tree search via xargs grep: run rg on the directory instead — \`rg -n <pattern> [path]\` walks the tree itself and respects .gitignore; replace the find filter with \`-g '*.ext'\`." ;;
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
