# One-time (idempotent) setup for win-toast:
#   - copies the icon to a stable data dir (plugin root changes on every update)
#   - registers the "Claude Code" AppUserModelId so toasts show the right name/icon
#   - registers the claude-focus:// protocol so clicking a toast focuses the terminal
# Runs on every SessionStart (async, ~200ms); only writes when something is missing or stale.
param([switch]$Quiet, [switch]$Force)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$data = if ($env:CLAUDE_PLUGIN_DATA) { $env:CLAUDE_PLUGIN_DATA } else { Join-Path $HOME '.claude\win-toast' }
if (-not (Test-Path $data)) { New-Item -ItemType Directory -Path $data -Force | Out-Null }

$appId   = 'Anthropic.ClaudeCode'
$appKey  = "HKCU:\Software\Classes\AppUserModelId\$appId"
$proto   = 'HKCU:\Software\Classes\claude-focus'
$iconSrc = Join-Path $root 'assets\claude-code.png'
$iconDst = Join-Path $data 'claude-code.png'
$vbs     = Join-Path $root 'scripts\focus-terminal.vbs'
$cmd     = "wscript.exe `"$vbs`" `"%1`""

$changed = @()

if ($Force -or -not (Test-Path $iconDst) -or (Get-Item $iconSrc).Length -ne (Get-Item $iconDst).Length) {
    Copy-Item $iconSrc $iconDst -Force
    $changed += 'icon'
}

$cur = Get-ItemProperty -Path $appKey -ErrorAction SilentlyContinue
if ($Force -or -not $cur -or $cur.DisplayName -ne 'Claude Code' -or $cur.IconUri -ne $iconDst) {
    New-Item -Path $appKey -Force | Out-Null
    Set-ItemProperty -Path $appKey -Name DisplayName -Value 'Claude Code'
    Set-ItemProperty -Path $appKey -Name IconUri -Value $iconDst
    Set-ItemProperty -Path $appKey -Name IconBackgroundColor -Value 'FFD97757'
    $changed += 'app-id'
}

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
    Write-Host "  protocol: $cmd"
}
