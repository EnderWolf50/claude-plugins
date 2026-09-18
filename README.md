# win-toast

Windows toast notifications for [Claude Code](https://code.claude.com), with click-to-focus for Windows Terminal.

| Event | When | Toast |
|---|---|---|
| `Notification` | Claude needs permission / is waiting for input | Claude's message |
| `Stop` | Claude finished a turn | **Session title** + first 180 chars of the response |

Every toast shows the project folder as attribution, is sent as **"Claude Code"** (own icon, not "Windows PowerShell"), and **clicking it brings back the Windows Terminal window and selects the tab** that owns the session.

No dependencies: Windows PowerShell 5.1 + the built-in WinRT toast API. Works on Windows 10/11.

## Install

```
claude plugin marketplace add EnderWolf50/claude-win-toast
claude plugin install win-toast@enderwolf50
```

Or, from a local checkout: `claude --plugin-dir D:\claude-win-toast`.

Registration (app identity + `claude-focus://` protocol) runs automatically on `SessionStart`. To force it or send a test toast, run `/win-toast:setup`.

## How it works

```
hook (Notification / Stop, async)
  └─ scripts/notify.ps1
       ├─ reads hook JSON from stdin
       ├─ title  ← transcript: custom-title (/rename) > ai-title > "Claude Code"
       ├─ body   ← last_assistant_message, markdown stripped, 180 chars
       ├─ hwnd   ← first ancestor process that owns a top-level window (WindowsTerminal.exe, Code.exe, ...)
       └─ toast  launch="claude-focus://focus?hwnd=…&title=…"

click
  └─ claude-focus:// (HKCU protocol handler)
       └─ scripts/focus-terminal.vbs  (hidden launcher)
            └─ scripts/focus-terminal.ps1
                 ├─ SetForegroundWindow(hwnd)  (restores if minimized)
                 └─ UI Automation: select the TabItem whose name contains the session title
```

`scripts/register.ps1` (idempotent, runs on `SessionStart`):
- copies the icon to `$CLAUDE_PLUGIN_DATA` (stable across plugin updates)
- `HKCU\Software\Classes\AppUserModelId\Anthropic.ClaudeCode` → DisplayName "Claude Code" + IconUri
- `HKCU\Software\Classes\claude-focus` → `wscript.exe "<plugin>/scripts/focus-terminal.vbs" "%1"`

## Files

```
.claude-plugin/plugin.json      manifest
.claude-plugin/marketplace.json lets the repo be added as a marketplace
hooks/hooks.json                SessionStart / Notification / Stop
scripts/notify.ps1              build + show the toast
scripts/register.ps1            app-id + protocol registration
scripts/focus-terminal.vbs      hidden launcher for the protocol handler
scripts/focus-terminal.ps1      focus window + select tab
skills/setup/SKILL.md           /win-toast:setup
assets/claude-code.png          toast icon
```

## Tweaks

- Preview length: `notify.ps1`, the `Substring(0, 180)` line.
- Sound: `notify.ps1`, the `<audio src="…">` element (`silent="true"` to mute).
- Tab matching is by session title (`*title*`). Use `/rename` if two sessions share a title.

## Uninstall

```
claude plugin uninstall win-toast@enderwolf50
```

Registry keys (optional cleanup):
```
reg delete HKCU\Software\Classes\AppUserModelId\Anthropic.ClaudeCode /f
reg delete HKCU\Software\Classes\claude-focus /f
```
