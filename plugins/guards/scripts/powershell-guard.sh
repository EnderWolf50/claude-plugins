#!/usr/bin/env bash
# PreToolUse (PowerShell) hook: denies a bash heredoc (<<EOF, <<'EOF', <<-EOF) in a PowerShell
# command. PowerShell has no heredoc: the parser fails, or the body runs as commands.
# Here-string bodies (@' ... '@, @" ... "@) and quoted strings are data, never checked.

set -u
command -v jq >/dev/null 2>&1 || exit 0

cmd="$(jq -r '.tool_input.command // empty' 2>/dev/null | tr -d '\r')"   # Windows jq writes CRLF

case "$cmd" in *'<<'*) ;; *) exit 0 ;; esac

hit="$(printf '%s\n' "$cmd" | awk '
  inhs { if ($0 ~ ("^" close_)) inhs = 0; next }
  {
    s = $0
    if (match(s, /@["\047][ \t]*$/)) { close_ = (substr(s, RSTART + 1, 1) == "\047") ? "\047@" : "\"@"; inhs = 1; s = substr(s, 1, RSTART - 1) }
    gsub(/<<-?[ \t]*["\047][A-Za-z_][A-Za-z0-9_]*["\047]/, "<<HEREDOC", s)   # quoted delimiter, before strings are blanked
    gsub(/\047[^\047]*\047/, "\047\047", s)
    gsub(/"[^"]*"/, "\"\"", s)
    if (s ~ /<<-?[ \t]*["\047]?[A-Za-z_]/) { print "heredoc"; exit }
  }')"

[ -n "$hit" ] || exit 0

jq -n --arg why "PowerShell has no bash heredoc (<<EOF, <<'EOF'), so this command would not run as written. For a multi-line string use a PowerShell here-string, with the closing '@ at column 0 on its own line: \$s = @'<newline>text<newline>'@. For a longer program, write it to a file with the Write tool and run it by path (pwsh -NoProfile -File <file>). To use a bash heredoc, send the command to the Bash tool instead." '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $why
  }
}'
