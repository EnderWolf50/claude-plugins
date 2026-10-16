"""Cross-platform hook contract checks; no model calls or trusted hooks needed."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def invoke(script, event, env=None):
    result = subprocess.run(["node", str(ROOT / script)], input=json.dumps(event), text=True,
                            capture_output=True, env={**os.environ, **(env or {})}, check=True)
    return json.loads(result.stdout) if result.stdout.strip() else {}


class Hooks(unittest.TestCase):
    def test_guards(self):
        deny = ["git add -A", "git commit -am fix", "git add .", "chezmoi apply --force",
                "git -C somewhere add --all", "echo ok; git add -A"]
        allow = ['git add src/app.py', 'git commit -m "fix git add -A"',
                 'chezmoi apply --force ~/.codex/AGENTS.md', 'chezmoi apply --force --dry-run']
        if os.name == "nt":
            deny += ['& "C:\\Program Files\\Git\\cmd\\git.exe" add -A', 'if ($true) { git add . }']
            allow += ["$message = @'\ngit add -A\n'@\nWrite-Output $message"]
            allow += ['git commit --message "-a"', 'git commit --file message.txt']
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
            cc = json.loads((directory / '.claude-plugin/plugin.json').read_text())
            cx = json.loads((directory / '.codex-plugin/plugin.json').read_text())
            self.assertEqual(cc['version'], cx['version'])
            hooks = json.loads((directory / cx['hooks']).read_text())
            self.assertNotIn('UserPromptExpansion', hooks['hooks'])


if __name__ == '__main__':
    unittest.main()
