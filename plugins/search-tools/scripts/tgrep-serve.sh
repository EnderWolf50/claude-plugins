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
# Windows (Git Bash: PowerShell CIM, taskkill, cygpath), Linux and macOS (ps,
# kill, realpath); $OSTYPE picks the process and path functions below.
# Process spawns are batched — one snapshot call, one jq call — because every
# fork costs ~50 ms on MSYS.

set -u

root="${CLAUDE_PROJECT_DIR:-$PWD}"
min="${TGREP_SERVE_MIN_FILES:-5000}"
data="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/search-tools}"   # survives plugin updates
logdir="$data/logs"
optout="$data/opt-out"                                      # normalized roots, one per line
sessions="$HOME/.claude/sessions"

# Per OS:
#   norm <path>   a root or cwd in the form sessions/*.json store it, no trailing separator
#   sep           the path separator after norm
#   fold          sed script applied to session cwds so they compare like norm's output
#   snapshot      "P|<pid>" for every live process, "S|<pid>|<cmdline>" for every tgrep
#   kill_one <pid>
#   detach <cmd>  runs <cmd> in the background, surviving the hook's exit (caller redirects)
# Lower-casing is ASCII-only everywhere (bash ${x,,} mangles UTF-8 under MSYS).
lower='y/ABCDEFGHIJKLMNOPQRSTUVWXYZ/abcdefghijklmnopqrstuvwxyz/'
cr=$'\r'   # literal: BSD sed reads \r in a pattern as the letter r
case "$OSTYPE" in
msys* | cygwin*)
  sep='\' fold="$lower"
  norm() { cygpath -w "$1" 2>/dev/null | sed -e "$lower" -e 's|[\\/]*$||'; }

  # One PowerShell call (scoop shim and real exe both show).
  snapshot() {
    powershell.exe -NoProfile -Command "
      Get-Process | ForEach-Object { 'P|' + \$_.Id }
      Get-CimInstance Win32_Process -Filter \"Name='tgrep.exe'\" |
        ForEach-Object { 'S|' + \$_.ProcessId + '|' + \$_.CommandLine }" 2>/dev/null | tr -d '\r'
  }

  kill_one() { taskkill //PID "$1" //F >/dev/null 2>&1; }

  detach() { nohup "$@" </dev/null & disown 2>/dev/null || true; }
  ;;
*)
  # Physical path: Claude Code stores the session cwd with symlinks resolved.
  # macOS file systems are case-insensitive by default; Linux ones are not.
  sep='/' fold=''
  case "$OSTYPE" in darwin*) fold="$lower" ;; esac
  norm() {
    local p
    p="$(realpath "$1" 2>/dev/null)" || p="$1"
    [ "$p" = / ] || p="${p%/}"
    if [ -n "$fold" ]; then printf '%s\n' "$p" | sed "$fold"; else printf '%s\n' "$p"; fi
  }

  snapshot() {
    # -ww: BSD ps otherwise cuts args at 79 columns without a tty.
    ps -ww -eo pid=,args= 2>/dev/null | awk '{
      print "P|" $1
      exe = $2; sub(/.*\//, "", exe)
      if (exe != "tgrep") next
      cmd = $0; sub(/^[ \t]*[0-9]+[ \t]+/, "", cmd)
      print "S|" $1 "|" cmd
    }'
  }

  kill_one() { kill "$1" 2>/dev/null; }

  # setsid: a new session, so the hook's process-group teardown cannot reach it.
  detach() {
    if command -v setsid >/dev/null 2>&1; then setsid "$@" </dev/null &
    else nohup "$@" </dev/null &
    fi
    disown 2>/dev/null || true
  }
  ;;
esac

server_pid() { tgrep status "$root" 2>/dev/null | awk '/^  PID:/{print $2}'; }

opted_out() { [ -f "$optout" ] && grep -qxF "$1" "$optout"; }

# "<pid>|<normalized-root>" for every serve process in a snapshot.
servers_of() {
  local spid cmd r
  printf '%s\n' "$1" | sed -n 's/^S|//p' | while IFS='|' read -r spid cmd; do
    case "$cmd" in *" serve "*) ;; *) continue ;; esac
    r="${cmd#* serve }"; r="${r#"${r%%[! ]*}"}"; r="${r%"${r##*[! ]}"}"; r="${r%\"}"; r="${r#\"}"
    [ -n "$r" ] && echo "$spid|$(norm "$r")"
  done
}

# " <pid> <pid> … " for every live process in a snapshot, for `case " $pid "` lookups.
live_pids() { echo " $(printf '%s\n' "$1" | sed -n 's/^P|//p' | tr '\n' ' ') "; }

# orphans <snapshot> <sessions> [normalized-root-to-keep]
# <sessions> is "<pid>|<cwd>" per line. Prints "<pid>|<normalized-root>" for every
# server whose root no live session (pid in the snapshot) has its cwd at or under.
# Other lines (session_records' "!" records) never match a live pid.
orphans() {
  local snap="$1" keep="${3:-}" live cwds="" pid cwd spid r c hit under
  live="$(live_pids "$snap")"
  # Drop the CR of Windows jq's CRLF, then fold the case like norm does.
  while IFS='|' read -r pid cwd; do
    [ -n "$pid" ] || continue
    case "$live" in *" $pid "*) cwds="$cwds$cwd"$'\n' ;; esac
  done <<<"$(printf '%s' "$2" | sed -e "s/$cr\$//" ${fold:+-e "$fold"})"

  servers_of "$snap" | while IFS='|' read -r spid r; do
    [ -n "$keep" ] && [ "$r" = "$keep" ] && continue
    under="${r%"$sep"}$sep"                                 # "/" stays "/", not "//"
    hit=""
    while IFS= read -r c; do
      [ -n "$c" ] || continue
      case "$c" in "$r" | "$under"*) hit=1; break ;; esac
    done <<<"$cwds"
    [ -n "$hit" ] || echo "$spid|$r"
  done
}

