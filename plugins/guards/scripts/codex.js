// Codex uses Bash as a hook alias even when unified exec runs PowerShell on Windows.
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const input = fs.readFileSync(0, 'utf8');
const event = JSON.parse(input);
const shell = event.tool_input?.shell || '';
// merge-guard.js makes the same call for `node merge-guard.js codex`; change both together.
const powershell = process.platform === 'win32' && !/bash|zsh|\/sh$/.test(shell);
const env = { ...process.env, GUARDS_HOST: 'codex' };   // codex-guard.ps1 hands some commands to bash-guard.sh
const result = powershell
  ? spawnSync('pwsh', ['-NoProfile', '-NonInteractive', '-File', path.join(__dirname, 'codex-guard.ps1')], { input, encoding: 'utf8', env })
  : spawnSync('bash', [path.join(__dirname, 'bash-guard.sh')], { input, encoding: 'utf8', env });
if (result.stdout) process.stdout.write(result.stdout);
if (result.stderr) process.stderr.write(result.stderr);
if (result.error) process.stderr.write(`guards: ${result.error.message}\n`);
process.exit(result.error ? 2 : result.status ?? 2);
