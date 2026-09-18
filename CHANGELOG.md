# Changelog

## 1.2.0
- Toast sender icon now shows next to the title. The AUMID is `ClaudeCode.WinToast` (was `Anthropic.ClaudeCode`; the old key is removed on registration), `IconUri` points at a multi-size `assets/claude-code.ico`, and the registry values are written as `REG_EXPAND_SZ`.
- Dropped the inline `appLogoOverride` image (large icon beside the body).
- Documented the per-logon-session icon cache: change the icon -> sign out or reboot to see it.

## 1.1.0
- Protocol handler is now a tiny C# WinExe (`scripts/focus-terminal.cs`) compiled by `register.ps1` with the inbox `csc.exe`. Replaces the `wscript` -> PowerShell chain: no console flash, click-to-focus ~0.2 s instead of ~1 s.
- Handler lives in `$CLAUDE_PLUGIN_DATA`, so plugin updates no longer require re-registering the protocol.

## 1.0.0
- Initial release.
