// Sidecars use the same live-process records as CC, so either host's reaper
// preserves servers still used by the other. Never use the short-lived hook PID.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const { spawn, spawnSync } = require('node:child_process');
const event = JSON.parse(fs.readFileSync(0, 'utf8'));
const home = process.env.SEARCH_TOOLS_HOME || os.homedir();
const directory = path.join(home, '.claude', 'sessions');
const id = 'codex-' + crypto.createHash('sha256').update(event.session_id || '').digest('hex');
const record = path.join(directory, id + '.json');
function gitBash() {
  if (process.platform !== 'win32') return 'bash';
  const git = spawnSync('where.exe', ['git.exe'], {encoding:'utf8'}).stdout?.trim().split(/\r?\n/)[0];
  const candidates = [process.env.CLAUDE_CODE_GIT_BASH_PATH,
    git && path.resolve(path.dirname(git), '../bin/bash.exe'),
    path.join(process.env.LOCALAPPDATA || '', 'Programs/Git/bin/bash.exe'),
    path.join(process.env.ProgramFiles || '', 'Git/bin/bash.exe')];
  const found = candidates.find(p => p && fs.existsSync(p));
  if (!found) throw new Error('search-tools requires Git Bash on Windows; WSL bash is not a compatible substitute.');
  return found;
}
const bash = gitBash();
const env = {...process.env, HOME: home, CLAUDE_PROJECT_DIR: event.cwd || process.cwd(),
  SEARCH_TOOLS_BASH: bash, CLAUDE_PLUGIN_DATA: path.join(home, '.claude', 'search-tools')};
const lifecycle = path.join(__dirname, 'tgrep-serve.sh').replaceAll('\\', '/');

function ownerPid() {
  // app-server serves multiple threads: SessionEnd removes this thread's lease;
  // after a crash, the existing CC reaper sees that the owning process is dead.
  if (process.platform === 'win32') {
    const script = `$p=${process.pid}; for($i=0;$i -lt 12;$i++){ $r=Get-CimInstance Win32_Process -Filter "ProcessId=$p"; if(!$r){break}; if($r.Name -match '^codex(\\.exe)?$'){Write-Output $r.ProcessId; break}; $p=$r.ParentProcessId }`;
    const result = spawnSync('pwsh', ['-NoProfile', '-NonInteractive', '-Command', script], {encoding:'utf8', timeout:10000});
    return Number(result.stdout?.trim()) || null;
  }
  let pid = process.ppid;
  for (let i = 0; pid > 1 && i < 12; i++) {
    const result = spawnSync('ps', ['-p', String(pid), '-o', 'ppid=', '-o', 'comm='], {encoding:'utf8', timeout:2000});
    const match = result.stdout?.trim().match(/^(\d+)\s+(.+)$/);
    if (!match) break;
    if (/^codex(?:[.-].*)?$/.test(path.basename(match[2]))) return pid;
    pid = Number(match[1]);
  }
  return null;
}

if (event.hook_event_name === 'SessionStart') {
  if (!event.session_id) process.exit(0);
  const pid = ownerPid();
  // Unknown owner: don't start a server whose lifetime we cannot track.
  if (!pid) process.exit(0);
  fs.mkdirSync(directory, {recursive:true});
  const temporary = record + '.' + process.pid;
  fs.writeFileSync(temporary, JSON.stringify({pid, sessionId:id, cwd:env.CLAUDE_PROJECT_DIR}));
  fs.renameSync(temporary, record);
  const result = spawnSync(bash, [lifecycle, 'start'], {env, encoding:'utf8', timeout:25000});
  if (result.stdout?.trim()) console.log(JSON.stringify({hookSpecificOutput:{hookEventName:'SessionStart', additionalContext:result.stdout.trim()}}));
} else if (event.hook_event_name === 'SessionEnd') {
  if (!event.session_id) process.exit(0);
  if (!fs.existsSync(record)) process.exit(0);
  const token = crypto.randomUUID();
  const lease = JSON.parse(fs.readFileSync(record, 'utf8'));
  fs.writeFileSync(record, JSON.stringify({...lease, ending:token}));
  // Keep the last record until reaping: the shared reaper intentionally refuses
  // to kill anything when there are no reliable session files at all.
  const child = spawn(process.execPath, [path.join(__dirname, 'codex-reap.js'), record, id, token],
    {env, detached:true, stdio:'ignore', windowsHide:true});
  child.on('error', () => {});
  child.unref();
} else if (event.hook_event_name === 'PreToolUse') {
  const powershell = process.platform === 'win32' && !/bash|zsh|\/sh$/.test(event.tool_input?.shell || '');
  const result = powershell
    ? spawnSync('pwsh', ['-NoProfile', '-NonInteractive', '-File', path.join(__dirname, 'codex-grep.ps1')], {input:JSON.stringify(event), encoding:'utf8', env})
    : spawnSync(bash, [path.join(__dirname, 'grep-guard.sh').replaceAll('\\', '/')], {input:JSON.stringify(event), encoding:'utf8', env});
  if (result.error || result.status !== 0) { console.error(result.error?.message || result.stderr); process.exit(2); }
  if (result.stdout?.trim()) {
    const output = JSON.parse(result.stdout);
    if (output.hookSpecificOutput?.updatedInput) output.hookSpecificOutput.permissionDecision = 'allow';
    console.log(JSON.stringify(output));
  }
}
