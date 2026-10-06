#!/usr/bin/env bash
# PreToolUse (Bash) hook: tree searches go to rg (or tgrep); grep keeps the rest.
#
# A recursive grep (-r / -R / --recursive / --dereference-recursive) that is the whole command
# is rewritten to the matching rg command, which still goes through the normal permission checks.
# Refused → retry lands on rg:
#   - a recursive grep the rewrite cannot map: inside a pipeline or compound command, or with a
#     flag that has no exact rg equivalent
#   - `xargs grep` (a tree search in disguise: find | xargs grep)
# Allowed: grep on a file or a stream, git grep, rg, tgrep, ast-grep.
# Set SEARCH_TOOLS_ALLOW_GREP=1 to disable.

set -u
[ "${SEARCH_TOOLS_ALLOW_GREP:-}" = "1" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
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

# The rg equivalent of a command that is one recursive grep and nothing else, or nothing.
to_rg() {
  printf '%s' "$1" | awk -v RS='\001' '
  function unq(v) { if (v ~ /^\047.*\047$/ || v ~ /^".*"$/) v = substr(v, 2, length(v) - 2); return v }
  function sq(v)  { if (v ~ /\047/) exit; return "\047" v "\047" }
  {
    c = $0; sub(/\n$/, "", c)
    s = c; gsub(/\047[^\047]*\047/, "", s); gsub(/"([^"\\]|\\.)*"/, "", s)
    if (s ~ /[|;&<>`$\\(){}\n]/ || s !~ /^[ \t]*[ef]?grep[ \t]/) exit
    n = 0; tok = ""; q = ""; in_tok = 0
    for (i = 1; i <= length(c); i++) {
      ch = substr(c, i, 1)
      if (q != "") { tok = tok ch; if (ch == q) q = ""; continue }
      if (ch == "\047" || ch == "\"") { q = ch; tok = tok ch; in_tok = 1; continue }
      if (ch == " " || ch == "\t") { if (in_tok) { t[++n] = tok; tok = ""; in_tok = 0 }; continue }
      tok = tok ch; in_tok = 1
    }
    if (in_tok) t[++n] = tok
    if (q != "") exit
    out = "rg"; if (t[1] == "fgrep") out = out " -F"
    for (i = 2; i <= n; i++) {
      a = t[i]
      if (a == "--" || a !~ /^-./) break
      if (a ~ /^--/) {
        if (a == "--recursive" || a == "--dereference-recursive" || a == "--extended-regexp") continue
        if (a == "--ignore-case")        { out = out " -i"; continue }
        if (a == "--line-number")        { out = out " -n"; continue }
        if (a == "--files-with-matches") { out = out " -l"; continue }
        if (a == "--count")              { out = out " -c"; continue }
        if (a == "--invert-match")       { out = out " -v"; continue }
        if (a == "--word-regexp")        { out = out " -w"; continue }
        if (a == "--fixed-strings")      { out = out " -F"; continue }
        if (a ~ /^--include=/)     { out = out " -g " sq(unq(substr(a, 11))); continue }
        if (a ~ /^--exclude=/)     { out = out " -g " sq("!" unq(substr(a, 11))); continue }
        if (a ~ /^--exclude-dir=/) { out = out " -g " sq("!" unq(substr(a, 15)) "/"); continue }
        exit
      }
      for (k = 2; k <= length(a); k++) {
        ch = substr(a, k, 1)
        if (ch ~ /[rRE]/) continue
        if (ch ~ /[inlcvwoFHP]/) { out = out " -" ch; continue }
        if (ch == "h") { out = out " -I"; continue }
        if (ch ~ /[ABCm]/) {
          v = substr(a, k + 1); if (v == "") v = t[++i]
          if (v !~ /^[0-9]+$/) exit
          out = out " -" ch " " v; break
        }
        exit
      }
    }
    for (; i <= n; i++) out = out " " t[i]
    print out
  }'
}

if [ "$verdict" = recursive ] && rg_cmd="$(to_rg "$cmd")" && [ -n "$rg_cmd" ]; then
  printf '%s' "$input" | jq --arg c "$rg_cmd" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      updatedInput: (.tool_input + {command: $c}),
      additionalContext: ("search-tools ran this recursive grep as `" + $c + "`. Unlike grep -r, rg skips files that .gitignore lists and hidden files; rerun with -uu to search those too.")
    }
  }'
  exit 0
fi

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
