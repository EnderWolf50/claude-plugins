# search-tools

Keeps a tgrep server alive for a repo only while a Claude Code session is using it, and routes tree searches away from grep.

## Language

**Root**:
The directory a tgrep server indexes and serves; the project directory of the session that started it.
_Avoid_: repo, project, workspace

**Server**:
A running `tgrep serve <root>` process. Each root shows up as two processes (the scoop shim and the real exe); both are the same server.
_Avoid_: watcher, daemon

**Live session**:
A Claude Code session whose `~/.claude/sessions/<pid>.json` names a pid still in the process table.
_Avoid_: active session, open session

**In use**:
A root is in use while some live session has its cwd at or under that root.

**Orphan server**:
A server whose root is not in use. Orphan servers are reaped.
_Avoid_: stale server, dead server

**Reap**:
To kill every orphan server on the machine.
_Avoid_: cleanup, sweep

**Opt-in / Opt-out**:
A per-root override of the file-count threshold: opted-in roots are always served, opted-out roots never are. Opt-out wins.
