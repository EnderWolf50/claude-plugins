# win-toast: Claude Code hook -> Windows toast notification
# Reads the hook JSON from stdin. Usage: notify.ps1 -Event Notification|Stop
# The "Claude Code" app identity and claude-focus:// protocol are registered by register.ps1
param([string]$Event = "Notification")

$appId = 'Anthropic.ClaudeCode'
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
$raw   = [Console]::In.ReadToEnd()
$title = "Claude Code"
$body  = "Task finished"
$project = ""

function Get-TerminalHwnd {
    # walk up from this hook process to the first ancestor that owns a top-level window
    # (WindowsTerminal.exe, Code.exe, ...). That is the window a toast click should bring back.
    $all = @{}
    foreach ($p in Get-CimInstance Win32_Process -Property ProcessId,ParentProcessId,Name) { $all[[int]$p.ProcessId] = $p }
    $id = $PID; $seen = 0
    while ($all.ContainsKey($id) -and $seen -lt 20) {
        $h = (Get-Process -Id $id -ErrorAction SilentlyContinue).MainWindowHandle
        if ($h -and $h -ne 0) { return [long]$h }
        $id = [int]$all[$id].ParentProcessId; $seen++
    }
    return 0
}

function Get-SessionTitle([string]$transcript) {
    # /rename writes custom-title; otherwise Claude Code auto-generates ai-title
    if (-not $transcript) { return $null }
    $p = $transcript -replace '^~', $HOME
    if (-not (Test-Path $p)) { return $null }
    $custom = $null; $ai = $null
    foreach ($line in [System.IO.File]::ReadLines($p)) {
        if ($line.StartsWith('{"type":"custom-title"'))   { $custom = $line }
        elseif ($line.StartsWith('{"type":"ai-title"'))   { $ai = $line }
    }
    $pick = if ($custom) { $custom } else { $ai }
    if (-not $pick) { return $null }
    try {
        $o = $pick | ConvertFrom-Json
        if ($o.customTitle) { return $o.customTitle }
        if ($o.aiTitle)     { return $o.aiTitle }
    } catch {}
    return $null
}

$sessionTitle = $null
try {
    $j = $raw | ConvertFrom-Json
    if ($j.cwd) { $project = Split-Path -Leaf $j.cwd }
    $sessionTitle = Get-SessionTitle $j.transcript_path

    if ($Event -eq "Stop") {
        $title = if ($sessionTitle) { $sessionTitle } else { "Claude Code" }
        $msg = [string]$j.last_assistant_message
        if ($msg) {
            # collapse markdown/whitespace into a short preview
            $msg = $msg -replace '```[\s\S]*?```', '[code]'
            $msg = $msg -replace '[#*_`>]', ''
            $msg = ($msg -replace '\s+', ' ').Trim()
            if ($msg.Length -gt 180) { $msg = $msg.Substring(0, 180) + "..." }
            $body = $msg
        } else {
            $body = "Claude has finished and is waiting for you"
        }
    } else {
        $body = if ($j.message) { $j.message } else { "Needs your attention" }
        if ($j.title) { $title = $j.title }
    }
} catch {}

[void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
[void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]

$esc = [System.Security.SecurityElement]::Escape
$attr = if ($project) { "<text placement=`"attribution`">$($esc.Invoke($project))</text>" } else { "" }
# click -> claude-focus:// -> claude-focus.exe (built from focus-terminal.cs) brings this window + tab to front
$launch = ""
try {
    Add-Type -AssemblyName System.Web
    $hwnd = Get-TerminalHwnd
    $q = "hwnd=$hwnd"
    if ($sessionTitle) { $q += "&title=" + [System.Web.HttpUtility]::UrlEncode($sessionTitle) }
    $launch = " activationType=`"protocol`" launch=`"$($esc.Invoke("claude-focus://focus?$q"))`""
} catch {}
$xml = @"
<toast$launch>
  <visual>
    <binding template="ToastGeneric">
      <text>$($esc.Invoke($title))</text>
      <text>$($esc.Invoke($body))</text>
      $attr
    </binding>
  </visual>
  <audio src="ms-winsoundevent:Notification.Default" />
</toast>
"@

$doc = New-Object Windows.Data.Xml.Dom.XmlDocument
$doc.LoadXml($xml)
$toast = New-Object Windows.UI.Notifications.ToastNotification $doc
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
