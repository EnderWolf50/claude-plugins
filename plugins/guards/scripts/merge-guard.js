// PreToolUse (Bash): a merge waits for a code review of the exact head it merges.
//
// Checked: `gh pr merge` (with --auto too), `gh api …/pulls/<n>/merge`, `glab mr merge`,
// `glab api …/merge_requests/<n>/merge`. Each one's current head SHA is looked up with gh/glab, and the merge
// passes when that SHA is recorded in `<git common dir>/reviewed-heads` (the code-review skill's patch appends
// it once a review leaves nothing to fix), or when the command itself attests it: `SHIP_REVIEWED=<sha> gh …`,
// or `$env:SHIP_REVIEWED='<sha>'; gh …` in PowerShell, for a review done another way that the user confirmed.
// Anything else is denied with the head SHA and both ways forward. The user's own merges (web UI, their
// terminal, `!` commands) never reach this hook.
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const RECORD = 'reviewed-heads';
// flags of `gh pr merge` / `glab mr merge` that take a value, so the value is not read as the PR selector
const VALUE_FLAGS = new Set(['-R', '--repo', '-b', '--body', '-F', '--body-file', '-t', '--subject',
  '--match-head-commit', '-A', '--author-email', '-m', '--message', '--sha', '--squash-message']);

/** Split a command into segments (; && || | newline) of shell words, quotes removed. Good enough for argv. */
function segments(cmd) {
  const out = [];
  let words = [], word = '', quote = '', i = 0, has = false;
  const push = () => { if (has) words.push(word); word = ''; has = false; };
  const end = () => { push(); if (words.length) out.push(words); words = []; };
  while (i < cmd.length) {
    const c = cmd[i];
    if (quote) {
      if (c === quote) quote = '';
      else if (c === '\\' && quote === '"' && i + 1 < cmd.length) { word += cmd[++i]; }
      else word += c;
      has = true;
    } else if (c === '"' || c === "'") { quote = c; has = true; }
    else if (c === '\\' && i + 1 < cmd.length) { if (cmd[i + 1] !== '\n') { word += cmd[i + 1]; has = true; } i++; }
    else if (/\s/.test(c) && c !== '\n') push();
    else if (c === '\n' || c === ';') end();
    else if ((c === '&' || c === '|') && cmd[i + 1] === c) { end(); i++; }
    else if (c === '|' || c === '&') end();
    else { word += c; has = true; }
    i++;
  }
  end();
  return out;
}

/** Strip leading `VAR=value` / `env VAR=value` / `$env:VAR = value` words; return [assignments, rest]. */
function leadingAssignments(words) {
  const vars = {};
  let i = 0;
  if (words[i] === 'env') i++;
  for (; i < words.length; i++) {
    const m = /^\$?(?:env:)?([A-Za-z_]\w*)=(.*)$/.exec(words[i]);
    if (m) { vars[m[1]] = m[2]; continue; }
    if (/^\$env:[A-Za-z_]\w*$/.test(words[i]) && words[i + 1] === '=' && i + 2 < words.length) {
      vars[words[i].slice(5)] = words[i + 2]; i += 2; continue;
    }
    break;
  }
  return [vars, words.slice(i)];
}

function flagValue(args, names) {
  for (let i = 0; i < args.length; i++) {
    for (const n of names) {
      if (args[i] === n && i + 1 < args.length) return args[i + 1];
      if (args[i].startsWith(n + '=')) return args[i].slice(n.length + 1);
    }
  }
  return null;
}

function selector(args) {
  for (let i = 0; i < args.length; i++) {
    if (VALUE_FLAGS.has(args[i])) { i++; continue; }
    if (!args[i].startsWith('-')) return args[i];
  }
  return null;
}

