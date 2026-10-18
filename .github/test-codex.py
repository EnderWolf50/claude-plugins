"""Cross-platform hook contract checks; no model calls or trusted hooks needed."""
import json
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def invoke(script, event, env=None):
    result = subprocess.run(["node", str(ROOT / script)], input=json.dumps(event), text=True,
                            capture_output=True, env={**os.environ, **(env or {})}, check=True)
    return json.loads(result.stdout) if result.stdout.strip() else {}


class Hooks(unittest.TestCase):
    def test_search_grep(self):
        script = 'plugins/search-tools/scripts/codex.js'
        def run(command):
            return invoke(script, {'hook_event_name':'PreToolUse', 'tool_name':'Bash', 'cwd':str(ROOT),
                                   'tool_input':{'command':command}})
        result = run('grep -rn needle plugins')
        self.assertEqual(result['hookSpecificOutput']['permissionDecision'], 'allow')
        self.assertIn('rg', result['hookSpecificOutput']['updatedInput']['command'])
        self.assertEqual(run('git grep needle'), {})
        self.assertEqual(run('rg -n needle plugins'), {})
        self.assertEqual(run('xargs grep needle')['hookSpecificOutput']['permissionDecision'], 'deny')
        if os.name == 'nt':
            self.assertEqual(run('Write-Output "grep -r x ."'), {})
            self.assertEqual(run('grep -r $pattern .')['hookSpecificOutput']['permissionDecision'], 'deny')
            self.assertEqual(run("$s = @'\ngrep -r x .\n'@\nWrite-Output $s"), {})
            result = run("Write-Output ok; grep -rn 'a|b' plugins | Select-Object -First 2")
            self.assertIn('Write-Output ok;', result['hookSpecificOutput']['updatedInput']['command'])

    def test_security(self):
        spec = importlib.util.spec_from_file_location('security', ROOT/'plugins/security-guidance/scripts/codex.py')
        security = importlib.util.module_from_spec(spec); spec.loader.exec_module(security)
        self.assertEqual(len(security.SECURITY_PATTERNS), 25)
        matches = security.pattern_matches('src/load.py', 'pickle.loads(payload)')
        self.assertIn('pickle_deserialization', matches)
        self.assertFalse(security.pattern_matches('README.md', 'new Function'))
        files = list(security.patch_files('*** Begin Patch\n*** Update File: a.py\n@@\n-old\n+pickle.loads(payload)\n*** Add File: b.ts\n+eval(input)\n*** End Patch'))
        self.assertEqual(len(files), 2)
        self.assertNotIn('old', files[0][1])
        self.assertEqual(list(security.git_commands('echo "git commit"', str(ROOT))), [])
        self.assertEqual(list(security.git_commands('git -C "other dir" commit -m fix; git push', str(ROOT))),
                         [(str(ROOT/'other dir'), 'commit'), (str(ROOT), 'push')])
        self.assertFalse(list(security.git_commands('git -C $repo commit -m fix', str(ROOT))))
        with tempfile.TemporaryDirectory() as temporary:
            state = Path(temporary)
            sha = 'a'*40
            def reviewer(command, **kwargs):
                self.assertIn('--ephemeral', command)
                self.assertIn('hooks', command)
                self.assertIn('sandbox_mode="read-only"', command)
                Path(command[command.index('-o')+1]).write_text('No security findings.')
                return subprocess.CompletedProcess(command, 0, '', '')
            with patch.object(security.subprocess, 'run', side_effect=reviewer) as mock:
                self.assertIn('No security findings.', security.review(ROOT, sha, state))
                self.assertEqual(security.review(ROOT, sha, state), '')
                self.assertEqual(mock.call_count, 1)
            with patch.object(security.subprocess, 'run', side_effect=OSError('offline')):
                self.assertIn('could not finish', security.review(ROOT, 'b'*40, state))
            self.assertFalse(list(state.glob('*.lock')))
            self.assertEqual(len(list(state.glob('*.done'))), 1)
            with patch.object(security, 'review', side_effect=AssertionError('Stop must not review')):
                with patch.dict(os.environ, {'PLUGIN_DATA':str(state)}):
                    security.main({'hook_event_name':'Stop'})

    def test_security_commit_capture(self):
        spec = importlib.util.spec_from_file_location('security_integration', ROOT/'plugins/security-guidance/scripts/codex.py')
        security = importlib.util.module_from_spec(spec); spec.loader.exec_module(security)
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary); repo = base/'repo'; repo.mkdir()
            def git(*args):
                return subprocess.run(['git', '-c', 'core.hooksPath='+str(base/'no-hooks'), '-C', str(repo), *args],
                    capture_output=True, text=True, check=True).stdout.strip()
            git('init'); git('config', 'user.name', 'Hook test'); git('config', 'user.email', 'test@example.invalid')
            (repo/'one.txt').write_text('one')
            git('add', 'one.txt'); git('commit', '-m', 'initial')
            event = {'session_id':'test', 'tool_use_id':'commit-one', 'cwd':str(repo),
                     'tool_name':'Bash', 'tool_input':{'command':'git commit -m second'}}
            with patch.dict(os.environ, {'PLUGIN_DATA':str(base/'state')}):
                security.main({**event, 'hook_event_name':'PreToolUse'})
                (repo/'one.txt').write_text('two')
                git('add', 'one.txt'); git('commit', '-m', 'second')
                sha = git('rev-parse', 'HEAD')
                with patch.object(security, 'review', return_value='') as mock:
                    security.main({**event, 'hook_event_name':'PostToolUse'})
                    self.assertEqual(mock.call_args.args[1], sha)
                    security.main({**event, 'hook_event_name':'PostToolUse'})
                    self.assertEqual(mock.call_count, 1)

    def test_guards(self):
        deny = ["git add -A", "git commit -am fix", "git add .", "chezmoi apply --force",
                "git -C somewhere add --all", "echo ok; git add -A"]
        allow = ['git add src/app.py', 'git commit -m "fix git add -A"',
                 'chezmoi apply --force ~/.codex/AGENTS.md', 'chezmoi apply --force --dry-run',
                 r"printf '%s' 'a\\b'"]
        if os.name == "nt":
            deny += ['& "C:\\Program Files\\Git\\cmd\\git.exe" add -A', 'if ($true) { git add . }']
            allow += ["$message = @'\ngit add -A\n'@\nWrite-Output $message"]
            allow += ['git commit --message "-a"', 'git commit --file message.txt']
            allow += ["cat <<EOF\na\\\\b\nEOF"]   # pwsh cannot parse it and hands it to bash-guard.sh
        for command in deny + allow:
            with self.subTest(command=command):
                result = invoke('plugins/guards/scripts/codex.js', {
                    'hook_event_name': 'PreToolUse', 'tool_name': 'Bash', 'tool_input': {'command': command}})
                self.assertEqual(bool(result), command in deny)
                if result: self.assertEqual(result['hookSpecificOutput']['permissionDecision'], 'deny')

    def test_patches(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            home, project = base / 'home', base / 'repo'
            (project / '.git').mkdir(parents=True)
            nested = project / 'src'; nested.mkdir()
            skill = home / '.agents/skills/tdd/SKILL.md'
            skill.parent.mkdir(parents=True); skill.write_text('base skill')
            for root, body in [(home / '.agents/skills', 'global override'), (project / '.agents/skills', 'project override')]:
                patch = root / 'tdd.patch/SKILL.md'
                patch.parent.mkdir(parents=True)
                patch.write_text('---\nname: tdd.patch\npatch-tools: mcp__test__* mcp__my-server__*\n---\n' + body)
            env = {'SKILL_PATCHES_HOME': str(home), 'PLUGIN_DATA': str(base / 'state')}
            event = {'hook_event_name': 'UserPromptSubmit', 'session_id': 'one', 'cwd': str(nested), 'prompt': '$tdd build this'}
            run = lambda e: invoke('plugins/skill-patches/scripts/codex.js', e, env)
            text = run(event)['hookSpecificOutput']['additionalContext']
            self.assertLess(text.index('global override'), text.index('project override'))
            self.assertEqual(run(event), {})
            run({**event, 'hook_event_name': 'SessionStart', 'source': 'compact'})
            self.assertTrue(run(event))
            mcp = {**event, 'session_id': 'two', 'hook_event_name': 'PostToolUse', 'tool_name': 'mcp__test__read'}
            self.assertTrue(run(mcp))
            self.assertEqual(run(mcp), {})
            self.assertTrue(run({**mcp, 'session_id': 'normalized', 'tool_name': 'mcp__my_server__read'}))
            self.assertEqual(run({**mcp, 'session_id': 'other', 'tool_name': 'mcp__unrelated__read'}), {})
            read = {**event, 'session_id': 'three', 'hook_event_name': 'PostToolUse', 'tool_name': 'Bash', 'tool_input': {'command': f'cat "{skill}"'}}
            self.assertTrue(run(read))
            # Malicious-looking names never become filesystem paths or trigger arbitrary patches.
            self.assertEqual(run({**event, 'session_id': 'four', 'prompt': '$../../tdd'}), {})

    def test_native_catalog_and_manifests(self):
        catalog = json.loads((ROOT / '.agents/plugins/marketplace.json').read_text())
        for plugin in catalog['plugins']:
            directory = ROOT / plugin['source']['path']
            cx = json.loads((directory / '.codex-plugin/plugin.json').read_text())
            if (directory / '.claude-plugin/plugin.json').exists():
                cc = json.loads((directory / '.claude-plugin/plugin.json').read_text())
                self.assertEqual(cc['version'], cx['version'])
            hooks = json.loads((directory / cx['hooks']).read_text())
            self.assertNotIn('UserPromptExpansion', hooks['hooks'])


if __name__ == '__main__':
    unittest.main()
