// PreToolUse (Bash, PowerShell): a merge waits for a code review of the exact head it merges.
//
// Checked: `gh pr merge` (with --auto too), `gh api -X PUT …/pulls/<n>/merge`, `glab mr merge` / `accept`,
// `glab api --method PUT …/merge_requests/<n>/merge`, anywhere in a segment (after `command`, `sudo`, `then`, `{`,
// …) and inside `bash -c "…"` / `pwsh -c "…"` / `eval` / `iex`. Each one's current head SHA is looked up with gh/glab,
// and the merge passes when that SHA is recorded in `<git common dir>/reviewed-heads` (the code-review skill's
// patch appends it once a review leaves nothing to fix), or when the command itself attests it:
// `SHIP_REVIEWED=<sha> gh …`, or `$env:SHIP_REVIEWED='<sha>'; gh …` in PowerShell, for a review done another way
// that the user confirmed. A GraphQL merge (in the command or in the query file it reads), `xargs` feeding the selector and a
// `gh alias set` that merges hide the head, so they are denied.
// Anything else is denied with the head SHA and both ways forward. The user's own merges (web UI, their
// terminal, `!` commands) never reach this hook. `node merge-guard.js codex` reads Codex's PowerShell on Windows.
'use strict';
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const RECORD = 'reviewed-heads';
// flags of `gh pr merge` / `glab mr merge` that take a value, so the value is not read as the PR selector
const VALUE_FLAGS = new Set(['-R', '--repo', '-b', '--body', '-F', '--body-file', '-t', '--subject',
  '--match-head-commit', '-A', '--author-email', '-m', '--message', '--sha', '--squash-message']);
