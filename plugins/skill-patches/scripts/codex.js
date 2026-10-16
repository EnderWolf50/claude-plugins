// Codex has no Skill/UserPromptExpansion event. Keep the global instruction fallback too.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const event = JSON.parse(fs.readFileSync(0, 'utf8'));
const home = process.env.SKILL_PATCHES_HOME || os.homedir();
let root = path.resolve(event.cwd || process.cwd());
while (!fs.existsSync(path.join(root, '.git')) && path.dirname(root) !== root) root = path.dirname(root);
// Outside a repository, use the session directory rather than the filesystem root.
if (!fs.existsSync(path.join(root, '.git'))) root = path.resolve(event.cwd || process.cwd());
const dirs = [path.join(home, '.claude/skills'), path.join(home, '.agents/skills')];
if (root !== path.resolve(home)) dirs.push(path.join(root, '.claude/skills'), path.join(root, '.agents/skills'));
const session = crypto.createHash('sha256').update(String(event.session_id || '')).digest('hex');
const marks = path.join(process.env.PLUGIN_DATA || os.tmpdir(), 'skill-patches-codex', session);
if (event.hook_event_name === 'SessionStart') {
  // Delete only this session's known marker files, keeping concurrent sessions independent.
  if (fs.existsSync(marks)) for (const file of fs.readdirSync(marks)) if (/^[a-zA-Z0-9_.-]+$/.test(file)) fs.unlinkSync(path.join(marks, file));
  process.exit(0);
}
const safe = name => /^[a-zA-Z0-9][a-zA-Z0-9_.-]*$/.test(name);
const names = new Set();
if (event.hook_event_name === 'UserPromptSubmit') {
  for (const match of String(event.prompt || '').matchAll(/(?:^|\s)\$([a-zA-Z0-9][\w.-]*)/g)) names.add(match[1]);
}
if (event.hook_event_name === 'PostToolUse') {
  // Observe concrete skill file reads. Arbitrary shell expressions are left to the instruction fallback.
  const command = String(event.tool_input?.command || '');
  for (const match of command.matchAll(/"([^"\r\n]*SKILL\.md)"|'([^'\r\n]*SKILL\.md)'|([^\s;"'`]+SKILL\.md)/g)) {
    const candidate = (match[1] || match[2] || match[3]).replace(/^(~|\$HOME|\$\{HOME\}|\$env:USERPROFILE)(?=[/\\])/i, home);
    const file = path.resolve(event.cwd || process.cwd(), candidate);
    for (const dir of dirs) {
      const relative = path.relative(dir, file).split(path.sep);
      if (relative.length === 2 && relative[1] === 'SKILL.md' && safe(relative[0]) && !relative[0].endsWith('.patch') && fs.existsSync(file)) names.add(relative[0]);
    }
  }
  if (String(event.tool_name || '').startsWith('mcp__')) {
    for (const dir of dirs) {
      if (!fs.existsSync(dir)) continue;
      for (const name of fs.readdirSync(dir)) {
        if (!name.endsWith('.patch') || !safe(name)) continue;
        const file = path.join(dir, name, 'SKILL.md');
        if (!fs.existsSync(file)) continue;
        const front = fs.readFileSync(file, 'utf8').match(/^---\r?\n([\s\S]*?)\r?\n---/);
        const patterns = front?.[1].match(/^patch-tools:\s*(.+)$/m)?.[1].trim().split(/\s+/) || [];
        const matches = patterns.some(pattern => new RegExp('^' + pattern.replace(/[.+?^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*') + '$').test(event.tool_name));
        if (matches) names.add(name.slice(0, -6));
      }
    }
  }
}
const context = [];
for (const name of names) {
  if (!safe(name)) continue;
  const seen = new Set();
  const body = [];
  for (const dir of dirs) {
    const file = path.join(dir, `${name}.patch/SKILL.md`);
    if (!fs.existsSync(file)) continue;
    const real = fs.realpathSync(file);
    if (seen.has(real)) continue;
    seen.add(real);
    body.push(fs.readFileSync(file, 'utf8').replace(/^---\r?\n[\s\S]*?\r?\n---\r?\n?/, ''));
  }
  if (!body.length) continue;
  const text = body.join('\n\n');
  const digest = crypto.createHash('sha256').update(text).digest('hex');
  const mark = path.join(marks, name);
  if (event.session_id && fs.existsSync(mark) && fs.readFileSync(mark, 'utf8') === digest) continue;
  context.push(`Patch for skill ${name} (overrides the skill where they conflict):\n${text}`);
  if (event.session_id) { fs.mkdirSync(marks, { recursive: true }); fs.writeFileSync(mark, digest); }
}
if (context.length) process.stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: event.hook_event_name, additionalContext: context.join('\n\n') } }));
