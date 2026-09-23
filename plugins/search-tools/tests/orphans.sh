#!/usr/bin/env bash
# Orphan-server decision in tgrep-serve.sh: snapshot + live sessions in, "<pid>|<root>" out.
# Pure: no process is started or killed. Needs Git Bash (cygpath). Run:
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

# Real `snapshot` output shape: the scoop shim and the real exe both serve each root.
crm='P|100
P|48328
P|32964
S|48328|C:\Users\me\scoop\shims\tgrep.exe serve D:/CRM
S|32964|"C:\Users\me\scoop\apps\tgrep\current\tgrep.exe"  serve D:/CRM'

check "no live session: both processes of the root are orphans" \
  "$(orphans "$crm" "")" \
  '48328|d:\crm
32964|d:\crm'

check "live session with cwd at the root: in use" \
  "$(orphans "$crm" '100|D:\CRM')" ''

check "live session with cwd under the root (any case, trailing backslash): in use" \
  "$(orphans "$crm" '100|d:\Crm\src\')" ''

check "non-ASCII root: session cwd and root lower-case the same way (ASCII only)" \
  "$(orphans 'P|100
P|9
S|9|tgrep.exe serve D:/Émile/Ωmega' '100|D:\Émile\Ωmega')" ''

check "CRLF session lines (Windows jq): a root in use on any line stays in use" \
  "$(orphans "$crm" "100|D:\CRM$cr
7|C:\other$cr")" ''

check "live session with cwd above the root: the root is not in use" \
  "$(orphans "$crm" '100|D:\')" \
  '48328|d:\crm
32964|d:\crm'

check "sibling that shares a prefix is not under the root" \
  "$(orphans "$crm" '100|D:\CRM-old')" \
  '48328|d:\crm
32964|d:\crm'

check "session file whose pid is gone does not count" \
  "$(orphans "$crm" '999|D:\CRM')" \
  '48328|d:\crm
32964|d:\crm'

check "kept root is never an orphan" \
  "$(orphans "$crm" '' 'd:\crm')" ''

two="$crm
S|500|C:\Users\me\scoop\shims\tgrep.exe serve \"C:\Work\Big Repo\\\"
P|500"

check "only the unused root is orphaned; quoted root with a space normalizes" \
  "$(orphans "$two" '100|D:\CRM')" \
  '500|c:\work\big repo'

check "non-serve tgrep processes are ignored" \
  "$(orphans 'P|7
S|7|tgrep.exe --stats -F probe' '')" ''

check "servers_for_root: every pid serving exactly that root" \
  "$(servers_for_root "$two" 'd:\crm')" \
  '48328
32964'

exit $fail
