# claude-plugins

Marketplace `enderwolf50` for [Claude Code](https://code.claude.com). Each plugin lives in its own repo; this repo only holds the catalog.

```
claude plugin marketplace add EnderWolf50/claude-plugins
```

| Plugin | Install | Repo |
|---|---|---|
| **win-toast** — Windows toast notifications with click-to-focus for Windows Terminal | `claude plugin install win-toast@enderwolf50` | [claude-win-toast](https://github.com/EnderWolf50/claude-win-toast) |
| **search-tools** — keeps a `tgrep serve` alive only while a session uses a large repo; reference skill for tgrep / ast-grep / semble / ripgrep | `claude plugin install search-tools@enderwolf50` | [claude-search-tools](https://github.com/EnderWolf50/claude-search-tools) |

Both are Windows-only.

## Adding a plugin

Append an entry to `.claude-plugin/marketplace.json` with a `github` source and bump `metadata.version`; users pick it up with `claude plugin marketplace update enderwolf50`.