const SHELLS = /^(bash|sh|zsh|dash|pwsh|powershell|cmd|wsl)$/i;
const SHELL_SCRIPT_FLAG = /^(-[a-z]*c|-command|\/c)$/i;
const EVALS = /^(eval|iex|invoke-expression)$/i;
const CD = /^(cd|pushd|set-location|sl|chdir)$/i;
const CONTROL = /^(then|do|else|\{)$/;
const GRAPHQL_MERGE = /\b(?:mergePullRequest|enablePullRequestAutoMerge)\s*\(/;
const graphqlMerge = text => GRAPHQL_MERGE.test(text.replace(/"""[\s\S]*?"""|"(?:\\.|[^"\\])*"|#[^\r\n]*/g, ' '));
const MERGE_ENDPOINT = /(?:pulls|merge_requests)\/\d+\/merge\/?(?:\?.*)?$/;
const DEADLINE = Date.now() + 25000;  // every lookup shares it, inside the hosts' 30 s hook timeout

const exeName = w => (w || '').split(/[\\/]/).pop().replace(/\.exe$/i, '').toLowerCase();

/** The text after each heredoc start (`<<EOF`, `<<-'EOF'`) up to its delimiter line: skipped, it is data. */
function heredocEnd(cmd, from, delims) {
  let p = from;
  for (const d of delims) {
    while (p < cmd.length) {
      const nl = cmd.indexOf('\n', p);
      const line = cmd.slice(p, nl < 0 ? cmd.length : nl);
      p = nl < 0 ? cmd.length : nl + 1;
      if (line.trim() === d) break;
    }
  }
  return p;
}

/**
 * Split a command into segments (; && || | & ( ) newline) of shell words, quotes removed. Good enough for argv.
 * `ps`: PowerShell, where the backtick escapes and a backslash is a path character.
 */
function segments(cmd, ps = false) {
  const esc = ps ? '`' : '\\';
  const out = [];
  let words = [], word = '', quote = '', inWord = false, heredocs = [];
  const push = () => { if (inWord) words.push(word); word = ''; inWord = false; };
  const end = () => { push(); if (words.length) out.push(words); words = []; };
  for (let i = 0; i < cmd.length; i++) {
    const c = cmd[i];
    if (quote) {
      if (c === quote) quote = '';
      else if (c === esc && quote === '"' && i + 1 < cmd.length) word += cmd[++i];
      else word += c;
      inWord = true;
    } else if (c === '"' || c === "'") { quote = c; inWord = true; }
    else if (c === esc && i + 1 < cmd.length) { if (cmd[i + 1] !== '\n') { word += cmd[i + 1]; inWord = true; } i++; }
    else if (!ps && cmd.startsWith('<<', i) && cmd[i + 2] !== '<') {
      push();
      let j = i + 2 + (cmd[i + 2] === '-' ? 1 : 0);
      while (cmd[j] === ' ' || cmd[j] === '\t') j++;
      let d = '';
      for (; j < cmd.length && !/[\s;&|<>()]/.test(cmd[j]); j++) if (!`'"\\`.includes(cmd[j])) d += cmd[j];
      if (d) heredocs.push(d);
      i = j - 1;
    } else if (c === '\n') {
      end();
      if (heredocs.length) { i = heredocEnd(cmd, i + 1, heredocs) - 1; heredocs = []; }
    } else if (/\s/.test(c)) push();
    else if (';&|()'.includes(c)) end();
    else { word += c; inWord = true; }
  }
  end();
  return out;
}

/** Strip leading `VAR=value` / `env|export VAR=value` / `$env:VAR = value`; return {vars, rest, lasting}. */
function leadingAssignments(words) {
  const vars = {};
  let i = 0, lasting = false;
  if (words[0] === 'env') i++;
  else if (words[0] === 'export') { i++; lasting = true; }
  for (; i < words.length; i++) {
    const m = /^(\$env:)?([A-Za-z_]\w*)=(.*)$/i.exec(words[i]);
    if (m) { vars[m[2]] = m[3]; lasting ||= !!m[1]; continue; }
    if (/^\$env:[A-Za-z_]\w*$/i.test(words[i]) && words[i + 1] === '=' && i + 2 < words.length) {
      vars[words[i].slice(5)] = words[i + 2]; lasting = true; i += 2; continue;
    }
    break;
  }
  const rest = words.slice(i);
  return { vars, rest, lasting: lasting || rest.length === 0 };  // a bare `X=v` sets it for later commands
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

const viaJson = s => JSON.parse(s).sha;
const viaText = s => s;

/** How to read the head this merge would land: [exe, args, parse], or a reason it cannot be read. */
function lookupOf(tool, sub, before, cwd) {
  let globalRepo = null;  // `gh -R o/r pr merge 5`
  while (sub[0] === '-R' || sub[0] === '--repo' || /^--repo=/.test(sub[0] || '')) {
    globalRepo = sub[0].includes('=') ? sub[0].slice('--repo='.length) : sub[1];
    sub = sub.slice(sub[0].includes('=') ? 1 : 2);
  }
  if (sub.includes('--help') || sub.includes('-h')) return null;
  if (sub[0] === 'alias' && sub[1] === 'set' && sub.some(w => /\bmerge\b/.test(w))) return 'it defines an alias that merges';
  const merging = tool === 'gh' ? sub[0] === 'pr' && sub[1] === 'merge'
    : sub[0] === 'mr' && (sub[1] === 'merge' || sub[1] === 'accept');
  if (merging && before.some(w => exeName(w) === 'xargs')) return 'its PR number comes from xargs';
  if (merging) {
    const args = sub.slice(2);
    const sel = selector(args), repo = flagValue(args, ['-R', '--repo']) || globalRepo;
    const target = [...(sel ? [sel] : []), ...(repo ? ['-R', repo] : [])];
    return tool === 'gh'
      ? ['gh', ['pr', 'view', ...target, '--json', 'headRefOid', '-q', '.headRefOid'], viaText]
      : ['glab', ['mr', 'view', ...target, '-F', 'json'], viaJson];
  }
  if (sub[0] !== 'api') return null;
  if (sub.includes('graphql')) {
    if (sub.some(w => graphqlMerge(w))) return 'it is a GraphQL merge';
    // a query read from a file (`-F query=@q.graphql`, `--input q.json`) is a merge when the file holds one
    const files = [];
    for (let i = 1; i < sub.length; i++) {
      const w = sub[i];
      const field = w === '-F' || w === '--field' ? sub[++i]
        : /^(?:--field=|-F=?)(.+)$/.exec(w)?.[1];
      if (field?.startsWith('query=@')) files.push({ name: field.slice('query=@'.length), json: false });
      if (w === '--input') files.push({ name: sub[++i], json: true });
      else if (w.startsWith('--input=')) files.push({ name: w.slice('--input='.length), json: true });
    }
    for (const { name: f, json } of files) {
      if (!f || f === '-' || /[$`]/.test(f)) return 'its GraphQL query file cannot be resolved before execution';
      let text;
      try { text = fs.readFileSync(path.resolve(cwd, f), 'utf8'); } catch { return `its GraphQL query file ${f} cannot be read`; }
      if (json) {
        try { text = JSON.parse(text).query; } catch { return 'its GraphQL input is not valid JSON'; }
        if (typeof text !== 'string') return 'its GraphQL input has no query string';
      }
      if (graphqlMerge(text)) return 'it is a GraphQL merge';
    }
    return null;
  }
  const endpoint = sub.find(w => MERGE_ENDPOINT.test(w));
  const method = flagValue(sub, ['-X', '--method']) || (sub.find(w => /^-X./.test(w)) || '').slice(2);
  if (!endpoint || method.toUpperCase() !== 'PUT') return null;  // GET only reads
  const pr = endpoint.replace(/^\//, '').replace(/\/merge\/?(?:\?.*)?$/, '');
  return tool === 'gh' ? ['gh', ['api', pr, '--jq', '.head.sha'], viaText] : ['glab', ['api', pr], viaJson];
}

/** The directory a `cd` / `Set-Location` segment moves to, or null when it does not move. */
function cdTarget(words, cwd) {
  const c = words.findIndex(w => !CONTROL.test(w));
  if (!CD.test(words[c] || '')) return null;
  const arg = words.slice(c + 1).find(w => !/^(-path|-literalpath|-p|-l|--)$/i.test(w));
  if (!arg || arg === '-') return null;
  let to = arg.replace(/^~(?=$|[\\/])/, os.homedir());
  if (process.platform === 'win32') to = to.replace(/^\/([a-z])(?=$|\/)/i, '$1:/');  // Git Bash's /d/dev
  to = path.resolve(cwd, to);
  return fs.existsSync(to) && fs.statSync(to).isDirectory() ? to : null;  // a cd that fails stays put
}

/** Every merge call in the command: {lookup, cwd, env, attested}. `cd` segments move the working directory. */
function merges(cmd, cwd, ps = false, inherited = {}) {
  const found = [];
  const exported = { ...inherited };
  for (const seg of segments(cmd, ps)) {
    const { vars, rest: words, lasting } = leadingAssignments(seg);
    if (lasting) Object.assign(exported, vars);
    const env = { ...exported, ...vars };
    const to = cdTarget(words, cwd);
    if (to) { cwd = to; continue; }
    const s = words.findIndex(w => SHELLS.test(exeName(w)));
    if (s >= 0) {
      const f = words.findIndex((w, i) => i > s && SHELL_SCRIPT_FLAG.test(w));
      if (f >= 0 && f + 1 < words.length) {
        found.push(...merges(words[f + 1], cwd, /^(pwsh|powershell)$/i.test(exeName(words[s])), env));
      }
    }
    const e = words.findIndex(w => EVALS.test(w));
    if (e >= 0) found.push(...merges(words.slice(e + 1).join(' '), cwd, ps || words[e].toLowerCase() !== 'eval', env));
    for (let k = 0; k < words.length; k++) {
      const tool = exeName(words[k]);
      if (tool !== 'gh' && tool !== 'glab') continue;
      const lookup = lookupOf(tool, words.slice(k + 1), words.slice(0, k), cwd);
      const dynamic = Object.entries(env).find(([, v]) => /[$`]/.test(v));
      if (lookup) found.push({ lookup: dynamic ? `its ${dynamic[0]} assignment cannot be resolved before execution; use a literal value` : lookup,
        cwd, env, attested: env.SHIP_REVIEWED || null });
    }
  }
  return found;
}

function run(exe, args, cwd, env = {}) {
  const timeout = DEADLINE - Date.now();
  if (timeout < 1000) throw new Error('out of time for the head lookups');
  const r = spawnSync(exe, args, { cwd, env: { ...process.env, ...env }, encoding: 'utf8', shell: false, timeout,
    windowsHide: true });
  if (r.error || r.status !== 0) throw new Error((r.stderr || r.error?.message || `${exe} failed`).trim().split('\n')[0]);
  return r.stdout.trim();
}

function recorded(cwd, sha, exec) {
  try {
    const dir = exec('git', ['rev-parse', '--path-format=absolute', '--git-common-dir'], cwd);
    return fs.readFileSync(path.join(dir, RECORD), 'utf8').split(/\r?\n/).some(l => l.split(/\s+/)[0] === sha);
  } catch { return false; }  // not in a repo, or nothing recorded yet
}

/** An attested SHA may be a prefix of the head, at least 7 characters. */
const attests = (prefix, sha) => !!prefix && prefix.length >= 7 && sha.toLowerCase().startsWith(prefix.toLowerCase());

/** The reason to deny, or null. `exec` is injectable for tests. */
function check(cmd, cwd, exec = run, ps = false) {
  for (const m of merges(cmd, cwd, ps)) {
    if (typeof m.lookup === 'string') {
      return `This merge cannot be checked: ${m.lookup}, so its head is not visible. Merge with \`gh pr merge <n>\` `
        + '(or `glab mr merge <n>`) so the guard can match the head against its review.';
    }
    const [exe, args, parse] = m.lookup;
    let sha;
    try { sha = parse(exec(exe, args, m.cwd, m.env)); } catch (e) {
      return `Could not read the head of this merge (${e.message}). Check the PR exists and gh/glab is logged in, then retry.`;
    }
    if (m.attested) {
      if (attests(m.attested, sha)) continue;
      return `SHIP_REVIEWED=${m.attested} does not match the head ${sha.slice(0, 12)} of this merge: commits landed after `
        + 'that review. Review the new head, or attest it only after the user confirms it was reviewed.';
    }
    if (recorded(m.cwd, sha, exec)) continue;
    return `This merge waits for a code review of its head ${sha.slice(0, 12)}. Run the code-review skill against it `
      + '(fixed point origin/<target>); when the review leaves nothing to fix, its patch records the head and this '
      + 'merge goes through. If the head was reviewed another way, ask the user; only once they confirm this exact '
      + `head, prefix SHIP_REVIEWED=${sha} to the command (PowerShell: $env:SHIP_REVIEWED='${sha}'; before it).`;
  }
  return null;
}

if (require.main === module) {
  const event = JSON.parse(fs.readFileSync(0, 'utf8'));
  // Codex's shell tool runs PowerShell on Windows unless it names a POSIX shell: the same call as codex.js, change both.
  const ps = event.tool_name === 'PowerShell' || (process.argv[2] === 'codex' && process.platform === 'win32'
    && !/bash|zsh|\/sh$/.test(event.tool_input?.shell || ''));
  const reason = check(event.tool_input?.command || '', event.cwd || process.cwd(), run, ps);
  if (reason) {
    process.stdout.write(JSON.stringify({ hookSpecificOutput: {
      hookEventName: 'PreToolUse', permissionDecision: 'deny', permissionDecisionReason: reason } }));
  }
}

module.exports = { check, RECORD };
