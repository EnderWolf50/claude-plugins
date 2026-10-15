#!/usr/bin/env bash
# PreToolUse (Bash) hook: tree searches go to rg (or tgrep); grep keeps the rest.
#
# Each segment of the command (split at |, &&, ||, ;, &, newline) that is a recursive grep
# (-r / -R / --recursive / --dereference-recursive):
#   - whose path arguments are all existing regular files: left alone (grep -r on a file is grep)
#   - otherwise rewritten in place to the matching rg command; the other segments run as written,
#     and the result still goes through the normal permission checks
# Refused → retry lands on rg:
#   - a recursive grep the rewrite cannot map: a flag with no exact rg equivalent (-e, -q, ...),
#     a $variable or glob as the pattern, command substitution or subshell syntax, no path right
#     after a pipe (rg would read stdin), a heredoc in the command, or a grep that does not start
#     its segment (x=$(grep -r ...))
#   - `xargs grep` (a tree search in disguise: find | xargs grep)
# Allowed: grep on a file or a stream, git grep, rg, tgrep, ast-grep.
# Set SEARCH_TOOLS_ALLOW_GREP=1 to disable.

set -u
[ "${SEARCH_TOOLS_ALLOW_GREP:-}" = "1" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null | tr -d '\r')"   # Windows jq writes CRLF
[ -n "$cmd" ] || exit 0

# Only what runs is checked: heredoc bodies are dropped, then quoted strings emptied, so
# `python -c "print('grep -r')"` or a script fed through <<'EOF' is data, not a search.
verdict_of() { printf '%s\n' "$1" | awk '
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
}'; }
verdict="$(verdict_of "$cmd")"
[ -n "$verdict" ] || exit 0

