# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Native Codex bridge. No Anthropic SDK, credentials, or recursive review hooks."""
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'vendor'))
from patterns import SECURITY_PATTERNS

SECURITY_INSTRUCTIONS = ('Review security vulnerabilities introduced by the selected changes only. '
    'Prioritize exploitable injection, XSS, SSRF, path traversal, authorization errors, secret exposure, '
    'unsafe deserialization and cryptography. Give concrete file/line evidence and attack preconditions. '
    'Do not modify files or review unrelated existing problems. Report no findings when none are substantiated.')

def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()

def git(cwd, *args):
    result = subprocess.run(['git', '-C', str(cwd), *args], capture_output=True, text=True,
                            encoding='utf-8', errors='replace', timeout=10)
    return result.stdout.strip() if result.returncode == 0 else ''

def emit(event, text):
    print(json.dumps({'hookSpecificOutput': {'hookEventName': event['hook_event_name'],
                                           'additionalContext': text}}, ensure_ascii=False))

def pattern_matches(file, content):
    found = {}
    file = file.replace('\\', '/').lstrip('/')
    for rule in SECURITY_PATTERNS:
        if 'path_filter' in rule and not rule['path_filter'](file):
            continue
        if (('path_check' in rule and rule['path_check'](file)) or
            any(s in content for s in rule.get('substrings', [])) or
            ('regex' in rule and re.search(rule['regex'], content))):
            found[rule['ruleName']] = rule['reminder']
    return found

def patch_files(patch):
    file, lines = None, []
    for line in patch.splitlines():
        match = re.match(r'^\*\*\* (?:Add|Update) File: (.+)$', line)
        if match:
            if file is not None:
                yield file, '\n'.join(lines)
            file, lines = match[1], []
        elif line.startswith('*** '):
            if file is not None:
                yield file, '\n'.join(lines)
            file, lines = None, []
        elif file is not None and line.startswith('+'):
            lines.append(line[1:])
    if file is not None:
        yield file, '\n'.join(lines)

def git_commands(command, cwd):
    # Parse literals without invoking a shell. Dynamic commands are deliberately
    # skipped, as executing them to discover a cwd would repeat side effects.
    try:
        lexer = shlex.shlex(command, posix=False, punctuation_chars=';&|\n')
        lexer.whitespace = ' \t\r'
        lexer.whitespace_split = True
        words = list(lexer)
    except ValueError:
        return
    segments, part = [], []
    for word in words + [';']:
        if word and all(c in ';&|\n' for c in word):
            if part:
                segments.append(part)
            part = []
        else:
            part.append(word.strip('\"\''))
    for words in segments:
        if not words or Path(words[0].replace('\\', '/')).name.lower() not in ('git', 'git.exe'):
            continue
        directory, i = Path(cwd), 1
        while i < len(words) and words[i] == '-C':
            if i+1 >= len(words) or any(c in words[i+1] for c in '$`*?'):
                break
            directory = directory / words[i+1]
            i += 2
        if i < len(words) and words[i] in ('commit', 'push'):
            yield str(directory), words[i]

def review(cwd, sha, state):
    if not re.fullmatch(r'[0-9a-f]{40,64}', sha):
        return ''
    key = digest(str(Path(cwd).resolve()) + ':' + sha)
    done, lock = state / (key + '.done'), state / (key + '.lock')
    if done.exists():
        return ''
    try:
        fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    except FileExistsError:
        # A crashed reviewer may leave a claim; allow retry after its hard timeout.
        if time.time() - lock.stat().st_mtime > 900:
            lock.unlink(missing_ok=True)
        return ''
    os.close(fd)
    try:
        # Config overrides apply only to this child. Keep the user's current model.
        with tempfile.TemporaryDirectory(prefix='security-review-') as temporary:
            output = Path(temporary) / 'report.txt'
            command = ['codex', 'exec', 'review', '--commit', sha, '--disable', 'hooks', '--ephemeral',
            '-c', 'approval_policy="never"', '-c', 'sandbox_mode="read-only"',
            '-c', 'developer_instructions=' + json.dumps(SECURITY_INSTRUCTIONS), '-o', str(output)]
            result = subprocess.run(command, cwd=cwd, capture_output=True, text=True,
                encoding='utf-8', errors='replace', timeout=240)
            report = output.read_text(encoding='utf-8').strip() if output.exists() else ''
        if result.returncode:
            return f'Security review of {sha[:12]} failed (exit {result.returncode}); retry manually with codex review --commit {sha}.'
        if not report:
            return f'Security review of {sha[:12]} returned no report; it has not been marked reviewed.'
        done.write_text(report, encoding='utf-8')
        return f'Security review of {sha[:12]}:\n{report[-16000:]}'
    except (OSError, subprocess.TimeoutExpired) as error:
        return f'Security review of {sha[:12]} could not finish: {type(error).__name__}. Retry manually.'
    finally:
        lock.unlink(missing_ok=True)

