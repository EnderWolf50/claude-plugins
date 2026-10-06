#!/usr/bin/env bash
# grep-guard.sh verdicts: a Bash command in; allow, deny, or rewrite (to rg) out. Run:
#   bash plugins/search-tools/tests/grep-guard.sh

set -u
here="$(cd "$(dirname "$0")" && pwd)"
guard="$here/../scripts/grep-guard.sh"
g=grep   # keeps this file's own commands clear of the guard

fail=0
# check <deny|allow> <command>   |   check rewrite <command> <expected rg command>
check() {
  local out got
  out="$(jq -n --arg c "$2" '{tool_input: {command: $c, description: "d"}}' | bash "$guard")"
  case "$out" in
    *'"deny"'*)      got=deny ;;
    *updatedInput*)  got="rewrite: $(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedInput.command')"
                     [ "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedInput.description')" = d ] || got="$got (description lost)"
                     printf '%s' "$out" | jq -e '.hookSpecificOutput | has("permissionDecision") | not' >/dev/null || got="$got (decides permission)" ;;
    *)               got=allow ;;
  esac
  local want="$1"; [ "$1" = rewrite ] && want="rewrite: $3"
  if [ "$got" = "$want" ]; then echo "ok   $want <- $2"
  else echo "FAIL want [$want], got [$got]: $2"; fail=1; fi
}

# A single recursive grep is rewritten to rg; permission checks still apply to the result.
check rewrite "$g -rn foo ."                          "rg -n foo ."
check rewrite "$g --recursive foo ."                  "rg foo ."
check rewrite "$g -rn \"some text\" ."                "rg -n \"some text\" ."
check rewrite "$g -rni --include='*.py' foo src"      "rg -n -i -g '*.py' foo src"
check rewrite "$g -r --exclude-dir=node_modules foo"  "rg -g '!node_modules/' foo"
check rewrite "$g -rl -A 3 foo"                       "rg -l -A 3 foo"
check rewrite "$g -rh -C2 foo lib"                    "rg -I -C 2 foo lib"
check rewrite "f$g -r a.b ."                          "rg -F a.b ."
# Anything the rewrite cannot map with confidence is refused as before.
check deny  "cd src && $g -R foo"
check deny  "$g -r -e foo ."
check deny  "$g -rq foo ."
check deny  "$g -rn foo . > out.txt"
check deny  "find . -name '*.py' | xargs $g foo"
check deny  "$(printf 'cat <<EOF
text
EOF
%s -rn foo .' "$g")"
check allow "$g foo file.txt"
check allow "cat x | $g -i foo"
check allow "git $g -n foo"
check allow "rg -n foo ."
check allow "ast-$g run -p 'foo(\$A)'"
# The words only appear as data: a quoted string or a heredoc body never runs.
check allow "python -c \"print('$g -r is a word')\""
check allow "echo '$g -rn foo .'"
check allow "git commit -m \"guard: refuse $g -r\""
check allow "$(printf 'python - <<%s
pats = {"%s -r": 1}
EOF
echo done' "'EOF'" "$g")"

exit $fail
