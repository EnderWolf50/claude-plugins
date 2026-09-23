#!/usr/bin/env bash
# Orphan-server decision in tgrep-serve.sh: snapshot + live sessions in, "<pid>|<root>" out.
# Pure: no process is started or killed. Same scenarios on every OS; the fixtures
# follow $OSTYPE (Windows paths under Git Bash, real temp dirs on Linux/macOS). Run:
#   bash plugins/search-tools/tests/orphans.sh

set -u
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../scripts/tgrep-serve.sh"

fail=0
cr=$'\r'   # set here: Git Bash yields '' for $'\r' written inside "$(…)"
# check <name> <actual> <expected> — order-insensitive, one item per line
check() {
  local got want
  got="$(printf '%s\n' "$2" | sed '/^$/d' | sort)"
  want="$(printf '%s\n' "$3" | sed '/^$/d' | sort)"
  if [ "$got" = "$want" ]; then echo "ok   $1"
  else echo "FAIL $1"; echo "  want: $(echo $want)"; echo "  got:  $(echo $got)"; fail=1; fi
}

# Fixtures. shim/exe = how `snapshot` shows the tgrep binary, arg = root as a serve
# command line carries it, root = its normalized form, at/under/above/sib = session
# cwds, big = a root with a space, uni = a non-ASCII root, r_* = a root ending in "r",
# top_* = the file-system top.
tmp="" sdir=""
trap 'rm -rf "$tmp" "$sdir"' EXIT
case "$OSTYPE" in
msys* | cygwin*)
  # Real shapes: the scoop shim and the real exe both serve each root.
  shim='C:\Users\me\scoop\shims\tgrep.exe' exe='"C:\Users\me\scoop\apps\tgrep\current\tgrep.exe" '
  arg='D:/CRM' root='d:\crm'
  at='D:\CRM' under='d:\Crm\src\' above='D:\' sib='D:\CRM-old'
  big_arg='"C:\Work\Big Repo\"' big='c:\work\big repo'
  uni_arg='D:/Émile/Ωmega' uni_cwd='D:\Émile\Ωmega'
  r_arg='D:/foo-bar' r_cwd='D:\foo-bar'
  top_arg='C:/' top_cwd='C:\Users'
  ;;
*)
  shim='tgrep' exe='/usr/local/bin/tgrep '
  # Fixed lower-case name: macOS resolves /tmp to /private/tmp and lower-cases.
  tmp="/tmp/search-tools-orphans-$$"
  mkdir -p "$tmp/crm/src" "$tmp/crm-old" "$tmp/Big Repo" "$tmp/Émile/Ωmega" "$tmp/foo-bar"
  ln -s "$tmp/crm" "$tmp/link"
  phys="$(cd "$tmp" && pwd -P)"
  arg="$tmp/crm" root="$phys/crm"
  at="$phys/crm" under="$phys/crm/src/" above="$phys" sib="$phys/crm-old"
  big_arg="$tmp/Big Repo" big="$phys/Big Repo"
  uni_arg="$tmp/Émile/Ωmega" uni_cwd="$phys/Émile/Ωmega"
  r_arg="$tmp/foo-bar" r_cwd="$phys/foo-bar"
  top_arg='/' top_cwd="$phys"
  case "$OSTYPE" in darwin*) big="$phys/big repo" ;; esac
  ;;
esac

crm="P|100
P|48328
P|32964
S|48328|$shim serve $arg
S|32964|$exe serve $arg"

check "no live session: both processes of the root are orphans" \
  "$(orphans "$crm" "")" \
  "48328|$root
32964|$root"

check "live session with cwd at the root: in use" \
  "$(orphans "$crm" "100|$at")" ''

check "live session with cwd under the root: in use" \
  "$(orphans "$crm" "100|$under")" ''

check "non-ASCII root: session cwd and root normalize the same way" \
  "$(orphans "P|100
P|9
S|9|tgrep serve $uni_arg" "100|$uni_cwd")" ''

check "CRLF session lines (Windows jq): a root in use on any line stays in use" \
  "$(orphans "$crm" "100|$at$cr
7|$sib$cr")" ''

check "a cwd ending in \"r\" is not mistaken for a CR (BSD sed)" \
  "$(orphans "P|100
P|9
S|9|$shim serve $r_arg" "100|$r_cwd")" ''

check "the file-system top as root: any cwd is under it" \
  "$(orphans "P|100
P|9
S|9|$shim serve $top_arg" "100|$top_cwd")" ''

check "live session with cwd above the root: the root is not in use" \
  "$(orphans "$crm" "100|$above")" \
  "48328|$root
32964|$root"

check "sibling that shares a prefix is not under the root" \
  "$(orphans "$crm" "100|$sib")" \
  "48328|$root
32964|$root"

check "session file whose pid is gone does not count" \
  "$(orphans "$crm" "999|$at")" \
  "48328|$root
32964|$root"

check "kept root is never an orphan" \
  "$(orphans "$crm" '' "$root")" ''

two="$crm
S|500|tgrep serve $big_arg
P|500"

check "only the unused root is orphaned; a root with a space normalizes" \
  "$(orphans "$two" "100|$at")" \
  "500|$big"

check "non-serve tgrep processes are ignored" \
  "$(orphans 'P|7
S|7|tgrep --stats -F probe' '')" ''

check "servers_for_root: every pid serving exactly that root" \
  "$(servers_for_root "$two" "$root")" \
  '48328
32964'

case "$OSTYPE" in
msys* | cygwin*) ;;
*)
  check "server started on a symlinked root: the session's physical cwd keeps it in use" \
    "$(orphans "P|100
P|9
S|9|tgrep serve $tmp/link" "100|$at")" ''
  ;;
