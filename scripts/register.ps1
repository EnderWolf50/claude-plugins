# One-time (idempotent) setup for win-toast. Runs on every SessionStart (async); only writes when
# something is missing or stale, so the steady-state cost is a few registry reads.
#   - copies the icon to a stable data dir (the plugin root changes on every update)
#   - compiles focus-terminal.cs -> claude-focus.exe with the inbox .NET Framework compiler
#     (a WinExe, so clicking a toast never flashes a console window)
#   - registers the "Claude Code" AppUserModelId so toasts show the right name/icon
#     (Windows caches the resolved icon per AUMID for the whole logon session: if you change the
#      icon, sign out or reboot before expecting to see it)
#   - registers the claude-focus:// protocol -> claude-focus.exe
param([switch]$Quiet, [switch]$Force)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$data = if ($env:CLAUDE_PLUGIN_DATA) { $env:CLAUDE_PLUGIN_DATA } else { Join-Path $HOME '.claude\win-toast' }
if (-not (Test-Path $data)) { New-Item -ItemType Directory -Path $data -Force | Out-Null }

$appId    = 'ClaudeCode.WinToast'
$appKey   = "HKCU:\Software\Classes\AppUserModelId\$appId"
$proto    = 'HKCU:\Software\Classes\claude-focus'
$iconSrc  = Join-Path $root 'assets\claude-code.ico'
$iconDst  = Join-Path $data 'claude-code.ico'
$csSrc    = Join-Path $root 'scripts\focus-terminal.cs'
$exe      = Join-Path $data 'claude-focus.exe'
$hashFile = Join-Path $data 'claude-focus.sha256'
$cmd      = "`"$exe`" `"%1`""

$changed = @()

# icon
if ($Force -or -not (Test-Path $iconDst) -or (Get-Item $iconSrc).Length -ne (Get-Item $iconDst).Length) {
    Copy-Item $iconSrc $iconDst -Force
    $changed += 'icon'
}

# protocol handler exe: rebuild when the source changes
$srcHash = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash([System.IO.File]::ReadAllBytes($csSrc))) -replace '-', ''
$oldHash = if (Test-Path $hashFile) { (Get-Content $hashFile -Raw).Trim() } else { '' }
if ($Force -or -not (Test-Path $exe) -or $srcHash -ne $oldHash) {
    $fw  = [System.Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()
    $csc = Join-Path $fw 'csc.exe'
    if (-not (Test-Path $csc)) { throw "win-toast: csc.exe not found in $fw" }
    # UIAutomation assemblies live in the GAC; ask the runtime where they are
    $refs = @('UIAutomationClient', 'UIAutomationTypes', 'WindowsBase') | ForEach-Object {
        '/r:' + [System.Reflection.Assembly]::Load("$_, Version=4.0.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35").Location
    }
    $tmp = "$exe.tmp"
    $out = & $csc /nologo /target:winexe /optimize+ /platform:anycpu "/out:$tmp" @refs $csSrc 2>&1
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tmp)) { throw "win-toast: compile failed`n$out" }
    Move-Item $tmp $exe -Force
    Set-Content -Path $hashFile -Value $srcHash -NoNewline
    $changed += 'exe'
}

# toast sender identity
$cur = Get-ItemProperty -Path $appKey -ErrorAction SilentlyContinue
if ($Force -or -not $cur -or $cur.DisplayName -ne 'Claude Code' -or $cur.IconUri -ne $iconDst) {
    New-Item -Path $appKey -Force | Out-Null
    New-ItemProperty -Path $appKey -Name DisplayName -Value 'Claude Code' -PropertyType ExpandString -Force | Out-Null
    New-ItemProperty -Path $appKey -Name IconUri -Value $iconDst -PropertyType ExpandString -Force | Out-Null
    New-ItemProperty -Path $appKey -Name IconBackgroundColor -Value 'FFD97757' -PropertyType String -Force | Out-Null
    $changed += 'app-id'
}
# pre-1.2 installs used a different AUMID; drop it so it does not linger in notification settings
$legacy = 'HKCU:\Software\Classes\AppUserModelId\Anthropic.ClaudeCode'
if (Test-Path $legacy) { Remove-Item -Path $legacy -Recurse -Force; $changed += 'legacy-app-id' }

# claude-focus:// protocol
$curCmd = (Get-ItemProperty -Path "$proto\shell\open\command" -ErrorAction SilentlyContinue).'(default)'
if ($Force -or $curCmd -ne $cmd) {
    New-Item -Path "$proto\shell\open\command" -Force | Out-Null
    Set-ItemProperty -Path $proto -Name '(default)' -Value 'URL:Claude Code focus'
    Set-ItemProperty -Path $proto -Name 'URL Protocol' -Value ''
    Set-ItemProperty -Path "$proto\shell\open\command" -Name '(default)' -Value $cmd
    $changed += 'protocol'
}

if (-not $Quiet) {
    if ($changed.Count) { Write-Host "win-toast: registered ($($changed -join ', '))" }
    else { Write-Host "win-toast: already up to date" }
    Write-Host "  icon:     $iconDst"
    Write-Host "  handler:  $exe"
    Write-Host "  protocol: $cmd"
}
