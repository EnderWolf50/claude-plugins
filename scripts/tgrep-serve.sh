#!/usr/bin/env bash
# Keep a `tgrep serve` watcher alive only while a Claude session is using the repo.
#
#   tgrep-serve.sh start   (SessionStart hook)
#     Reap orphaned servers for *other* roots, then serve <root> when
#     <root>/.tgrep exists (opted in) or the repo has >= TGREP_SERVE_MIN_FILES
#     text files (default 5000). tgrep's serve.lock refuses duplicates.
#
#   tgrep-serve.sh stop    (SessionEnd hook)
#     Reap every server whose root no other live session is using, this
#     session excluded.
#
#   tgrep-serve.sh reap
#     Same sweep, nothing excluded — /search-tools:reap.
#
# A root is "in use" while a live Claude session (~/.claude/sessions/<pid>.json
# whose pid is in the process table) has its cwd at or under it, so a killed
# terminal or a crash never pins a server: the next start/stop anywhere reaps it.
# The index survives a kill: `serve` reconciles it against the tree on restart.
#
# Windows-only (tasklist/taskkill/cygpath/CIM). Process spawns are batched —
# one PowerShell call, one jq call — because every fork costs ~50 ms on MSYS.

set -u
command -v tgrep >/dev/null 2>&1 || exit 0

mode="${1:-start}"
root="${CLAUDE_PROJECT_DIR:-$PWD}"
min="${TGREP_SERVE_MIN_FILES:-5000}"
logdir="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/tgrep-logs}/logs"   # survives plugin updates
sessions="$HOME/.claude/sessions"

# Windows path, lower-cased, no trailing slash — the form sessions/*.json store.
norm() { cygpath -w "$1" 2>/dev/null | tr 'A-Z' 'a-z' | sed 's|[\\/]*$||'; }

server_pid() { tgrep status "$root" 2>/dev/null | awk '/^  PID:/{print $2}'; }

# One PowerShell call. Emits "P|<pid>" for every live process and
# "S|<pid>|<cmdline>" for every tgrep.exe (scoop shim and real exe both show).
snapshot() {
  powershell.exe -NoProfile -Command "
    Get-Process | ForEach-Object { 'P|' + \$_.Id }
    Get-CimInstance Win32_Process -Filter \"Name='tgrep.exe'\" |
      ForEach-Object { 'S|' + \$_.ProcessId + '|' + \$_.CommandLine }" 2>/dev/null | tr -d '\r'
}

# reap [session-id-to-ignore] [normalized-root-to-leave-alone]
reap() {
  local skip="${1:-}" keep="${2:-}" snap live="" line spid cmd r
  snap="$(snapshot)"
  live="$(printf '%s\n' "$snap" | sed -n 's/^P|//p' | tr '\n' ' ')"

  # cwd of every live session except the one to skip: one jq pass, lower-cased.
  local using=""
  set -- "$sessions"/*.json
  [ -f "$1" ] && using="$(jq -r --arg skip "$skip" 'select(.sessionId != $skip) | "\(.pid)|\(.cwd | ascii_downcase)"' "$@" 2>/dev/null)"

  local cwds="" spid2 cwd
  while IFS='|' read -r spid2 cwd; do
    [ -n "$spid2" ] || continue
    case " $live " in *" $spid2 "*) cwds="$cwds${cwd%\\}"$'\n' ;; esac
  done <<<"$using"

  printf '%s\n' "$snap" | sed -n 's/^S|//p' | while IFS='|' read -r spid cmd; do
    case "$cmd" in *" serve "*) ;; *) continue ;; esac
    r="${cmd#* serve }"; r="${r#"${r%%[! ]*}"}"; r="${r%"${r##*[! ]}"}"; r="${r%\"}"; r="${r#\"}"
    [ -n "$r" ] || continue
    r="$(norm "$r")"
    [ -n "$keep" ] && [ "$r" = "$keep" ] && continue
    local hit="" c
    while IFS= read -r c; do
      [ -n "$c" ] || continue
      case "$c" in "$r"|"$r"\\*) hit=1; break ;; esac
    done <<<"$cwds"
    [ -n "$hit" ] && continue
    taskkill //PID "$spid" //F >/dev/null 2>&1
  done
}

# Never index the home directory itself.
[ "$(norm "$root")" = "$(norm "$HOME")" ] && exit 0

case "$mode" in
start)
  reap "" "$(norm "$root")"
  [ -n "$(server_pid)" ] && exit 0

  if [ ! -d "$root/.tgrep" ]; then
    count="$(tgrep count-files "$root" 2>/dev/null | head -1)"
    case "$count" in ''|*[!0-9]*) exit 0 ;; esac
    [ "$count" -ge "$min" ] || exit 0
  fi

  # Keep the index out of git without touching the shared .gitignore.
  exclude="$(git -C "$root" rev-parse --path-format=absolute --git-path info/exclude 2>/dev/null)"
  if [ -n "$exclude" ] && ! grep -qx '.tgrep/' "$exclude" 2>/dev/null; then
    mkdir -p "$(dirname "$exclude")" && printf '.tgrep/\n' >>"$exclude"
  fi

  mkdir -p "$logdir"
  log="$logdir/$(printf '%s' "$root" | tr -c 'A-Za-z0-9' '_').log"
  nohup tgrep serve "$root" >"$log" 2>&1 </dev/null &
  disown 2>/dev/null || true

  echo "tgrep serve started for $root (log: $log). Run tgrep from that root so searches hit the server."
  ;;

stop)
  input="$(cat)"                                        # hook stdin
  # /clear ends the session id but the process stays in the repo.
  [ "$(printf '%s' "$input" | jq -r '.reason // empty')" = "clear" ] && exit 0
  reap "$(printf '%s' "$input" | jq -r '.session_id // empty')"
  ;;

reap)
  reap
  ;;
esac
