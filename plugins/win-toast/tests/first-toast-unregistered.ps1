# Regression check: a toast that fires before register.ps1 ever ran must still carry the sender identity.
#
# Scenario (win-toast 1.2.0 bug): plugin installed into a running session (/plugin install + /reload-plugins)
# -> Notification/Stop hooks are live, SessionStart never fired -> the first toast is shown for an AUMID with no
# registry key -> Windows renders the raw AUMID "ClaudeCode.WinToast" as the sender and caches it for the
# whole logon session.
#
# The test removes the AUMID key (and the data-dir icon), fires ONE toast through notify.ps1 exactly like the
# hook does, and asserts the identity existed by the time Show() ran. It touches HKCU only and leaves the key
# registered afterwards. Run under Windows PowerShell 5.1:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\first-toast-unregistered.ps1
param([string]$Root = (Split-Path -Parent $PSScriptRoot))
$appId = 'ClaudeCode.WinToast'; $key = "HKCU:\Software\Classes\AppUserModelId\$appId"
$data = if ($env:CLAUDE_PLUGIN_DATA) { $env:CLAUDE_PLUGIN_DATA } else { Join-Path $HOME '.claude\win-toast' }
$icon = Join-Path $data 'claude-code.ico'

Remove-Item $key -Recurse -Force -ErrorAction SilentlyContinue
if (Test-Path $icon) { Rename-Item $icon "$icon.bak" -Force }
if (Test-Path $key) { throw "could not remove $key" }
Write-Host "[first-toast] state: AUMID key absent, data icon absent"

$tmp = Join-Path $env:TEMP 'win-toast-test.json'
[IO.File]::WriteAllText($tmp, '{"cwd":"' + ($Root -replace '\\', '\\\\') + '","message":"first toast before SessionStart","title":"win-toast test"}')
$t0 = Get-Date
cmd /c "type `"$tmp`" | powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$Root\scripts\notify.ps1`" -Event Notification"
Write-Host ("[first-toast] notify.ps1 exit={0} in {1}ms" -f $LASTEXITCODE, [int]((Get-Date) - $t0).TotalMilliseconds)
Remove-Item $tmp -Force -ErrorAction SilentlyContinue

$cur = Get-ItemProperty $key -ErrorAction SilentlyContinue
$name = if ($cur) { $cur.DisplayName } else { '<no key>' }
$ok = ($name -eq 'Claude Code') -and $cur.IconUri -and (Test-Path $cur.IconUri)
Write-Host "[first-toast] after toast: DisplayName='$name' IconUri='$($cur.IconUri)'"
if (Test-Path "$icon.bak") { if (Test-Path $icon) { Remove-Item "$icon.bak" -Force } else { Rename-Item "$icon.bak" $icon -Force } }

if ($ok) { Write-Host "[first-toast] PASS: identity registered before the toast was shown"; exit 0 }
Write-Host "[first-toast] FAIL: toast shown for an unregistered AUMID; Windows will show '$appId' as the sender until sign-out"
exit 1
