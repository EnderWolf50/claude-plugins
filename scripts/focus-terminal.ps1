# Protocol handler for claude-focus://  -> bring Windows Terminal to front and select the matching tab
# Invoked as: focus-terminal.ps1 "claude-focus://focus?hwnd=12345&title=<urlencoded>"
param([string]$Uri)

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Win32 {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
}
"@

$hwnd = [IntPtr]::Zero; $title = ""
try {
    $u = [Uri]$Uri
    $q = [System.Web.HttpUtility]::ParseQueryString($u.Query)
} catch {
    Add-Type -AssemblyName System.Web
    $u = [Uri]$Uri
    $q = [System.Web.HttpUtility]::ParseQueryString($u.Query)
}
if ($q["hwnd"])  { $hwnd  = [IntPtr][long]$q["hwnd"] }
if ($q["title"]) { $title = $q["title"] }

# fall back to any Windows Terminal window if the recorded one is gone
if ($hwnd -eq [IntPtr]::Zero -or -not [Win32]::IsWindow($hwnd)) {
    $wt = Get-Process WindowsTerminal -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
    if (-not $wt) { exit 0 }
    $hwnd = $wt.MainWindowHandle
}

# bring window to front (Alt tap releases the foreground lock if needed)
if ([Win32]::IsIconic($hwnd)) { [Win32]::ShowWindow($hwnd, 9) | Out-Null }   # SW_RESTORE
[Win32]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero); [Win32]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
[Win32]::SetForegroundWindow($hwnd) | Out-Null

if (-not $title) { exit 0 }

# select the tab whose name contains the session title
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$root = [System.Windows.Automation.AutomationElement]::FromHandle($hwnd)
$cond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::TabItem)
$tabs = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
foreach ($t in $tabs) {
    if ($t.Current.Name -like "*$title*") {
        try {
            $t.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
        } catch {}
        break
    }
}
