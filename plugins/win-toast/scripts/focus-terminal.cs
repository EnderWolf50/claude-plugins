// win-toast: claude-focus:// protocol handler.
// Compiled once by register.ps1 (inbox .NET Framework csc.exe) into $CLAUDE_PLUGIN_DATA\claude-focus.exe.
// A WinExe has no console window, so nothing flashes when a toast is clicked.
//
// Usage: claude-focus.exe "claude-focus://focus?hwnd=<handle>&title=<url-encoded session title>"
//   1. bring the window <hwnd> to the foreground (restore if minimized)
//   2. if it is Windows Terminal, select the tab whose name contains <title>

using System;
using System.Diagnostics;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows.Automation;

static class Program
{
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll")] static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    const int SW_RESTORE = 9;
    const byte VK_MENU = 0x12;
    const uint KEYEVENTF_KEYUP = 2;

    [STAThread]
    static int Main(string[] args)
    {
        if (args.Length == 0) return 0;

        long hwndValue = 0;
        string title = "";
        Uri uri;
        if (Uri.TryCreate(args[0], UriKind.Absolute, out uri))
        {
            foreach (string pair in uri.Query.TrimStart('?').Split('&'))
            {
                int eq = pair.IndexOf('=');
                if (eq < 0) continue;
                string key = pair.Substring(0, eq);
                string val = Uri.UnescapeDataString(pair.Substring(eq + 1).Replace('+', ' '));
                if (key == "hwnd") long.TryParse(val, out hwndValue);
                else if (key == "title") title = val;
            }
        }

        IntPtr hwnd = new IntPtr(hwndValue);
        if (hwnd == IntPtr.Zero || !IsWindow(hwnd))
        {
            // recorded window is gone: fall back to any Windows Terminal window
            Process wt = Process.GetProcessesByName("WindowsTerminal")
                                .FirstOrDefault(p => p.MainWindowHandle != IntPtr.Zero);
            if (wt == null) return 0;
            hwnd = wt.MainWindowHandle;
        }

        if (IsIconic(hwnd)) ShowWindow(hwnd, SW_RESTORE);
        // tapping Alt releases the foreground lock so SetForegroundWindow is honored
        keybd_event(VK_MENU, 0, 0, UIntPtr.Zero);
        keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
        SetForegroundWindow(hwnd);

        if (title.Length == 0) return 0;

        try
        {
            AutomationElement root = AutomationElement.FromHandle(hwnd);
            AutomationElementCollection tabs = root.FindAll(TreeScope.Descendants,
                new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.TabItem));
            foreach (AutomationElement tab in tabs)
            {
                if (tab.Current.Name.IndexOf(title, StringComparison.OrdinalIgnoreCase) < 0) continue;
                ((SelectionItemPattern)tab.GetCurrentPattern(SelectionItemPattern.Pattern)).Select();
                break;
            }
        }
        catch { /* not a tabbed window (VS Code, conhost, ...) - focusing it was enough */ }
        return 0;
    }
}
