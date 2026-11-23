#!/usr/bin/env bash
# PreToolUse (Bash) hook: denies commands that change more than the agent knows about, with the
# narrower command to run instead.
#   git add -A / --all / . / :/       stage the paths you created or changed by name
#   git commit -a / --all / -am ...   same, then commit without -a
#   chezmoi apply --force (no target) diff and force-apply one drifted target at a time
#   taskkill /IM, pkill, killall      find the PID, check it, kill by PID
# and rewrites, Claude Code on Windows only:
#   \\ anywhere                       run the command from a file that holds it as written
# Each segment of a compound command (&&, ||, ;, |, &, subshells) is checked on its own;
# for the deny rules, heredoc bodies and quoted strings are data, never commands.
# The rule text is in rules.json.

set -u
command -v jq >/dev/null 2>&1 || exit 0
case "${BASH_SOURCE[0]}" in */*|*\\*) . "${BASH_SOURCE[0]%[/\\]*}/rules.sh" ;; *) . ./rules.sh ;; esac

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null | tr -d '\r')"   # Windows jq writes CRLF

# Claude Code's Bash tool on Windows turns every \\ into \ before bash sees the command, even
# inside single quotes and a quoted heredoc. Codex is not known to, so codex.js sets GUARDS_HOST.
halved=""
case "$cmd" in *'\\'*) [ "${GUARDS_HOST:-}" != codex ] && windows && halved=1 ;; esac

case "$cmd" in *git*|*chezmoi*|*[Kk][Ii][Ll][Ll]*) scan=1 ;; *) scan="" ;; esac
[ -n "$scan$halved" ] || exit 0

verdict=""
[ -z "$scan" ] || verdict="$(printf '%s\n' "$cmd" | awk '
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
  function taskkill(t, n,    i) {
    for (i = 2; i <= n; i++) if (tolower(t[i]) ~ /^(\/\/?|-)im$/) return "kill"   # Git Bash writes /IM as //IM
    return ""
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
      v = ""; b = tolower(base(t[1])); sub(/\.exe$/, "", b)
      if (b == "git") v = git(t, n)
      else if (b == "chezmoi") v = chezmoi(t, n)
      else if (b == "taskkill") v = taskkill(t, n)
      else if (b == "pkill" || b == "killall") v = "kill"
      if (v != "") { print v; exit }
    }
  }')"

[ -n "$verdict" ] && deny "$(rule "$verdict")"
[ -n "$halved" ] || exit 0

# The hook gets the command before the Bash tool halves it, so the file holds it byte for byte.
# The tool then runs `source <file>`: no backslash left in the command to halve, and the file runs
# in the tool's own shell, from the same directory, so a cd in it carries to the next command as
# the command's own would. Anything that fails on the way falls back to the denial.
dir="${TMPDIR:-/tmp}/claude-guards"
mkdir -p "$dir" 2>/dev/null || deny "$(rule backslash)"
find=/usr/bin/find; [ -x "$find" ] || find=find   # not Windows' find.exe from PATH
"$find" "$dir" -type f -name 'cmd.*' -mmin +1440 -delete 2>/dev/null   # a day's files are kept
file="$(mktemp "$dir/cmd.XXXXXX" 2>/dev/null)" || deny "$(rule backslash)"
if jq -b -n 1 >/dev/null 2>&1; then
  printf '%s' "$input" | jq -bj '.tool_input.command' > "$file" || deny "$(rule backslash)"   # -b: no CRLF on Windows
else
  printf '%s' "$input" | jq -j '.tool_input.command' | tr -d '\r' > "$file" || deny "$(rule backslash)"
fi
printf '\n' >> "$file"
path="$(cygpath -m "$file" 2>/dev/null)" || path="$file"   # C:/... reads the same in every shell
case "$path" in *"'"*|*'\'*) deny "$(rule backslash)" ;; esac

printf '%s' "$input" | jq --arg c "source '$path'" --arg why "$(rule rewrite)" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    updatedInput: (.tool_input + {command: $c}),
    additionalContext: ("guards: " + $why + " This command is in `" + ($c | ltrimstr("source ")) + "`.")
  }
}'
