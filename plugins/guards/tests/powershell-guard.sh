#!/usr/bin/env bash
# powershell-guard.sh verdicts: a PowerShell command in; allow or deny out. Run:
#   bash plugins/guards/tests/powershell-guard.sh

set -u
here="$(cd "$(dirname "$0")" && pwd)"
guard="$here/../scripts/powershell-guard.sh"

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

nl=$'\n'
check deny  "git commit -F - <<'EOF'${nl}msg${nl}EOF"
check deny  "git commit -F - <<EOF${nl}msg${nl}EOF"
check deny  "cat <<-EOF${nl}x${nl}EOF"
check deny  "cat << 'EOF'${nl}x${nl}EOF"
check deny  "cat <<\"EOF\"${nl}x${nl}EOF"
check deny  "Get-Date; cat <<EOT${nl}x${nl}EOT"
check allow "Get-Date"
check allow "\$s = @'${nl}line${nl}'@${nl}git commit -m \$s"
check allow "\$s = @'${nl}cat <<'EOF'${nl}x${nl}EOF${nl}'@${nl}\$s"
check allow "\$s = @\"${nl}cat <<EOF${nl}\"@${nl}\$s"
check allow "Write-Output 'a <<EOF b'"
check allow "Write-Output \"a <<EOF b\""
check allow "1 -shl 2"
check allow "[int]2 -bor 1"

exit $fail
