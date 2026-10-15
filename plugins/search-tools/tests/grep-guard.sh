#!/usr/bin/env bash
# grep-guard.sh verdicts: a Bash command in; allow, deny, or rewrite (to rg) out. Run:
#   bash plugins/search-tools/tests/grep-guard.sh

set -u
here="$(cd "$(dirname "$0")" && pwd)"
guard="$here/../scripts/grep-guard.sh"
g=grep   # keeps this file's own commands clear of the guard

fail=0
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/src/sub" && touch "$tmp/src/a.py" "$tmp/src/b.py"
# check <deny|allow> <command>   |   check rewrite <command> <expected rg command>
# The hook runs with cwd $tmp (holds src/a.py, src/b.py, src/sub/).
check() {
  local out got
  out="$(jq -n --arg c "$2" --arg d "${cwd:-$tmp}" '{cwd: $d, tool_input: {command: $c, description: "d"}}' | bash "$guard")"
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
check rewrite "$g -rn foo . > out.txt"                "rg -n foo . > out.txt"
check rewrite "$g -rn foo src 2>/dev/null"            "rg -n foo src 2>/dev/null"
# grep's basic regex becomes rg's: \| \( \) are operators, bare | ( ) + ? { } literals.
check rewrite "$g -rn 'a\\|b' src"                      "rg -n 'a|b' src"
check rewrite "$g -rn \"Up\\\\|Down\" ."                "rg -n 'Up|Down' ."
check rewrite "$g -rn 'f(x)+' ."                       "rg -n 'f\\(x\\)\\+' ."
check rewrite "$g -rn '\\<word\\>' ."                  "rg -n '\\bword\\b' ."
check rewrite "$g -rnE 'a|b' ."                        "rg -n 'a|b' ."
check rewrite "$g -rn '[[:digit:]]x' ."                "rg -n '[[:digit:]]x' ."
check rewrite "$g -rnF 'a\\|b' ."                      "rg -n -F 'a\\|b' ."
# In a compound command only the recursive grep segments change.
check rewrite "cd src && $g -R foo"                   "cd src && rg foo"
check rewrite "cat f; $g -n x f | head; $g -rn \"export.*foo\" src" \
                                                     "cat f; $g -n x f | head; rg -n \"export.*foo\" src"
check rewrite "gofmt -l . && go vet ./... && go test ./...; $g -rn TODO --include=*.go ." \
                                                     "gofmt -l . && go vet ./... && go test ./...; rg -n -g '*.go' TODO ."
check rewrite "$g -rn foo src | $g -v test | head -5" "rg -n foo src | $g -v test | head -5"
check rewrite "git diff && $g -rln foo . 2>&1 | wc -l" "git diff && rg -l -n foo . 2>&1 | wc -l"
# grep -r on files only is plain grep: left alone.
check allow "$g -rn pat src/a.py"
check allow "$g -rn pat src/a.py src/b.py | head"
check allow "ls; $g -rn pat src/a.py"
check rewrite "$g -rn pat src/a.py src/sub"           "rg -n pat src/a.py src/sub"
# A cwd with backslashes (C:\Users\...) is read as written, not as escapes (\t, \U).
cwd="$tmp/w\\tx"; mkdir -p "$cwd/src" && touch "$cwd/src/a.py"
check allow "$g -rn pat src/a.py"
command -v cygpath >/dev/null && cwd="$(cygpath -w "$tmp")" && check allow "$g -rn pat src/a.py"
unset cwd
check rewrite "$g -rn pat src/missing.py"             "rg -n pat src/missing.py"
# Anything the rewrite cannot map with confidence is refused as before.
check deny  "$g -rn \$PAT src"
check rewrite "$g -rn foo src/*.py"                   "rg -n foo src/*.py"
check rewrite "$g -rn foo \"\$DIR\""                   "rg -n foo \"\$DIR\""
check deny  "cat x | $g -r foo"
check rewrite "make || $g -r foo"                     "make || rg foo"
check deny  "$g -rn foo . | xargs $g bar"
check rewrite "$g foo -r ."                           "rg foo ."
check deny  "$g -r -- -foo ."
check deny  "$g -rn '[\\]x' ."
check deny  "x=\$($g -rn foo .)"
check deny  "$g -r -e foo ."
check deny  "$g -rq foo ."
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
