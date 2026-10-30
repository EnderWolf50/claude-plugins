#!/usr/bin/env bash
# PreToolUse (PowerShell) hook: denies a bash heredoc (<<EOF, <<'EOF', <<-EOF) in a PowerShell
# command. PowerShell has no heredoc: the parser fails, or the body runs as commands.
# Quoted strings (across lines too), # comments, <# #> blocks and here-string bodies
# (@' ... '@, @" ... "@) are data, never checked.

set -u
command -v jq >/dev/null 2>&1 || exit 0

cmd="$(jq -r '.tool_input.command // empty' 2>/dev/null | tr -d '\r')"   # Windows jq writes CRLF

case "$cmd" in *'<<'*) ;; *) exit 0 ;; esac

hit="$(printf '%s\n' "$cmd" | awk '
  # One pass over the characters; string, block-comment and here-string state carries across lines.
  {
    s = $0
    if (inhs) { if (substr(s, 1, 2) == close_) { inhs = 0; s = substr(s, 3) } else next }
    if (bc) { p = index(s, "#>"); if (!p) next; bc = 0; s = substr(s, p + 2) }
    n = length(s)
    for (i = 1; i <= n; i++) {
      c = substr(s, i, 1)
      if (q != "") {
        if (q == "\"" && c == "`") i++
        else if (c == q) q = ""
        continue
      }
      if (c == "\047" || c == "\"") { q = c; continue }
      if (c == "#" && (i == 1 || substr(s, i - 1, 1) ~ /[ \t;(]/)) break
      if (c == "<" && substr(s, i, 2) == "<#") { p = index(substr(s, i + 2), "#>"); if (!p) { bc = 1; break } i += p + 2; continue }
      if (c == "@" && substr(s, i + 1) ~ /^["\047][ \t]*$/ && (i == 1 || substr(s, i - 1, 1) !~ /[A-Za-z0-9_]/)) { close_ = substr(s, i + 1, 1) "@"; inhs = 1; break }
      if (c == "<" && substr(s, i, 2) == "<<" && substr(s, i + 2) ~ /^-?[ \t]*(["\047]|[A-Za-z_])/) { print "heredoc"; exit }
    }
  }')"

[ -n "$hit" ] || exit 0

jq -n --arg why "PowerShell has no bash heredoc (<<EOF, <<'EOF'), so this command would not run as written. For a multi-line string use a PowerShell here-string, with the closing '@ at column 0 on its own line: \$s = @'<newline>text<newline>'@. For a longer program, write it to a file with the Write tool and run it by path (pwsh -NoProfile -File <file>). To use a bash heredoc, send the command to the Bash tool instead." '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $why
  }
}'
