# Changelog

## Unreleased
- Marketplace moved to [EnderWolf50/claude-plugins](https://github.com/EnderWolf50/claude-plugins); this repo no longer ships a marketplace.json. Existing installs keep working; to follow updates re-add the marketplace from the new repo.

## 1.2.1
- Fix: the toast sender showed the raw AUMID `ClaudeCode.WinToast` instead of "Claude Code" when the plugin was installed into a running session (`/plugin install` + `/reload-plugins`). The hooks were live but `SessionStart` had not fired, so `register.ps1` had never run and the first toast went out for an unregistered AUMID; Windows resolves the sender name at that first toast and keeps it for the whole logon session. `notify.ps1` now registers the identity itself (`register.ps1 -NoBuild`, no compile) before showing a toast whenever the key is missing.
- `register.ps1` writes the icon + AUMID + protocol before compiling the click handler, so a compile failure can no longer leave toasts without an identity. New `-NoBuild` switch.
- Already seeing `ClaudeCode.WinToast` as the sender? Update, then sign out / reboot once; re-registering alone cannot evict the cached name.
- `tests/first-toast-unregistered.ps1`: regression check for the above.

## 1.2.0
- Toast sender icon now shows next to the title. The AUMID is `ClaudeCode.WinToast` (was `Anthropic.ClaudeCode`; the old key is removed on registration), `IconUri` points at a multi-size `assets/claude-code.ico`, and the registry values are written as `REG_EXPAND_SZ`.
- Dropped the inline `appLogoOverride` image (large icon beside the body).
- Documented the per-logon-session icon cache: change the icon -> sign out or reboot to see it.

## 1.1.0
- Protocol handler is now a tiny C# WinExe (`scripts/focus-terminal.cs`) compiled by `register.ps1` with the inbox `csc.exe`. Replaces the `wscript` -> PowerShell chain: no console flash, click-to-focus ~0.2 s instead of ~1 s.
- Handler lives in `$CLAUDE_PLUGIN_DATA`, so plugin updates no longer require re-registering the protocol.

## 1.0.0
- Initial release.
