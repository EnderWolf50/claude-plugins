#!/usr/bin/env bash
# Check that every tool this plugin drives or routes to is installed.
#
#   healthcheck.sh      (/search-tools:healthcheck)
#
# required  what the hooks shell out to; a gap breaks them (a missing tgrep
#           makes tgrep-serve.sh exit silently, so nothing ever gets served)
# routed    the tools the reference skill and your CLAUDE.md routing point at
#
# Exit 1 when a required tool is missing, else 0. Versions that differ from the
# ones skills/reference/SKILL.md was verified against are flagged, not failed.

set -u

fail=0

# check <name> <required|routed> <verified-version|-> <install hint> [version cmd...]
check() {
  local name="$1" kind="$2" verified="$3" hint="$4"; shift 4
  local path ver note=""
  path="$(command -v "$name" 2>/dev/null)"
  if [ -z "$path" ]; then
    printf '  %-15s MISSING   %s\n' "$name" "install: $hint"
    [ "$kind" = required ] && fail=1
    return
  fi
  if [ $# -gt 0 ]; then
    ver="$("$@" 2>/dev/null | head -1 | grep -oE '[0-9]+(\.[0-9]+)+' | head -1)"
    [ "$verified" != - ] && [ -n "$ver" ] && [ "$ver" != "$verified" ] && note="  (reference verified $verified)"
  fi
  printf '  %-15s ok %-8s %s%s\n' "$name" "${ver:-}" "$path" "$note"
}

echo "required (hooks):"
check tgrep          required 1.0.9  'https://github.com/microsoft/tgrep (Windows: scoop install tgrep)'   tgrep --version
check jq             required -      'scoop install jq / apt install jq / brew install jq'      jq --version
case "$OSTYPE" in
msys* | cygwin*)
  check cygpath        required - 'ships with Git for Windows (Git Bash)'
  check powershell.exe required - 'ships with Windows'
  check taskkill       required - 'ships with Windows'
  ;;
*)
  check ps             required - 'procps (Linux); ships with macOS'
  check kill           required - 'shell builtin'
  check realpath       required - 'coreutils (Linux); ships with macOS 13+'
  command -v setsid >/dev/null 2>&1 || printf '  %-15s absent    (optional: servers then share the hook process group)
' setsid
  ;;
esac

echo
echo "routed (search tools):"
check rg             routed   15.2.0 'scoop install ripgrep / apt install ripgrep / brew install ripgrep'  rg --version
check ast-grep       routed   0.45.1 'scoop install ast-grep / brew install ast-grep / cargo install ast-grep' ast-grep --version
check semble         routed   0.6.0  'uv tool install semble' semble --version

# semble is routed to over MCP first; the CLI alone is not enough for mcp__semble__*.
echo
if [ -f "$HOME/.claude.json" ] && command -v jq >/dev/null 2>&1 &&
   jq -e '[.. | objects | .mcpServers? // empty | keys[]] | index("semble")' "$HOME/.claude.json" >/dev/null 2>&1; then
  echo "semble MCP: registered in ~/.claude.json"
else
  echo "semble MCP: not found in ~/.claude.json (fine if a plugin provides it; else \`semble install --agent claude --type mcp\`)"
fi

echo
if [ "$fail" = 0 ]; then echo "result: OK"; else echo "result: FAIL — a required tool is missing, the hooks cannot run"; fi
exit "$fail"
