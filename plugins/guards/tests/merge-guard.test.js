// node --test plugins/guards/tests/merge-guard.test.js
'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const g = require('../scripts/merge-guard.js');

const HEAD = 'abc1234def5678abc1234def5678abc1234def56';

function repo(lines) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'merge-guard-'));
  if (lines) fs.writeFileSync(path.join(dir, g.RECORD), lines.join('\n') + '\n');
  return dir;
}

// A stand-in for gh / glab / git: every PR has HEAD as its head, the git common dir is `dir`.
function stub(dir, calls = []) {
  return (exe, args) => {
    calls.push([exe, ...args]);
    if (exe === 'git') return dir;
    if (exe === 'gh') return HEAD;
    if (exe === 'glab') return JSON.stringify({ sha: HEAD });
    throw new Error('unexpected ' + exe);
  };
}

test('a merge with no review on record is denied, naming the head and both ways forward', () => {
  const reason = g.check('gh pr merge 171 --merge', '.', stub(repo()));
  assert.match(reason, /code-review skill/);
  assert.match(reason, new RegExp(`SHIP_REVIEWED=${HEAD}`));
});

test('a recorded head passes', () => {
  assert.equal(g.check('gh pr merge 171 --merge', '.', stub(repo([`${HEAD} 2026-10-19 code-review`]))), null);
});

test('a record of an older head does not cover a newer one', () => {
  assert.match(g.check('gh pr merge 171 --merge', '.', stub(repo(['0000000000000000000000000000000000000000 x']))), /waits for a code review/);
});

test('an attestation passes only for the current head', () => {
  const dir = repo();
  assert.equal(g.check(`SHIP_REVIEWED=${HEAD} gh pr merge 171 --merge`, '.', stub(dir)), null);
  assert.equal(g.check(`SHIP_REVIEWED=${HEAD.slice(0, 7)} gh pr merge 171`, '.', stub(dir)), null);
  assert.match(g.check('SHIP_REVIEWED=deadbeef gh pr merge 171', '.', stub(dir)), /does not match/);
  assert.equal(g.check(`$env:SHIP_REVIEWED='${HEAD}'; gh pr merge 171`, '.', stub(dir)), null);  // PowerShell
});

test('auto-merge, the API and GitLab are merges too', () => {
  const dir = repo();
  for (const cmd of ['gh pr merge 5 --auto --squash', 'gh api -X PUT repos/o/r/pulls/5/merge',
    'glab mr merge 7 --yes', "glab api --method PUT 'projects/:id/merge_requests/7/merge'"]) {
    assert.match(g.check(cmd, '.', stub(dir)), /waits for a code review/, cmd);
  }
});

test('the selector and repo reach the head lookup; flag values are not the selector', () => {
  const calls = [];
  g.check('gh pr merge -R o/r --subject "x y" 42 --merge', '.', stub(repo(), calls));
  assert.deepEqual(calls[0], ['gh', 'pr', 'view', '42', '-R', 'o/r', '--json', 'headRefOid', '-q', '.headRefOid']);
});

test('commands that are not merges pass without any lookup', () => {
  const calls = [];
  for (const cmd of ['gh pr view 171 --json state', 'git merge --ff-only origin/main', 'gh api repos/o/r/pulls/5',
    'echo "gh pr merge 1"', 'gh pr checks 5 --watch']) {
    assert.equal(g.check(cmd, '.', stub(repo(), calls)), null, cmd);
  }
  assert.deepEqual(calls, []);
});

test('every merge in a compound command is checked', () => {
  const dir = repo([`${HEAD} x`]);
  assert.equal(g.check('gh pr merge 1 --merge && git pull --ff-only', '.', stub(dir)), null);
  let n = 0;
  const twoHeads = (exe, args) => exe === 'git' ? dir : (n++ === 0 ? HEAD : 'f'.repeat(40));
  assert.match(g.check('gh pr merge 1 --merge; gh pr merge 2 --merge', '.', twoHeads), /ffffffffffff/);
});

test('a failed head lookup is denied with a reason', () => {
  const failing = (exe) => { if (exe === 'gh') throw new Error('not logged in'); return '.'; };
  assert.match(g.check('gh pr merge 1', '.', failing), /not logged in/);
});