esac

case "$OSTYPE" in
darwin*)
  check "macOS: a cwd that differs only in case is the same root" \
    "$(orphans "$crm" "100|$phys/CRM")" ''
  ;;
esac

# blocker <snapshot> <records> <recent-files>: the first blocking session file, or nothing.
# Records are "<pid>|<cwd>" or "!<file>|<pid or empty>|<reason>".
snap9='P|9
P|100'
check "no unreadable record: nothing blocks" \
  "$(blocker "$snap9" '100|/x' '')" ''

check "live pid, cwd unreadable: blocks" \
  "$(blocker "$snap9" '!/s/100.json|100|no cwd' '')" \
  '100.json (live session, no cwd)'

check "dead pid, cwd unreadable: ignored" \
  "$(blocker "$snap9" '!/s/555.json|555|no cwd' '')" ''

check "no pid, modified within a day: blocks (recent list may spell the dir differently)" \
  "$(blocker "$snap9" '!C:/s/7.json||unparsable' '/c/s/7.json')" \
  '7.json (unparsable, modified within a day)'

check "no pid, older than a day: ignored" \
  "$(blocker "$snap9" '!/s/7.json||unparsable' '/s/other.json')" ''

check "CRLF records: still blocks" \
  "$(blocker "$snap9" "100|/x$cr
!/s/100.json|100|no cwd$cr" '')" \
  '100.json (live session, no cwd)'

# session_records <session-id-to-ignore>: one record per session file (names only
# compared: jq may print the dir as C:/…); fails when there is no session file at all.
sdir="$(mktemp -d)"
sessions="$sdir/sessions"
status_of() { "$@" >/dev/null 2>&1 && echo ok || echo refused; }
records_of() { session_records "$1" | tr -d '\r' | sed 's|^!.*/|!|'; }

check "sessions dir missing: refused" "$(status_of session_records '')" refused

mkdir "$sessions"
check "sessions dir without session files: refused" "$(status_of session_records '')" refused

printf '{"pid":100,"sessionId":"a","cwd":"/x"}' >"$sessions/100.json"
printf '{"pid":200,"sessionId":"b","cwd":"/y"}' >"$sessions/200.json"
check "every other session is listed; the ending one is left out" "$(records_of b)" '100|/x'

check "only the ending session left: nothing listed, not refused" \
  "$(rm "$sessions/100.json"; status_of session_records b)" ok

printf '{"pid":300,"sessionId":"c"}' >"$sessions/1.json"
check "a file without cwd: a ! record with its pid, sorting before a good one" \
  "$(records_of '')" '!1.json|300|no cwd
200|/y'
rm "$sessions/1.json"

printf '{"pid":300,"sessionId":"end"}' >"$sessions/1.json"
check "the ending session's own file is left out even without cwd (stop must not block itself)" \
  "$(records_of end)" '200|/y'
rm "$sessions/1.json"

printf '{"sessionId":"c","cwd":"/z"}' >"$sessions/300.json"
check "a file without pid: a ! record, no pid" "$(records_of '')" '!300.json||no pid
200|/y'

printf '{"pid":300,' >"$sessions/300.json"
check "a truncated file: unparsable" "$(records_of '')" '!300.json||unparsable
200|/y'

: >"$sessions/300.json"
check "an empty file: unparsable" "$(records_of '')" '!300.json||unparsable
200|/y'
rm "$sessions/300.json"

# reap through stand-in adapters.
logdir="$sdir/logs"
snapshot() { printf 'P|9\nP|300\nS|9|tgrep serve /nowhere\n'; }
kill_pids() { cat >>"$sdir/killed"; }

printf '{"pid":300,"sessionId":"c"}' >"$sessions/300.json"
reap ''
check "reap blocked by a live session without cwd: kills nothing" "$(cat "$sdir/killed" 2>/dev/null)" ''
check "reap blocked: logs the blocking file" "$(grep -c 'blocked by 300.json (live session, no cwd)' "$logdir/reap.log")" 1

printf '{"pid":555,"sessionId":"d"}' >"$sessions/300.json"
reap ''
check "reap past a dead session without cwd: the orphan is killed" "$(cut -d'|' -f1 "$sdir/killed")" 9
rm -f "$sdir/killed"

printf '{"pid":300,' >"$sessions/300.json"
reap ''
check "reap blocked by a recent unparsable file" "$(cat "$sdir/killed" 2>/dev/null)" ''
touch -t 202001010000 "$sessions/300.json"
reap ''
check "reap past a day-old unparsable file" "$(cut -d'|' -f1 "$sdir/killed")" 9
rm -f "$sdir/killed" "$sessions/300.json"

jq() { return 2; }   # e.g. a session file removed between the glob and jq's read
reap ''
unset -f jq
check "reap when jq fails: kills nothing" "$(cat "$sdir/killed" 2>/dev/null)" ''
check "reap when jq fails: says so, not 'no session files'" \
  "$(tail -1 "$logdir/reap.log" | grep -c 'blocked by a jq failure')" 1

rm "$sessions"/*.json
reap ''
check "reap with no session file: kills nothing" "$(cat "$sdir/killed" 2>/dev/null)" ''
check "no session files reads as a block too" \
  "$(tail -1 "$logdir/reap.log" | grep -c 'reap skipped: blocked by no session files')" 1

for i in $(seq 150); do echo "old $i"; done >"$logdir/reap.log"
reap ''
check "reap.log keeps the last 100 lines" "$(wc -l <"$logdir/reap.log" | tr -d ' ')" 100
check "reap.log: the newest line is the last" "$(tail -1 "$logdir/reap.log" | grep -c 'blocked by no session files')" 1

exit $fail
