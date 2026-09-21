---
name: reap
description: Stop every tgrep server whose repo no live Claude Code session is using, and show what is still running.
disable-model-invocation: true
---

# tgrep reap

1. Sweep (kills servers for roots with no live session; the current session's root is kept while this session is alive):

   ```
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/tgrep-serve.sh" reap
   ```

2. Show what survived:

   ```
   powershell.exe -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='tgrep.exe'\" | ForEach-Object { \$_.ProcessId.ToString() + '  ' + (\$_.CommandLine -replace '.* serve ','') }"
   ```

   Each root appears twice (scoop shim + real exe); that is normal.

3. Report the list to the user. To stop a specific one regardless: `taskkill /PID <pid> /F` (the index in `<root>/.tgrep` survives; the next `serve` reconciles it).
