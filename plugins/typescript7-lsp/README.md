# typescript7-lsp

Code intelligence for projects on TypeScript 7 (the Go port, `typescript-go`). It runs the project's own TypeScript as the language server: `npx --no-install tsc --lsp --stdio`.

The official `typescript-lsp` plugin runs typescript-language-server, which drives the `tsserver` that TypeScript 6.x and older ship. TypeScript 7 has no tsserver, so in a TypeScript 7 project that plugin fails with `Could not find a valid TypeScript installation`.

## Use it per project

Turn it on only in projects whose `typescript` dependency is 7.x, and turn `typescript-lsp` off there. In TypeScript 6 or older, `tsc` has no `--lsp` and this server exits. In the project's `.claude/settings.json`:

```json
{
  "enabledPlugins": {
    "typescript7-lsp@enderwolf50": true,
    "typescript-lsp@claude-plugins-official": false
  }
}
```

`--no-install` keeps npx to the project's `node_modules/.bin/tsc`: run `pnpm install` (or the project's package manager) first. A project without a local TypeScript gets no server instead of whatever TypeScript npx would download.

## Tested

TypeScript 7.0.2 on Windows: `initialize` reports `typescript-go`; hover returns the type; a type error comes back through pull diagnostics (`textDocument/diagnostic`).
