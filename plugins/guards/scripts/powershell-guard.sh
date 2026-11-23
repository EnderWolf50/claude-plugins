#!/usr/bin/env bash
# PreToolUse (PowerShell) hook: denies, with the command to run instead,
#   a bash heredoc (<<EOF, <<'EOF', <<-EOF)   PowerShell has none: the parser fails, or the body
#                                             runs as commands
#   Stop-Process -Name (kill, spps), taskkill /IM, pkill, killall
#                                             find the PID, check it, kill by PID
# Quoted strings (across lines too), # comments, <# #> blocks and here-string bodies
# (@' ... '@, @" ... "@) are data, never checked. The rule text is in rules.json.

set -u
command -v jq >/dev/null 2>&1 || exit 0
case "${BASH_SOURCE[0]}" in */*|*\\*) . "${BASH_SOURCE[0]%[/\\]*}/rules.sh" ;; *) . ./rules.sh ;; esac

cmd="$(jq -r '.tool_input.command // empty' 2>/dev/null | tr -d '\r')"   # Windows jq writes CRLF

case "$cmd" in *'<<'*|*[Kk][Ii][Ll][Ll]*|*[Ss][Pp][Pp][Ss]*|*[Ss][Tt][Oo][Pp]-*) ;; *) exit 0 ;; esac

hit="$(printf '%s\n' "$cmd" | awk '
  # One pass over the characters; string, block-comment and here-string state carries across lines.
  # The code outside them (a string kept as empty quotes) goes to `code`, checked for kills at END.
  {
    s = $0
    if (inhs) { if (substr(s, 1, 2) == close_) { inhs = 0; s = substr(s, 3) } else next }
    if (bc) { p = index(s, "#>"); if (!p) next; bc = 0; s = substr(s, p + 2) }
    n = length(s)
    for (i = 1; i <= n; i++) {
      c = substr(s, i, 1)
      if (q != "") {
        if (q == "\"" && c == "`") i++
        else if (c == q) { q = ""; code = code c }
        continue
      }
      if (c == "\047" || c == "\"") { q = c; code = code c; continue }
      if (c == "#" && (i == 1 || substr(s, i - 1, 1) ~ /[ \t;(]/)) break
      if (c == "<" && substr(s, i, 2) == "<#") { p = index(substr(s, i + 2), "#>"); if (!p) { bc = 1; break } i += p + 2; continue }
      if (c == "@" && substr(s, i + 1) ~ /^["\047][ \t]*$/ && (i == 1 || substr(s, i - 1, 1) !~ /[A-Za-z0-9_]/)) { close_ = substr(s, i + 1, 1) "@"; inhs = 1; code = code "\"\""; break }
      if (c == "<" && substr(s, i, 2) == "<<" && substr(s, i + 2) ~ /^-?[ \t]*(["\047]|[A-Za-z_])/) { print "heredoc"; done = 1; exit }
      code = code c
    }
    code = code (q == "" ? "\n" : "")
  }
  # a prefix of the parameter name, at least min characters long, as PowerShell accepts it
  function param(a, name, min) { sub(/:.*/, "", a); return length(a) >= min && index(name, a) == 1 }
  END {
    if (done) exit
    nseg = split(code, seg, /[;|&(){}\n]/)
    for (j = 1; j <= nseg; j++) {
      n = split(seg[j], t, /[ \t]+/)
      if (t[1] == "") { for (k = 1; k < n; k++) t[k] = t[k + 1]; n-- }
      if (n == 0) continue
      b = tolower(t[1]); sub(/.*[\/\\]/, "", b); sub(/\.exe$/, "", b)
      for (k = 2; k <= n; k++) {
        a = tolower(t[k])
        if ((b == "stop-process" || b == "spps" || b == "kill") && (param(a, "-name", 2) || param(a, "-processname", 3))) { print "kill"; exit }
        if (b == "taskkill" && a ~ /^[\/-]im$/) { print "kill"; exit }
      }
      if (b == "pkill" || b == "killall") { print "kill"; exit }
    }
  }')"

[ -n "$hit" ] || exit 0
deny "$(rule "$hit")"
