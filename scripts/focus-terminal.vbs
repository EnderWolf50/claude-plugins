' Hidden launcher for the claude-focus:// protocol so no console window flashes on click.
' Runs focus-terminal.ps1 from the same directory as this file.
Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
uri = ""
If WScript.Arguments.Count > 0 Then uri = WScript.Arguments(0)
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & dir & "\focus-terminal.ps1"" """ & uri & """", 0, False
