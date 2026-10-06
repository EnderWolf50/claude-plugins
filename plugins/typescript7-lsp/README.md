# typescript7-lsp

Code intelligence for projects on TypeScript 7 (the Go port, `typescript-go`). It runs the project's own TypeScript as the language server: `bun run tsc --lsp --stdio`.

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

`bun run` only runs the project's `node_modules/.bin/tsc`: run `pnpm install` (or the project's package manager) first. A project without a local TypeScript gets no server, and nothing is installed or downloaded. Needs [Bun](https://bun.sh) on `PATH`.

Why `bun run`: it starts in about 200 ms, against about 750 ms for `npx --no-install`. `pnpm exec` was also tried and dropped: in a project installed by npm, it reinstalls `node_modules` the pnpm way before running.

## Tested

TypeScript 7.0.2 on Windows, in a pnpm project and an npm project: `initialize` reports `typescript-go`; hover returns the type; a type error comes back through pull diagnostics (`textDocument/diagnostic`). The npm project's `node_modules` is left as it was.