/** Every merge call in the command: {tool, kind, selector?, repo?, endpoint?, attested?}. */
function merges(cmd) {
  const found = [];
  const attestedAll = {};
  for (const seg of segments(cmd)) {
    const [vars, words] = leadingAssignments(seg);
    Object.assign(attestedAll, vars);  // `$env:X='…'; gh …` sets it for the rest of the line
    const exe = (words[0] || '').replace(/\.exe$/i, '').split(/[\\/]/).pop();
    const attested = vars.SHIP_REVIEWED || attestedAll.SHIP_REVIEWED || null;
    if ((exe === 'gh' && words[1] === 'pr' || exe === 'glab' && words[1] === 'mr') && words[2] === 'merge') {
      const args = words.slice(3);
      found.push({ tool: exe, kind: 'cli', selector: selector(args), repo: flagValue(args, ['-R', '--repo']), attested });
    } else if ((exe === 'gh' || exe === 'glab') && words[1] === 'api') {
      const endpoint = words.slice(2).find(w => /(?:pulls|merge_requests)\/\d+\/merge\/?$/.test(w));
      if (endpoint) found.push({ tool: exe, kind: 'api', endpoint: endpoint.replace(/^\//, ''), attested });
    }
  }
  return found;
}

function run(exe, args, cwd) {
  const r = spawnSync(exe, args, { cwd, encoding: 'utf8', shell: false, timeout: 15000, windowsHide: true });
  if (r.error || r.status !== 0) throw new Error((r.stderr || r.error?.message || `${exe} failed`).trim().split('\n')[0]);
  return r.stdout.trim();
}

/** The head SHA the merge would land. */
function headOf(m, cwd, exec = run) {
  if (m.tool === 'gh' && m.kind === 'cli') {
    return exec('gh', ['pr', 'view', ...(m.selector ? [m.selector] : []), ...(m.repo ? ['-R', m.repo] : []),
      '--json', 'headRefOid', '-q', '.headRefOid'], cwd);
  }
  if (m.tool === 'gh') return exec('gh', ['api', m.endpoint.replace(/\/merge\/?$/, ''), '--jq', '.head.sha'], cwd);
  if (m.kind === 'cli') {
    return JSON.parse(exec('glab', ['mr', 'view', ...(m.selector ? [m.selector] : []), ...(m.repo ? ['-R', m.repo] : []),
      '-F', 'json'], cwd)).sha;
  }
  return JSON.parse(exec('glab', ['api', m.endpoint.replace(/\/merge\/?$/, '')], cwd)).sha;
}

function recordPath(cwd, exec = run) {
  return path.join(exec('git', ['rev-parse', '--path-format=absolute', '--git-common-dir'], cwd), RECORD);
}

function recorded(file, sha) {
  try {
    return fs.readFileSync(file, 'utf8').split(/\r?\n/).some(l => l.split(/\s+/)[0] === sha);
  } catch { return false; }
}

const same = (a, b) => !!a && !!b && a.length >= 7 && b.toLowerCase().startsWith(a.toLowerCase());

/** The reason to deny, or null. `exec` is injectable for tests. */
function check(cmd, cwd, exec = run) {
  for (const m of merges(cmd)) {
    let sha;
    try { sha = headOf(m, cwd, exec); } catch (e) {
      return `Could not read the head of this merge (${e.message}). Check the PR exists and gh/glab is logged in, then retry.`;
    }
    if (m.attested !== null && m.attested !== undefined) {
      if (same(m.attested, sha)) continue;
      return `SHIP_REVIEWED=${m.attested} does not match the head ${sha.slice(0, 12)} of this merge: commits landed after `
        + 'that review. Review the new head, or attest it only after the user confirms it was reviewed.';
    }
    let file = null;
    try { file = recordPath(cwd, exec); } catch { /* not in a repo: no record */ }
    if (file && recorded(file, sha)) continue;
    return `This merge waits for a code review of its head ${sha.slice(0, 12)}. Run the code-review skill against it `
      + '(fixed point origin/<target>); when the review leaves nothing to fix, its patch records the head and this '
      + `merge goes through. If this exact head was already reviewed another way and the user confirmed it, prefix `
      + `SHIP_REVIEWED=${sha} to the command (PowerShell: $env:SHIP_REVIEWED='${sha}'; before it).`;
  }
  return null;
}

if (require.main === module) {
  const event = JSON.parse(fs.readFileSync(0, 'utf8'));
  const reason = check(event.tool_input?.command || '', event.cwd || process.cwd());
  if (reason) {
    process.stdout.write(JSON.stringify({ hookSpecificOutput: {
      hookEventName: 'PreToolUse', permissionDecision: 'deny', permissionDecisionReason: reason } }));
  }
}

module.exports = { segments, merges, headOf, check, recorded, RECORD };
