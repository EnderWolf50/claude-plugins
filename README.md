# win-toast

Windows toast notifications for [Claude Code](https://code.claude.com), with click-to-focus for Windows Terminal.

| Event | When | Toast |
|---|---|---|
| `Notification` | Claude needs permission / is waiting for input | Claude's message |
| `Stop` | Claude finished a turn | **Session title** + first 180 chars of the response |

Every toast shows the project folder as attribution, is sent as **"Claude Code"** (own icon, not "Windows PowerShell"), and **clicking it brings back the Windows Terminal window and selects the tab** that owns the session.

No dependencies: Windows PowerShell 5.1, the built-in WinRT toast API, and the inbox .NET Framework C# compiler (`csc.exe`, present on every Windows 10/11). Nothing to install, no binaries in the repo.

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
       └─ claude-focus.exe  (tiny WinExe compiled from scripts/focus-terminal.cs at registration;
                             no console window, ~200 ms)
            ├─ SetForegroundWindow(hwnd)  (restores if minimized)
            └─ UI Automation: select the TabItem whose name contains the session title
```

`scripts/register.ps1` (idempotent, runs on `SessionStart`; `notify.ps1` also runs it with `-NoBuild` if the AUMID key is missing when a toast is about to be shown):
- copies the icon to `$CLAUDE_PLUGIN_DATA` (stable across plugin updates)
- `HKCU\Software\Classes\AppUserModelId\ClaudeCode.WinToast` → DisplayName "Claude Code" + IconUri (`.ico`)
- `HKCU\Software\Classes\claude-focus` → `"<data>\claude-focus.exe" "%1"`
- compiles `scripts/focus-terminal.cs` → `$CLAUDE_PLUGIN_DATA\claude-focus.exe` (only when the source hash changes; skipped by `-NoBuild`)

## Files

```
.claude-plugin/plugin.json      manifest
.claude-plugin/marketplace.json lets the repo be added as a marketplace
hooks/hooks.json                SessionStart / Notification / Stop
scripts/notify.ps1              build + show the toast
scripts/register.ps1            icon + exe build + app-id + protocol registration
scripts/focus-terminal.cs       protocol handler: focus window + select tab (compiled by register.ps1)
skills/setup/SKILL.md           /win-toast:setup
assets/claude-code.ico          toast icon (multi-size .ico; .png kept as the source image)
tests/first-toast-unregistered.ps1  regression check: a toast sent before SessionStart must still carry the identity
```

## Tweaks

- Preview length: `notify.ps1`, the `Substring(0, 180)` line.
- Sound: `notify.ps1`, the `<audio src="…">` element (`silent="true"` to mute).
- Tab matching is by session title (`*title*`). Use `/rename` if two sessions share a title.

## Gotcha: sender name / icon cache

Windows resolves the AUMID's display name and icon the first time a toast is shown for it and caches the result for the whole logon session. Two consequences:

- If you swap `assets/claude-code.ico` (or the icon was missing the first time a toast fired), sign out or reboot before expecting the new icon.
- If a toast was ever sent while the `AppUserModelId\ClaudeCode.WinToast` key did not exist, the sender reads `ClaudeCode.WinToast` until you sign out. Since 1.2.1 `notify.ps1` registers the identity just-in-time so this cannot happen on a fresh install; if you saw it with 1.2.0, update and sign out once.

## Uninstall

```
claude plugin uninstall win-toast@enderwolf50
```

Optional cleanup:
```
reg delete HKCU\Software\Classes\AppUserModelId\ClaudeCode.WinToast /f
reg delete HKCU\Software\Classes\claude-focus /f
rmdir /s /q %USERPROFILE%\.claude\win-toast
```
