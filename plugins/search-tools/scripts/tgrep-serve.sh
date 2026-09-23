#!/usr/bin/env bash
# Keep a `tgrep serve` server alive only while a live Claude session has its cwd in the root.
#
#   tgrep-serve.sh start   (SessionStart hook)
#     Reap orphaned servers for *other* roots, then serve <root> when it is
#     opted in (<root>/.tgrep exists) or has >= TGREP_SERVE_MIN_FILES text
#     files (default 5000) and is not opted out. serve.lock refuses duplicates.
#
#   tgrep-serve.sh stop    (SessionEnd hook)
#     Reap every server whose root no other live session is using, this
#     session excluded. Runs detached (`reap <session-id>`) so the hook
#     returns inside the SessionEnd budget.
#
#   tgrep-serve.sh on | off | status | reap      (/search-tools:tgrep)
#     on      opt <root> in (build the index, forget any opt-out) and serve now
#     off     opt <root> out, stop its server, delete <root>/.tgrep
#     status  health check for <root> + every server on the machine
#     reap    reap orphan servers, no session excluded
#
# A root is "in use" while a live Claude session (~/.claude/sessions/<pid>.json
# whose pid is in the process table) has its cwd at or under it, so a killed
# terminal or a crash never pins a server: the next start/stop anywhere reaps it.
# The index survives a kill: `serve` reconciles it against the tree on restart.
#
# Windows-only (tasklist/taskkill/cygpath/CIM). Process spawns are batched —
# one PowerShell call, one jq call — because every fork costs ~50 ms on MSYS.

set -u

root="${CLAUDE_PROJECT_DIR:-$PWD}"
min="${TGREP_SERVE_MIN_FILES:-5000}"
data="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/search-tools}"   # survives plugin updates
logdir="$data/logs"
optout="$data/opt-out"                                      # normalized roots, one per line
sessions="$HOME/.claude/sessions"

# Windows path, lower-cased, no trailing slash — the form sessions/*.json store.
norm() { cygpath -w "$1" 2>/dev/null | tr 'A-Z' 'a-z' | sed 's|[\\/]*$||'; }

server_pid() { tgrep status "$root" 2>/dev/null | awk '/^  PID:/{print $2}'; }

opted_out() { [ -f "$optout" ] && grep -qxF "$1" "$optout"; }

# One PowerShell call. Emits "P|<pid>" for every live process and
# "S|<pid>|<cmdline>" for every tgrep.exe (scoop shim and real exe both show).
snapshot() {
  powershell.exe -NoProfile -Command "
    Get-Process | ForEach-Object { 'P|' + \$_.Id }
    Get-CimInstance Win32_Process -Filter \"Name='tgrep.exe'\" |
      ForEach-Object { 'S|' + \$_.ProcessId + '|' + \$_.CommandLine }" 2>/dev/null | tr -d '\r'
}

# "<pid>|<normalized-root>" for every serve process in a snapshot.
servers_of() {
  local spid cmd r
  printf '%s\n' "$1" | sed -n 's/^S|//p' | while IFS='|' read -r spid cmd; do
    case "$cmd" in *" serve "*) ;; *) continue ;; esac
    r="${cmd#* serve }"; r="${r#"${r%%[! ]*}"}"; r="${r%"${r##*[! ]}"}"; r="${r%\"}"; r="${r#\"}"
    [ -n "$r" ] && echo "$spid|$(norm "$r")"
  done
}

# orphans <snapshot> <sessions> [normalized-root-to-keep]
# <sessions> is "<pid>|<cwd>" per line. Prints "<pid>|<normalized-root>" for every
# server whose root no live session (pid in the snapshot) has its cwd at or under.
orphans() {
  local snap="$1" keep="${3:-}" live cwds="" pid cwd spid r c hit
  live=" $(printf '%s\n' "$snap" | sed -n 's/^P|//p' | tr '\n' ' ') "
  # ASCII-only lower-casing, the same as norm; bash ${x,,} mangles UTF-8 here.
  while IFS='|' read -r pid cwd; do
    [ -n "$pid" ] || continue
    case "$live" in *" $pid "*) cwds="$cwds$cwd"$'\n' ;; esac
  done <<<"$(printf '%s' "$2" | tr 'A-Z' 'a-z')"

  servers_of "$snap" | while IFS='|' read -r spid r; do
    [ -n "$keep" ] && [ "$r" = "$keep" ] && continue
    hit=""
    while IFS= read -r c; do
      [ -n "$c" ] || continue
      case "$c" in "$r"|"$r"\\*) hit=1; break ;; esac
    done <<<"$cwds"
    [ -n "$hit" ] || echo "$spid|$r"
  done
}

# Start a server for <root> if none runs. Prints one line on start.
serve_now() {
  [ -n "$(server_pid)" ] && return 0

  # Keep the index out of git without touching the shared .gitignore.
  local exclude
  exclude="$(git -C "$root" rev-parse --path-format=absolute --git-path info/exclude 2>/dev/null)"
  if [ -n "$exclude" ] && ! grep -qx '.tgrep/' "$exclude" 2>/dev/null; then
    mkdir -p "$(dirname "$exclude")" && printf '.tgrep/\n' >>"$exclude"
  fi

  mkdir -p "$logdir"
  local log="$logdir/$(printf '%s' "$root" | tr -c 'A-Za-z0-9' '_').log"
  nohup tgrep serve "$root" >"$log" 2>&1 </dev/null &
  disown 2>/dev/null || true

  echo "tgrep serve started for $root (log: $log). Run tgrep from that root so searches hit the server."
}

