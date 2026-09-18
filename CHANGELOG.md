# Changelog

## 1.1.0
- Protocol handler is now a tiny C# WinExe (`scripts/focus-terminal.cs`) compiled by `register.ps1` with the inbox `csc.exe`. Replaces the `wscript` -> PowerShell chain: no console flash, click-to-focus ~0.2 s instead of ~1 s.
- Handler lives in `$CLAUDE_PLUGIN_DATA`, so plugin updates no longer require re-registering the protocol.

## 1.0.0
- Initial release.
