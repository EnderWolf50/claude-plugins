#!/usr/bin/env bash
# grep-guard.sh verdicts: a Bash command in, deny or allow out. Run:
#   bash plugins/search-tools/tests/grep-guard.sh

set -u
here="$(cd "$(dirname "$0")" && pwd)"
guard="$here/../scripts/grep-guard.sh"
g=grep   # keeps this file's own commands clear of the guard

fail=0
# check <deny|allow> <command>
check() {
  local out got
  out="$(jq -n --arg c "$2" '{tool_input: {command: $c}}' | bash "$guard")"
  case "$out" in *'"deny"'*) got=deny ;; *) got=allow ;; esac
  if [ "$got" = "$1" ]; then echo "ok   $1: $2"
  else echo "FAIL want $1, got $got: $2"; fail=1; fi
}

check deny  "$g -rn foo ."
check deny  "cd src && $g -R foo"
check deny  "$g --recursive foo ."
check deny  "$g -rn \"some text\" ."
check deny  "find . -name '*.py' | xargs $g foo"
check allow "$g foo file.txt"
check allow "cat x | $g -i foo"
check allow "git $g -n foo"
check allow "rg -n foo ."
check allow "ast-$g run -p 'foo(\$A)'"
# The words only appear as data: a quoted string or a heredoc body never runs.
check allow "python -c \"print('$g -r is a word')\""
check allow "echo '$g -rn foo .'"
check allow "git commit -m \"guard: refuse $g -r\""
check allow "$(printf 'python - <<%s\npats = {"%s -r": 1}\nEOF\necho done' "'EOF'" "$g")"
check deny  "$(printf 'cat <<EOF\ntext\nEOF\n%s -rn foo .' "$g")"

exit $fail