# blocker <snapshot> <records> <recent-files>
# Records are session_records lines; <recent-files> lists session files modified in
# the last day. Prints "<file> (<reason>)" for the first blocking session file: an
# unreadable one whose pid is live, or that has no pid and is recent. A dead pid
# cannot pin a root, and a day-old unparsable file is a leftover, not a session
# being written. Files compare by name: jq and find may spell the dir differently.
blocker() {
  local live recent=" " f line pid why
  live="$(live_pids "$1")"
  while IFS= read -r f; do [ -n "$f" ] && recent="$recent${f##*/} "; done <<<"$3"
  while IFS='|' read -r line pid why; do
    case "$line" in !*) ;; *) continue ;; esac
    f="${line#!}"; f="${f##*/}"; f="${f##*\\}"; why="${why%"$cr"}"
    if [ -n "$pid" ]; then
      case "$live" in *" $pid "*) echo "$f (live session, $why)"; return ;; esac
    else
      case "$recent" in *" $f "*) echo "$f ($why, modified within a day)"; return ;; esac
    fi
  done <<<"$2"
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
  detach tgrep serve "$root" >"$log" 2>&1

  echo "tgrep serve started for $root (log: $log). Run tgrep from that root so searches hit the server."
}

# session_records <session-id-to-ignore>: one line per session file but the ignored
# one — "<pid>|<cwd>", or "!<file>|<pid or empty>|<reason>" when it cannot be read
# (see blocker). One jq pass; each file comes in whole as a string (--rawfile) and
# is parsed on its own, so a broken or empty file, a missing final newline, or jq's
# version-dependent exit status after an error cannot touch the other records. The
# ignored session is dropped before any check, so a stop never blocks on its own file.
# Fails with 1 when there is no session file at all, 2 when jq fails (e.g. a file
# removed between the glob and the read).
session_records() {
  local f i=0 args=()
  set -- "$1" "$sessions"/*.json
  [ -f "$2" ] || return 1
  for f in "${@:2}"; do args+=(--arg "p$i" "$f" --rawfile "f$i" "$f"); i=$((i + 1)); done
  jq -nr --arg skip "$1" --argjson n "$i" "${args[@]}" '
    range($n) as $i | $ARGS.named["p\($i)"] as $f
    | ($ARGS.named["f\($i)"] | try fromjson catch null) as $j
    | if ($j | type) != "object" then "!\($f)||unparsable"
      elif $j.sessionId == $skip then empty
      elif ($j.pid | type) != "number" then "!\($f)||no pid"
      elif ($j.cwd | type) != "string" then "!\($f)|\($j.pid)|no cwd"
      else "\($j.pid)|\($j.cwd)" end' 2>/dev/null || return 2
}

# Session files modified in the last day, when some record has no pid (else no fork).
recent_files() {
  case $'\n'"$1" in *$'\n!'*'||'*) find "$sessions" -name '*.json' -mmin -1440 2>/dev/null ;; esac
}

# why_not_reap <snapshot> <records> <session_records status>
# "blocked by <what>" when reaping must not happen, else nothing.
why_not_reap() {
  local b
  case "$3" in
  0) b="$(blocker "$1" "$2" "$(recent_files "$2")")" ;;
  1) b="no session files in $sessions" ;;
  *) b="a jq failure reading $sessions" ;;
  esac
  [ -z "$b" ] || echo "blocked by $b"
}

# One line to logs/reap.log, keeping the last 100 (tmp per pid: reaps may overlap).
reap_skipped() {
  local log="$logdir/reap.log"
  mkdir -p "$logdir"
  { tail -n 99 "$log" 2>/dev/null; echo "$(date '+%F %T') reap skipped: $1"; } >"$log.$$" && mv -f "$log.$$" "$log"
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
    [ -n "$pid" ] && kill_one "$pid"
  done
}

# reap [session-id-to-ignore] [normalized-root-to-keep]
reap() {
  local records rc snap why
  records="$(session_records "${1:-}")"; rc=$?
  snap="$(snapshot)"
  why="$(why_not_reap "$snap" "$records" "$rc")"
  if [ -n "$why" ]; then reap_skipped "$why"; return 0; fi
  orphans "$snap" "$records" "${2:-}" | kill_pids
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
    # and the snapshot alone takes longer on Windows: reap detached, return now.
    # Parsed without jq for the same reason — each fork costs ~0.5 s at exit.
    detach bash "$0" reap "$sid" >/dev/null 2>&1
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
    snap="$(snapshot)"
    echo "all tgrep servers on this machine (shim + exe both listed per root on Windows):"
    servers_of "$snap" | sed 's/^/  /'
    records="$(session_records "")"; rc=$?
    why="$(why_not_reap "$snap" "$records" "$rc")"
    echo
    echo "reap: ${why:-OK}"
    ;;
  esac
}

# Sourced (tests/orphans.sh) = functions only.
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
