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

3. Tell the user what was registered (the script prints the icon path and protocol command) and remind them that if a toast never appears, Windows notification settings or Focus Assist may be suppressing "Claude Code".

Troubleshooting:
- Toast shows sender "Windows PowerShell": the AppUserModelId registration is missing → rerun step 1.
- Click does nothing: check `HKCU\Software\Classes\claude-focus\shell\open\command` points at the current plugin's `scripts/focus-terminal.vbs` → rerun step 1 (plugin updates move the path; `SessionStart` normally fixes this).
- Wrong tab selected: tab matching uses the session title; rename the session with `/rename` to disambiguate.