def main(event):
    if os.environ.get('SECURITY_GUIDANCE_DISABLE') == '1' or os.environ.get('ENABLE_SECURITY_REMINDER') == '0':
        return
    kind, tool = event['hook_event_name'], event.get('tool_name')
    data = event.get('tool_input') or {}
    state = Path(os.environ.get('PLUGIN_DATA', str(Path.home()/'.codex/security-guidance')))
    state.mkdir(parents=True, exist_ok=True)
    session = digest(event.get('session_id', 'unknown'))
    if kind == 'PostToolUse' and tool in ('apply_patch', 'Edit', 'Write'):
        if os.environ.get('ENABLE_PATTERN_RULES', '1') == '0':
            return
        files = list(patch_files(data.get('command', ''))) if tool == 'apply_patch' else [(data.get('file_path', ''), data.get('new_string', data.get('content', '')))]
        warnings = []
        for file, content in files:
            for rule, message in pattern_matches(file, content).items():
                marker = state / (session + '-' + digest(file+rule) + '.warning')
                try:
                    with marker.open('x', encoding='utf-8') as stream:
                        stream.write('shown')
                except FileExistsError:
                    continue
                warnings.append(file + ': ' + message)
        if warnings:
            emit(event, '\n\n'.join(warnings))
        return
    # Retain this user's Stop-review-off preference. No model call on Stop.
    if kind == 'Stop':
        return
    if tool != 'Bash' or os.environ.get('ENABLE_CODE_SECURITY_REVIEW', '1') == '0':
        return
    identity = event.get('tool_use_id')
    if not identity:
        return
    capture = state / (session + '-' + digest(identity) + '.pending')
    if kind == 'PreToolUse':
        entries = []
        for cwd, action in git_commands(data.get('command', ''), event.get('cwd', os.getcwd())):
            root = git(cwd, 'rev-parse', '--show-toplevel')
            if not root:
                continue
            head = git(root, 'rev-parse', 'HEAD')
            # Capture the outgoing range BEFORE push updates tracking refs.
            outgoing = git(root, 'rev-list', '--reverse', '@{upstream}..HEAD').splitlines() if action == 'push' else []
            entries.append({'root': root, 'action': action, 'head': head, 'outgoing': outgoing})
        if entries:
            capture.write_text(json.dumps(entries), encoding='utf-8')
    elif kind == 'PostToolUse' and capture.exists():
        # A failed compound command can still have created a commit. Compare the
        # immutable pre/post SHA rather than trusting only its final exit status.
        claim = capture.with_suffix('.claimed-' + str(os.getpid()))
        try:
            capture.rename(claim)
        except FileNotFoundError:
            return
        entries = json.loads(claim.read_text(encoding='utf-8'))
        claim.unlink(missing_ok=True)
        reports = []
        for entry in entries:
            current = git(entry['root'], 'rev-parse', 'HEAD')
            if entry['action'] == 'commit':
                if os.environ.get('ENABLE_COMMIT_REVIEW', '1') == '0' or current == entry['head']:
                    continue
                commits = git(entry['root'], 'rev-list', '--reverse', entry['head']+'..'+current).splitlines() if entry['head'] else [current]
            else:
                commits = entry['outgoing'] or [entry['head']]
            for sha in commits:
                report = review(entry['root'], sha, state)
                if report:
                    reports.append(report)
        if reports:
            emit(event, '\n\n'.join(reports))

if __name__ == '__main__':
    main(json.load(sys.stdin))
