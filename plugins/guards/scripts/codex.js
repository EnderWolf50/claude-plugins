// Codex uses Bash as a hook alias even when unified exec runs PowerShell on Windows.
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const input = fs.readFileSync(0, 'utf8');
const event = JSON.parse(input);
if (event.hook_event_name === 'SessionStart' || event.hook_event_name === 'SubagentStart') {
  // The rules up front, from the same text as the denials. Codex has no doubled-backslash
  // rewrite or PowerShell heredoc check, so only context.all.
  const rules = JSON.parse(fs.readFileSync(path.join(__dirname, 'rules.json'), 'utf8'));
  const additionalContext = [rules.context.intro, ...rules.context.all.map(key => `- ${rules[key].do}`)].join('\n');
  process.stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: event.hook_event_name, additionalContext } }));
  process.exit(0);
}
const shell = event.tool_input?.shell || '';
const powershell = process.platform === 'win32' && !/bash|zsh|\/sh$/.test(shell);
const env = { ...process.env, GUARDS_HOST: 'codex' };   // codex-guard.ps1 hands some commands to bash-guard.sh
const result = powershell
  ? spawnSync('pwsh', ['-NoProfile', '-NonInteractive', '-File', path.join(__dirname, 'codex-guard.ps1')], { input, encoding: 'utf8', env })
  : spawnSync('bash', [path.join(__dirname, 'bash-guard.sh')], { input, encoding: 'utf8', env });
if (result.stdout) process.stdout.write(result.stdout);
if (result.stderr) process.stderr.write(result.stderr);
if (result.error) process.stderr.write(`guards: ${result.error.message}\n`);
process.exit(result.error ? 2 : result.status ?? 2);