# The command with every recursive grep segment that maps to rg rewritten (mode=out), or with
# those segments and the file-only ones replaced by `:` (mode=mask, checked again for what is left).
rewrite() {
  # cwd goes in through ENVIRON: awk -v would read the backslashes of C:\Users\... as escapes
  printf '%s' "$1" | CWD="$3" awk -v RS='\001' -v mode="$2" '
  function sq(v) { gsub(/\047/, "\047\\\047\047", v); return "\047" v "\047" }
  function isfile(p,    cwd) {
    cwd = ENVIRON["CWD"]
    if (p !~ /^\// && p !~ /^[A-Za-z]:/ && cwd != "") p = cwd "/" p
    return system("test -f " sq(p)) == 0
  }
  # grep BRE/ERE → rg regex. Bracket expressions are copied; one rg would read differently aborts.
  function conv(p, bre,    o, i, j, e, ch, nx, b) {
    o = ""
    for (i = 1; i <= length(p); i++) {
      ch = substr(p, i, 1); nx = substr(p, i + 1, 1)
      if (ch == "[") {
        j = i + 1; if (substr(p, j, 1) == "^") j++; if (substr(p, j, 1) == "]") j++
        while (j <= length(p) && substr(p, j, 1) != "]") {
          if (substr(p, j, 2) == "[:") { e = index(substr(p, j + 2), ":]"); if (!e) { BAD = 1; return "" }; j += e + 3; continue }
          j++
        }
        b = substr(p, i, j - i + 1)
        if (j > length(p) || b ~ /\\|&&|--|~~/ || b ~ /.\[[^:]/) { BAD = 1; return "" }
        o = o b; i = j; continue
      }
      if (ch == "\\") {
        if (nx == "<" || nx == ">") o = o "\\b"
        else if (bre && nx ~ /[|(){}?+]/) o = o nx
        else o = o ch nx
        i++; continue
      }
      if (bre && ch ~ /[|(){}?+]/) { o = o "\\" ch; continue }
      o = o ch
    }
    return o
  }
  # tokens of segment c: raw t[], shell value v[]; var[]: holds a $expansion, glob[]: an unquoted
  # glob or ~. 0 when quotes are unbalanced or the segment holds subshell or redirection syntax.
  function tokenize(c,    i, ch, q, in_tok) {
    n = 0; q = ""; in_tok = 0
    for (i = 1; i <= length(c); i++) {
      ch = substr(c, i, 1)
      if (q == "\047") { t[n] = t[n] ch; if (ch == q) q = ""; else v[n] = v[n] ch; continue }
      if (q == "\"") {
        t[n] = t[n] ch
        if (ch == "\\" && substr(c, i + 1, 1) ~ /[\\"$`]/) { i++; ch = substr(c, i, 1); t[n] = t[n] ch; v[n] = v[n] ch; continue }
        if (ch == q) { q = ""; continue }
        if (ch == "`") return 0
        if (ch == "$") var[n] = 1
        v[n] = v[n] ch; continue
      }
      if (ch == " " || ch == "\t") { in_tok = 0; continue }
      if (!in_tok) { n++; t[n] = ""; v[n] = ""; var[n] = 0; glob[n] = 0; in_tok = 1 }
      if (ch == "\047" || ch == "\"") { q = ch; t[n] = t[n] ch; continue }
      if (ch == "\\") { i++; t[n] = t[n] ch substr(c, i, 1); v[n] = v[n] substr(c, i, 1); continue }
      if (ch ~ /[`(){}<]/) return 0
      if (ch == "$") var[n] = 1
      if (ch ~ /[*?[~]/) glob[n] = 1
      t[n] = t[n] ch; v[n] = v[n] ch
    }
    return q == ""
  }
  # 0: not a recursive grep, or one rg cannot run as is; 1: R holds the rg command; 2: files only
  function seg2rg(c, afterpipe,    i, k, a, ch, out, rest, rec, bre, pat, endopt, npath, files) {
    if (!tokenize(c) || t[1] !~ /^[ef]?grep$/) return 0
    out = "rg"; rest = ""; rec = 0; pat = 0; endopt = 0; npath = 0; files = 1
    bre = (t[1] == "grep"); if (t[1] == "fgrep") { out = out " -F"; bre = -1 }
    for (i = 2; i <= n; i++) {
      a = t[i]
      if (a ~ /^[0-9]*(>>?|>&|&>)/) {                 # a redirection: kept as written
        rest = rest " " a
        if (a ~ /^[0-9]*(>>?|&>)$/) rest = rest " " t[++i]
        continue
      }
      if (!endopt && a == "--") { endopt = 1; continue }
      if (!endopt && a ~ /^-./ && a ~ /^--/) {          # options may follow the pattern, as in GNU grep
        if (a == "--recursive" || a == "--dereference-recursive") { rec = 1; continue }
        if (a == "--extended-regexp")    { if (bre >= 0) bre = 0; continue }
        if (a == "--ignore-case")        { out = out " -i"; continue }
        if (a == "--line-number")        { out = out " -n"; continue }
        if (a == "--files-with-matches") { out = out " -l"; continue }
        if (a == "--count")              { out = out " -c"; continue }
        if (a == "--invert-match")       { out = out " -v"; continue }
        if (a == "--word-regexp")        { out = out " -w"; continue }
        if (a == "--fixed-strings")      { out = out " -F"; bre = -1; continue }
        if (var[i]) return 0
        if (a ~ /^--include=/)     { out = out " -g " sq(substr(v[i], 11)); continue }
        if (a ~ /^--exclude=/)     { out = out " -g " sq("!" substr(v[i], 11)); continue }
        if (a ~ /^--exclude-dir=/) { out = out " -g " sq("!" substr(v[i], 15) "/"); continue }
        return 0
      }
      if (!endopt && a ~ /^-./) {
        for (k = 2; k <= length(a); k++) {
          ch = substr(a, k, 1)
          if (ch ~ /[rR]/) { rec = 1; continue }
          if (ch == "E") { if (bre >= 0) bre = 0; continue }
          if (ch ~ /[FP]/) { out = out " -" ch; bre = -1; continue }
          if (ch ~ /[inlcvwoH]/) { out = out " -" ch; continue }
          if (ch == "h") { out = out " -I"; continue }
          if (ch ~ /[ABCm]/) {
            a = substr(a, k + 1); if (a == "") a = t[++i]
            if (a !~ /^[0-9]+$/) return 0
            out = out " -" ch " " a; break
          }
          return 0
        }
        continue
      }
      if (v[i] ~ /^-/) return 0                          # rg would read it as a flag
      if (!pat) { pat = i; continue }
      npath++; rest = rest " " a
      if (var[i] || glob[i] || !isfile(v[i])) files = 0
    }
    if (!rec || !pat || var[pat] || glob[pat]) return 0
    if (npath && files) return 2
    if (!npath && afterpipe) return 0
    a = t[pat]
    if (bre >= 0) {
      BAD = 0; ch = conv(v[pat], bre); if (BAD) return 0
      if (ch != v[pat]) a = sq(ch)
    }
    R = out " " a rest; return 1
  }
  {
    c = $0; sub(/\n$/, "", c)
    bare = c; gsub(/\047[^\047]*\047/, "", bare); gsub(/"([^"\\]|\\.)*"/, "", bare)
    if (bare ~ /<<[^<]/) { print c; exit }              # heredoc bodies are not commands
    # split at unquoted separators; seg[k] is followed by sep[k]
    ns = 1; seg[1] = ""; q = ""
    for (i = 1; i <= length(c); i++) {
      ch = substr(c, i, 1); nx = substr(c, i + 1, 1)
      if (q != "") {
        seg[ns] = seg[ns] ch
        if (q == "\"" && ch == "\\") { seg[ns] = seg[ns] nx; i++ }
        else if (ch == q) q = ""
        continue
      }
      if (ch == "\\") { seg[ns] = seg[ns] ch nx; i++; continue }
      if (ch == "\047" || ch == "\"") { q = ch; seg[ns] = seg[ns] ch; continue }
      if (ch == "&" && (seg[ns] ~ /[<>]$/ || nx == ">")) { seg[ns] = seg[ns] ch; continue }
      if (ch ~ /[|&;\n]/) {
        s2 = ch; if ((ch == "|" || ch == "&") && (nx == ch || (ch == "|" && nx == "&"))) { s2 = ch nx; i++ }
        sep[ns] = s2; seg[++ns] = ""; continue
      }
      seg[ns] = seg[ns] ch
    }
    sep[ns] = ""
    o = ""
    for (k = 1; k <= ns; k++) {
      lead = seg[k]; sub(/[^ \t].*/, "", lead)
      body = substr(seg[k], length(lead) + 1)
      tail = body; sub(/.*[^ \t]/, "", tail)
      body = substr(body, 1, length(body) - length(tail))
      r = seg2rg(body, k > 1 && sep[k - 1] ~ /^\|&?$/)
      if (r == 1) o = o lead (mode == "mask" ? ":" : R) tail sep[k]
      else if (r == 2 && mode == "mask") o = o lead ":" tail sep[k]
      else o = o seg[k] sep[k]
    }
    print o
  }'
}

if [ "$verdict" = recursive ]; then
  cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null | tr -d '\r')"
  verdict="$(verdict_of "$(rewrite "$cmd" mask "$cwd")")"
  if [ -z "$verdict" ]; then
    rg_cmd="$(rewrite "$cmd" out "$cwd")"
    [ "$rg_cmd" = "$cmd" ] && exit 0   # every recursive grep reads only files
    printf '%s' "$input" | jq --arg c "$rg_cmd" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        updatedInput: (.tool_input + {command: $c}),
        additionalContext: ("search-tools ran the recursive grep as rg: `" + $c + "`. Unlike grep -r, rg skips files that .gitignore lists and hidden files; rerun with -uu to search those too.")
      }
    }'
    exit 0
  fi
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
