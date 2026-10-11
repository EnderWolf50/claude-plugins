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
    '')         got=allow ;;
    *)          got="unexpected: $out" ;;
  esac
  if [ "$got" = "$1" ]; then echo "ok   $1 <- $2"
  else echo "FAIL want [$1], got [$got]: $2"; fail=1; fi
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

exit $fail
