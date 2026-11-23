#!/usr/bin/env bash
# bash-guard.sh verdicts: a Bash command in; allow or deny out. Run:
#   bash plugins/guards/tests/bash-guard.sh

set -u
here="$(cd "$(dirname "$0")" && pwd)"
guard="$here/../scripts/bash-guard.sh"

fail=0
# check <deny|allow> <command>
check() {
  local out got
  out="$(jq -n --arg c "$2" '{tool_input: {command: $c}}' | bash "$guard")"
  case "$out" in
    *'"deny"'*) got=deny
                printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecisionReason | length > 20' >/dev/null || got="deny (no reason)" ;;
    *'"updatedInput"'*) got=rewrite ;;
    '')         got=allow ;;
    *)          got="unexpected: $out" ;;
  esac
  if [ "$got" = "$1" ]; then echo "ok   $1 <- $2"
  else echo "FAIL want [$1], got [$got]: $2"; fail=1; fi
}

# rewrites <command> <stdout>: on Windows the command goes to a file byte for byte, the other
# tool_input fields are kept, and running the new command in a shell prints <stdout> and leaves
# the shell where the command's own cd put it.
export TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT
rewrites() {
  local out new file got want
  out="$(jq -n --arg c "$1" '{tool_input: {command: $c, description: "d", timeout: 5}}' \
    | GUARDS_PLATFORM=MINGW64_NT-10.0 bash "$guard")"
  new="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedInput.command // empty' | tr -d '\r')"
  file="${new#source \'}"; file="${file%\'}"
  if [ "$new" = "$file" ] || [ ! -f "$file" ]; then echo "FAIL no rewrite to a file: $1 -> $out"; fail=1; return; fi
  if ! cmp -s "$file" <(printf '%s\n' "$1"); then echo "FAIL file differs from the command: $1"; fail=1; return; fi
  if ! printf '%s' "$out" | jq -e '.hookSpecificOutput.updatedInput | .description == "d" and .timeout == 5' >/dev/null; then
    echo "FAIL other tool_input fields lost: $out"; fail=1; return
  fi
  if printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision' >/dev/null; then
    echo "FAIL the rewrite decides the permission: $out"; fail=1; return
  fi
  got="$(cd "$TMPDIR" && bash -c "$new"$'\n''printf "\n@%s" "${PWD##*/}"')"
  local where="${got##*@}"; got="${got%@*}"
  while [ "${got%$'\n'}" != "$got" ]; do got="${got%$'\n'}"; done
  got="$got@$where"; want="$2@${3:-${TMPDIR##*/}}"
  if [ "$got" = "$want" ]; then echo "ok   rewrite <- $1"
  else echo "FAIL rewrite of [$1]: want [$want], got [$got]"; fail=1; fi
}

# git add: whole-tree staging is denied, named paths pass
check deny  "git add -A"
check deny  "git add --all"
check deny  "git add ."
check deny  "git add -- ."
check deny  "git add :/"
check deny  "git add -vA"
check deny  "git -C some/dir add -A"
check deny  "git -c core.autocrlf=false add ."
check deny  "cd repo && git add -A && git commit -m wip"
check deny  "make test; git add . || true"
check deny  "(cd sub && git add --all)"
check deny  "FOO=1 git add -A"
check allow "git add src/a.ts README.md"
check allow "git add -p src/a.ts"
check allow "git add ./src/a.ts"
check allow "git add \"file with spaces.txt\""
check allow "git status && git diff ."
# git commit: -a in any form is denied
check deny  "git commit -a -m msg"
check deny  "git commit -am \"msg\""
check deny  "git commit --all -m msg"
check deny  "git commit -qam msg"
check deny  "git add x && git commit -am 'fix: y'"
check allow "git commit -m \"add -A support\""
check allow "git commit -m 'git add -A'"
check allow "git commit -ma"
check allow "git commit -m a"
check allow "git commit -uall -m msg"
check allow "git commit --amend --no-edit"
check allow "git commit -F msg.txt -- a.txt"
check allow "echo 'git add -A' > notes.txt"
check allow "$(printf 'cat > f.sh <<EOF\ngit add -A\nEOF\nbash -n f.sh')"
# chezmoi apply --force: denied without a target
check deny  "chezmoi apply --force"
check deny  "chezmoi --force apply"
check deny  "chezmoi apply -v --force"
check deny  "chezmoi -S ~/src apply --force"
check deny  "chezmoi diff ~/.zshrc && chezmoi apply --force"
check allow "chezmoi apply --force ~/.zshrc"
check allow "chezmoi apply --force \"\$HOME/.config/a b\""
check allow "chezmoi apply"
check allow "chezmoi apply ~/.zshrc"
check allow "chezmoi apply --force --dry-run"
check allow "chezmoi apply -nv --force"
check allow "chezmoi diff"
check allow "chezmoi status --force"
# kill by name: denied, by PID passes
check deny  "taskkill /IM node.exe /F"
check deny  "taskkill //IM node.exe //F"
check deny  "taskkill /f /im node.exe"
check deny  "taskkill.exe -IM node.exe"
check deny  "TASKKILL /T /IM dotnet.exe"
check deny  "pkill -f vite"
check deny  "killall node"
check deny  "sudo pkill -9 python"
check deny  "make; pkill node || true"
check deny  "make; /usr/bin/pkill node"   # not leading: MSYS would rewrite a leading /usr/bin into C:/... for jq.exe
check allow "taskkill /PID 1234 /F"
check allow "taskkill //PID 1234 //T //F"
check allow "kill 1234"
check allow "kill -9 \$(cat server.pid)"
check allow "pgrep -af node"
check allow "echo 'pkill node'"
check allow "git commit -m \"stop using pkill\""
check allow "skill-check --all"
# \\ on Windows: the Bash tool would halve it, so there the command runs from a file, nowhere else
GUARDS_PLATFORM=MINGW64_NT-10.0 check rewrite 'printf "%s" '\''a\\b'\'''
GUARDS_PLATFORM=MSYS_NT-10.0    check rewrite $'python - <<\'EOF\'\nprint("a\\\\b")\nEOF'
GUARDS_PLATFORM=CYGWIN_NT-10.0  check rewrite 'echo "a\\b"'
GUARDS_PLATFORM=MINGW64_NT-10.0 check allow 'echo '\''a\b'\'' [\s\S]'
# a deny rule wins over the rewrite
GUARDS_PLATFORM=MINGW64_NT-10.0 check deny 'printf "%s" '\''a\\b'\'' && git add -A'
GUARDS_PLATFORM=MINGW64_NT-10.0 check deny 'taskkill //IM node.exe; echo '\''a\\b'\'''
rewrites 'printf '\''%s'\'' '\''a\\b'\''' 'a\\b'
rewrites "printf '%s' 'it'\\''s a\\\\b'" "it's a\\\\b"
rewrites $'cat <<\'EOF\'\nC:\\\\dir\\\\file\nEOF' 'C:\\dir\\file'
rewrites $'cat <<EOF\nC:\\\\dir\nEOF' 'C:\dir'
rewrites 'printf '\''%s'\'' '\''C:\x/y\\z'\'' | sed -E '\''s#[\\/]+#|#g'\''' 'C:|x|y|z'
rewrites 'mkdir -p sub && cd sub && printf '\''%s'\'' '\''a\\b'\''' 'a\\b' sub
GUARDS_PLATFORM=Linux           check allow 'printf "%s" '\''a\\b'\'''
GUARDS_PLATFORM=MINGW64_NT-10.0 GUARDS_HOST=codex check allow 'printf "%s" '\''a\\b'\'''

exit $fail
