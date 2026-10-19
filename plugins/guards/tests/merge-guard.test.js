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

test('a merge after a prefix word, in a subshell or inside a shell script is still found', () => {
  const dir = repo();
  for (const cmd of ['command gh pr merge 5', 'sudo gh pr merge 5', 'timeout 60 gh pr merge 5', '(gh pr merge 5)',
    'echo $(gh pr merge 5)', 'if true; then gh pr merge 5; fi', '{ gh pr merge 5; }', 'bash -c "gh pr merge 5"',
    "wsl.exe -e bash -lc 'cd x && gh pr merge 5'", 'pwsh -NoProfile -c "gh pr merge 5"', 'cmd /c gh pr merge 5',
    'glab api --method PUT projects/1/merge_requests/7/merge?x=1']) {
    assert.match(g.check(cmd, '.', stub(dir)) || '', /waits for a code review/, cmd);
  }
});

test('PowerShell paths and backtick escapes', () => {
  const dir = repo();
  for (const cmd of ['C:\\tools\\gh.exe pr merge 5', '& "C:\\Program Files\\GitHub CLI\\gh.exe" pr merge 5',
    'echo "a`"b"; gh pr merge 6', 'if ($true) { gh pr merge 5 }']) {
    assert.match(g.check(cmd, '.', stub(dir), true) || '', /waits for a code review/, cmd);
  }
});

test('heredoc bodies, reads of the merge endpoint and quoted text are not merges', () => {
  const calls = [];
  for (const cmd of ['cat <<EOF > notes.md\ngh pr merge 1\nEOF\ngit status', "cat <<-'X'\n\tgh pr merge 1\n\tX",
    'gh api repos/o/r/pulls/5/merge', 'gh api repos/o/r/pulls/5/merge --method GET', 'git commit -m "gh pr merge 1"']) {
    assert.equal(g.check(cmd, '.', stub(repo(), calls)), null, cmd);
  }
  assert.deepEqual(calls, []);
});

test('a GraphQL merge and xargs hide the head, so they are denied without a lookup', () => {
  const calls = [];
  for (const cmd of ["gh api graphql -f query='mutation { mergePullRequest(input: {}) { clientMutationId } }'",
    'echo 5 | xargs gh pr merge']) {
    assert.match(g.check(cmd, '.', stub(repo(), calls)), /cannot be checked/, cmd);
  }
  assert.deepEqual(calls, []);
});

test('the record is read where the merge runs, after a cd', () => {
  const calls = [];
  const dir = repo([`${HEAD} x`]);
  const exec = (exe, args, cwd) => { calls.push([exe, cwd]); return exe === 'git' ? dir : HEAD; };
  const other = repo();
  assert.equal(g.check(`cd ../${path.basename(other)} && gh pr merge 6`, path.join(os.tmpdir(), 'a'), exec), null);
  assert.deepEqual(calls.map(c => c[1]), [other, other]);
  calls.length = 0;
  g.check('cd ./no-such-dir && gh pr merge 6', other, exec);  // a failed cd stays put
  assert.deepEqual(calls.map(c => c[1]), [other, other]);
});

test('an inline assignment covers only its own command; export and $env: last', () => {
  const dir = repo();
  assert.match(g.check(`SHIP_REVIEWED=${HEAD} true; gh pr merge 5`, '.', stub(dir)), /waits for a code review/);
  assert.equal(g.check(`export SHIP_REVIEWED=${HEAD}; gh pr merge 5`, '.', stub(dir)), null);
  assert.equal(g.check(`$env:SHIP_REVIEWED = '${HEAD}'; gh pr merge 5`, '.', stub(dir), true), null);
});

test('a global -R, -XPUT, mr accept, eval and iex are found; a merging query file and alias are denied; --help is not a merge', () => {
  const calls = [];
  const dir = repo();
  for (const cmd of ['gh -R o/r pr merge 16 --squash', 'gh --repo=o/r pr merge 16', 'gh api -XPUT repos/o/r/pulls/5/merge',
    'glab mr accept 5', 'eval "gh pr merge 5"', 'iex "gh pr merge 5"']) {
    assert.match(g.check(cmd, '.', stub(dir, calls)) || '', /waits for a code review/, cmd);
  }
  assert.deepEqual(calls[0].slice(0, 6), ['gh', 'pr', 'view', '16', '-R', 'o/r']);
  fs.writeFileSync(path.join(dir, 'm.graphql'), 'mutation { mergePullRequest(input: {}) { clientMutationId } }');
  fs.writeFileSync(path.join(dir, 'q.graphql'), 'query { viewer { login } }');
  fs.writeFileSync(path.join(dir, 'm.json'), JSON.stringify({ query: 'mutation { mergePullRequest(input: {}) { clientMutationId } }' }));
  fs.writeFileSync(path.join(dir, 'q.json'), JSON.stringify({ query: 'query { viewer { login } }' }));
  for (const cmd of ['gh api graphql -F query=@m.graphql', 'gh api graphql -F query=@missing.graphql',
    'gh api graphql -Fquery=@m.graphql', 'gh api graphql --field=query=@m.graphql',
    'gh api graphql --input m.json', 'gh api graphql --input=m.json', 'gh api graphql --input=-',
    'gh api graphql -F query=@-',
    'gh alias set m "pr merge"']) {
    assert.match(g.check(cmd, dir, stub(dir)), /cannot be checked/, cmd);
  }
  for (const cmd of ['gh api graphql -F query=@q.graphql', 'gh api graphql -f query=@m.graphql',
    'gh api graphql -Fquery=@q.graphql', 'gh api graphql --field=query=@q.graphql',
    'gh api graphql --input q.json', 'gh api graphql --input=q.json',
    'gh api graphql -f query=\'query { viewer { login } }\' -f b=@alice']) {
    assert.equal(g.check(cmd, dir, stub(dir)), null, cmd);
  }
  assert.equal(g.check('gh pr merge --help', '.', stub(dir)), null);
});

test('the command\'s own variables reach the lookup, and cd after a keyword or with -Path moves', () => {
  const seen = [];
  const other = repo();
  const exec = (exe, args, cwd, env) => { seen.push([exe, cwd, env && env.GH_REPO]); return exe === 'git' ? other : HEAD; };
  g.check('GH_REPO=o/other gh pr merge 5', '.', exec);
  assert.equal(seen[0][2], 'o/other');
  seen.length = 0;
  assert.match(g.check('GH_REPO=$REPO gh pr merge 5', '.', exec), /GH_REPO assignment cannot be resolved/);
  assert.equal(seen.length, 0);  // never look up a different repository by dropping the assignment
  seen.length = 0;
  g.check(`if true; then cd ${other.replace(/\\/g, '/')} && gh pr merge 6; fi`, '.', exec);
  assert.equal(seen[0][1], other);
  seen.length = 0;
  g.check(`Set-Location -Path '${other}'; gh pr merge 6`, '.', exec, true);
  assert.equal(seen[0][1], other);
});

test('a failed head lookup is denied with a reason', () => {
  const failing = (exe) => { if (exe === 'gh') throw new Error('not logged in'); return '.'; };
  assert.match(g.check('gh pr merge 1', '.', failing), /not logged in/);
});
