#!/usr/bin/env bash
# PreToolUse (Bash) hook: denies commands that change more than the agent knows about, with the
# narrower command to run instead.
#   git add -A / --all / . / :/       stage the paths you created or changed by name
#   git commit -a / --all / -am ...   same, then commit without -a
#   chezmoi apply --force (no target) diff and force-apply one drifted target at a time
#   \\ anywhere, on Windows           write the program to a file and run it by path
# Each segment of a compound command (&&, ||, ;, |, &, subshells) is checked on its own;
# heredoc bodies and quoted strings are data, never commands.

set -u
command -v jq >/dev/null 2>&1 || exit 0

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

cmd="$(jq -r '.tool_input.command // empty' 2>/dev/null | tr -d '\r')"   # Windows jq writes CRLF

# Claude Code's Bash tool on Windows turns every \\ into \ before bash sees the command, even
# inside single quotes and a quoted heredoc. GUARDS_PLATFORM stands in for uname (codex.js, tests).
case "${GUARDS_PLATFORM:-$(uname -s)}" in
  MINGW*|MSYS*|CYGWIN*)
    case "$cmd" in *'\\'*) deny "On Windows the Bash tool turns every \\\\ in a command into \\ before bash runs it, inside single quotes and quoted heredocs too, so this command would not run as written. Write the program or text with the Write tool to a file, then run it by path (\`python <file>\`, \`bash <file>\`, \`--body-file <file>\`)." ;; esac ;;
esac

case "$cmd" in *git*|*chezmoi*) ;; *) exit 0 ;; esac

verdict="$(printf '%s\n' "$cmd" | awk '
  inhd { t = $0; if (strip) sub(/^\t+/, "", t); if (t == delim) inhd = 0; next }
  {
    print
    if (match($0, /<<-?[ \t]*["\047]?[A-Za-z_][A-Za-z0-9_]*["\047]?/) && substr($0, RSTART - 1, 1) != "<") {
      d = substr($0, RSTART, RLENGTH); strip = (d ~ /^<<-/)
      sub(/^<<-?[ \t]*/, "", d); gsub(/["\047]/, "", d); delim = d; inhd = 1
    }
  }' | awk -v RS='\001' '
  function base(w) { sub(/.*\//, "", w); return w }
  function git(t, n,    i, sub_, a, k, ch) {
    for (i = 2; i <= n; i++) {                       # global options before the subcommand
      a = t[i]
      if (a ~ /^(-C|-c|--git-dir|--work-tree|--namespace|--super-prefix|--config-env|--attr-source)$/) { i++; continue }
      if (a ~ /^-/) continue
      break
    }
    if (i > n) return ""
    sub_ = t[i]
    for (i++; i <= n; i++) {
      a = t[i]
      if (sub_ == "add") {
        if (a == "-A" || a == "--all" || a == "--no-ignore-removal" || a == "." || a == "./" || a == ":/") return "add"
        if (a ~ /^-[A-Za-z]*A/) return "add"
      }
      if (sub_ == "commit") {
        if (a == "--") break
        if (a == "--all") return "commit"
        if (a ~ /^-[A-Za-z]/) {
          for (k = 2; k <= length(a); k++) {
            ch = substr(a, k, 1)
            if (ch == "a") return "commit"
            if (ch ~ /[mCcFt]/) { if (k == length(a)) i++; break }   # takes a value: -m msg, -mmsg
            if (ch ~ /[Su]/) break                                    # optional attached value: -uall
          }
        }
      }
    }
    return ""
  }
  function chezmoi(t, n,    i, a, sub_, force, target) {
    for (i = 2; i <= n; i++) {
      a = t[i]
      if (a == "--force") force = 1
      else if (a == "-n" || a == "--dry-run" || a ~ /^-[A-Za-z]*n[A-Za-z]*$/) return ""
      else if (a ~ /^(-[xicDoSW]|--(exclude|include|cache|color|config|config-format|destination|mode|output|override-data|override-data-file|persistent-state|progress|source|working-tree|age-recipient|age-recipient-file|use-builtin-age|use-builtin-git))$/ || a ~ /^-[A-Za-z]*[xicDoSW]$/) i++
      else if (a ~ /^-/) continue
      else if (sub_ == "") sub_ = a
      else target = 1
    }
    return (sub_ == "apply" && force && !target) ? "chezmoi" : ""
  }
  {
    s = $0
    gsub(/\047[^\047]*\047/, "\047\047", s)
    gsub(/"([^"\\]|\\.)*"/, "\"\"", s)
    gsub(/[0-9]*>&[0-9-]*|&>/, " > ", s)              # redirections, not separators
    nseg = split(s, seg, /&&|\|\||[;&|()`{}\n]/)
    for (j = 1; j <= nseg; j++) {
      n = split(seg[j], t, /[ \t]+/)
      if (t[1] == "") { for (i = 1; i < n; i++) t[i] = t[i + 1]; n-- }
      while (n > 0 && (t[1] ~ /^[A-Za-z_][A-Za-z0-9_]*=/ || t[1] ~ /^(!|\$|if|then|elif|else|do|while|until|time|command|exec|nohup|sudo|env)$/)) {
        for (i = 1; i < n; i++) t[i] = t[i + 1]; n--
      }
      if (n == 0) continue
      v = ""
      if (base(t[1]) == "git") v = git(t, n)
      else if (base(t[1]) == "chezmoi") v = chezmoi(t, n)
      if (v != "") { print v; exit }
    }
  }')"

case "$verdict" in
  add)     why="Stage the paths you created or changed by name: \`git add <path>...\`. \`git add -A\`, \`--all\` and \`.\` also stage files you did not touch: the user's work in progress, other sessions' changes, generated files." ;;
  commit)  why="Stage the paths you created or changed by name with \`git add <path>...\`, then run \`git commit\` without \`-a\`. \`-a\` also commits every tracked change you did not make." ;;
  chezmoi) why="Force-apply one target at a time: for each drifted target in \`chezmoi status\`, run \`chezmoi diff <target>\`, then \`chezmoi apply --force <target>\`. \`apply --force\` with no target overwrites every drifted file, including local edits nobody has reviewed." ;;
  *)       exit 0 ;;
esac

deny "$why"
