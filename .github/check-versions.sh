#!/usr/bin/env bash
# Every plugin's version agrees in three places: its marketplace.json entry, its
# .claude-plugin/plugin.json, and the newest version heading of its CHANGELOG.md. Run from the repo root.
set -u
fail=0
while IFS=$'\t' read -r name version source; do
  dir="${source#./}"
  manifest="$(jq -r '.version // ""' "$dir/.claude-plugin/plugin.json" 2>/dev/null | tr -d '\r')"
  # the newest released heading: an `## Unreleased` section above it is fine
  changelog="$(sed -n 's/^## \([^ ]*\).*/\1/p' "$dir/CHANGELOG.md" 2>/dev/null | tr -d '\r' | grep -v -x -i 'unreleased' | head -1)"
  if [ "$manifest" = "$version" ] && [ "$changelog" = "$version" ]; then
    echo "ok   $name $version"
  else
    echo "FAIL $name: marketplace.json $version, plugin.json ${manifest:-missing}, CHANGELOG.md ${changelog:-missing}"
    fail=1
  fi
done < <(jq -r '.plugins[] | [.name, .version, .source] | @tsv' .claude-plugin/marketplace.json | tr -d '\r')
exit $fail
