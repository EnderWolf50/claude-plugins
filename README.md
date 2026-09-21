# claude-plugins

EnderWolf50's [Claude Code](https://code.claude.com) plugins, published as the marketplace `enderwolf50`. One repo: the catalog plus every plugin under `plugins/`.

```
claude plugin marketplace add EnderWolf50/claude-plugins
```

| Plugin | Install | What |
|---|---|---|
| [win-toast](plugins/win-toast/) | `claude plugin install win-toast@enderwolf50` | Windows toast notifications with click-to-focus for Windows Terminal |
| [search-tools](plugins/search-tools/) | `claude plugin install search-tools@enderwolf50` | keeps a `tgrep serve` alive only while a session uses a large repo; refuses `grep -r` in favour of `rg`; reference skill for tgrep / ast-grep / semble / ripgrep |

Both are Windows-only. Each plugin's README covers its own hooks, skills and knobs.

## Layout

```
.claude-plugin/marketplace.json   catalog — every plugin is "./plugins/<name>"
plugins/<name>/                   a plugin: .claude-plugin/plugin.json, hooks/, scripts/, skills/, README, CHANGELOG
```

## Releasing

1. Change the plugin, bump `plugins/<name>/.claude-plugin/plugin.json` `version`, add a CHANGELOG entry.
2. Mirror the version in `.claude-plugin/marketplace.json`.
3. Commit and push. Users pick it up with `claude plugin marketplace update enderwolf50` then `claude plugin update <name>@enderwolf50`.

Local development: `claude --plugin-dir D:\claude-plugins\plugins\<name>`.

## History

`win-toast` and `search-tools` were imported with `git subtree` from their former standalone repos (now archived), so their full history is in this repo.
