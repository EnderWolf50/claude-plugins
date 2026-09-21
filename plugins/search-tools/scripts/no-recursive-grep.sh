#!/usr/bin/env bash
# PreToolUse (Bash) hook: refuse a recursive `grep` over a tree and point at rg.
#
# Only tree searches are refused (`grep -r`, `-R`, `--recursive`,
# `--dereference-recursive`); `cmd | grep x` on a stream is left alone.
# `rg`, `tgrep`, `ast-grep` and `git grep` are not matched.
# Set SEARCH_TOOLS_ALLOW_GREP=1 to disable.

set -u
[ "${SEARCH_TOOLS_ALLOW_GREP:-}" = "1" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

cmd="$(jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -n "$cmd" ] || exit 0

# A grep word (not the tail of tgrep / ast-grep, not after `git `), then a
# recursive flag before the next pipe/; /&&.
if printf '%s' "$cmd" | grep -Eq '(^|[^A-Za-z0-9_./-])[ef]?grep([[:space:]]+(-[A-Za-z]*[rR][A-Za-z]*|--(dereference-)?recursive)([[:space:]]|$)|[[:space:]]+[^|;&]*[[:space:]](-[A-Za-z]*[rR][A-Za-z]*|--(dereference-)?recursive)([[:space:]]|$))' \
   && ! printf '%s' "$cmd" | grep -Eq '(^|[^A-Za-z0-9_])git[[:space:]]+grep'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "Tree search: use rg — `rg -n <pattern> [path]` (same flags as grep, respects .gitignore, faster). On a large repo with a tgrep server, run `tgrep` from the repo root instead. Stream filters (`cmd | grep x`) are fine."
    }
  }'
fi
exit 0