# "<pid>|<cwd>" for every session file except <session-id-to-ignore>: one jq pass.
sessions_except() {
  set -- "$1" "$sessions"/*.json
  [ -f "$2" ] || return 0
  jq -r --arg skip "$1" 'select(.sessionId != $skip) | "\(.pid)|\(.cwd)"' "${@:2}" 2>/dev/null
}

# servers_for_root <snapshot> <normalized-root>: pids serving exactly that root.
servers_for_root() {
  local spid r
  servers_of "$1" | while IFS='|' read -r spid r; do
    [ "$r" = "$2" ] && echo "$spid"
  done
}

kill_pids() {
  local pid
  while IFS='|' read -r pid _; do
    [ -n "$pid" ] && taskkill //PID "$pid" //F >/dev/null 2>&1
  done
}

# reap [session-id-to-ignore] [normalized-root-to-keep]
reap() {
  orphans "$(snapshot)" "$(sessions_except "${1:-}")" "${2:-}" | kill_pids
}

main() {
  command -v tgrep >/dev/null 2>&1 || exit 0
  mode="${1:-start}"

  # stop and reap act machine-wide, so they skip the <root> checks below.
  case "$mode" in
  stop)
    IFS= read -r -d '' input || true                      # hook stdin
    # /clear ends the session id but the process stays in the root.
    [[ $input =~ \"reason\"[[:space:]]*:[[:space:]]*\"clear\" ]] && exit 0
    sid=""
    [[ $input =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && sid="${BASH_REMATCH[1]}"
    # SessionEnd hooks share a 1.5 s budget (plugin `timeout` does not raise it)
    # and the PowerShell snapshot alone takes longer: reap detached, return now.
    # Parsed without jq for the same reason — each fork costs ~0.5 s at exit.
    nohup bash "$0" reap "$sid" >/dev/null 2>&1 </dev/null &
    disown 2>/dev/null || true
    exit 0
    ;;
  reap)
    reap "${2:-}"
    exit 0
    ;;
  esac

  # Never index the home directory itself.
  [ "$(norm "$root")" = "$(norm "$HOME")" ] && exit 0
  me_root="$(norm "$root")"

  case "$mode" in
  start)
    reap "" "$me_root"
    opted_out "$me_root" && exit 0
    if [ ! -d "$root/.tgrep" ]; then
      count="$(tgrep count-files "$root" 2>/dev/null | head -1)"
      case "$count" in ''|*[!0-9]*) exit 0 ;; esac
      [ "$count" -ge "$min" ] || exit 0
    fi
    serve_now
    ;;

  on)
    if [ -f "$optout" ]; then
      grep -vxF "$me_root" "$optout" >"$optout.tmp" 2>/dev/null; mv -f "$optout.tmp" "$optout"
    fi
    [ -d "$root/.tgrep" ] || tgrep index "$root" >/dev/null 2>&1
    echo "opted in: $root (index at $root/.tgrep)"
    serve_now
    [ -n "$(server_pid)" ] && echo "server running (pid $(server_pid))"
    ;;

  off)
    mkdir -p "$data"
    opted_out "$me_root" || printf '%s\n' "$me_root" >>"$optout"
    servers_for_root "$(snapshot)" "$me_root" | kill_pids
    rm -rf "$root/.tgrep"
    echo "opted out: $root (server stopped, index removed; \`tgrep\` here brute-forces until \`on\`)"
    ;;

  status)
    echo "root: $root"
    if opted_out "$me_root"; then
      echo "policy: opted out"
    elif [ -d "$root/.tgrep" ]; then
      echo "policy: opted in (.tgrep present)"
    else
      count="$(tgrep count-files "$root" 2>/dev/null | head -1)"
      echo "policy: automatic — $count text files, threshold $min → $([ "${count:-0}" -ge "$min" ] 2>/dev/null && echo serve || echo skip)"
    fi
    echo
    tgrep status "$root" 2>&1 | sed 's/^/  /'
    echo
    # Health: does a search issued from <root> actually hit the server?
    if [ -n "$(server_pid)" ]; then
      plan="$(cd "$root" && tgrep --stats -F 'zqxjkvw_probe' 2>&1 | tail -1)"
      case "$plan" in *"via server"*) echo "health: OK — search from root goes via server ($plan)" ;;
                      *) echo "health: DEGRADED — search from root did not use the server: $plan" ;; esac
      log="$logdir/$(printf '%s' "$root" | tr -c 'A-Za-z0-9' '_').log"
      [ -f "$log" ] && { echo "log tail ($log):"; tail -3 "$log" | sed 's/^/  /'; }
    else
      echo "health: no server for this root"
    fi
    echo
    echo "all tgrep servers on this machine (shim + exe both listed per root):"
    servers_of "$(snapshot)" | sed 's/^/  /'
    ;;
  esac
}

# Sourced (tests/orphans.sh) = functions only.
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
