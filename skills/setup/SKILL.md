---
name: setup
description: Register (or re-register) the win-toast app identity and claude-focus:// protocol handler, then send a test toast. Use when the user asks to set up, repair, or test Windows toast notifications for Claude Code.
---

# win-toast setup

Registration normally happens automatically on `SessionStart`. Run this skill when the user wants to force it, verify it, or see a test notification.

1. Register (idempotent; `-Force` rewrites everything):

   ```
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/register.ps1" -Force
   ```

2. Send a test toast so the user can confirm it appears and that clicking it focuses the terminal:

   ```
   echo '{"cwd":"'"$PWD"'","message":"win-toast is working. Click me to focus the terminal.","title":"Test"}' | powershell.exe -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/notify.ps1" -Event Notification
   ```

3. Tell the user what was registered (the script prints the icon, handler exe, and protocol command) and remind them that if a toast never appears, Windows notification settings or Focus Assist may be suppressing "Claude Code".

Troubleshooting:
- Toast shows sender "Windows PowerShell": the AppUserModelId registration is missing → rerun step 1.
- Sender reads `ClaudeCode.WinToast`: a toast was shown while the AppUserModelId key did not exist (typically the plugin was installed into a running session, so `SessionStart` never ran `register.ps1` before the first `Stop`). Windows caches the name it resolved at that first toast for the whole logon session: run step 1 (already prevented since 1.2.1, which registers just-in-time), then the user must sign out / reboot once.
- Sender is "Claude Code" but there is no icon next to it: Windows caches the icon per AUMID for the logon session; the user needs to sign out / reboot (re-registering does not help until then).
- Click does nothing: check `HKCU\Software\Classes\claude-focus\shell\open\command` points at `<data>\claude-focus.exe` and that the exe exists → rerun step 1 (it recompiles from `scripts/focus-terminal.cs`).
- Step 1 fails with "compile failed": `csc.exe` (inbox .NET Framework 4.x) is missing or the source has a syntax error; show the user the compiler output.
- Wrong tab selected: tab matching uses the session title; rename the session with `/rename` to disambiguate.
