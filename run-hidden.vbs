Set objShell = CreateObject("WScript.Shell")
objShell.Run "powershell.exe -NonInteractive -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName) & "\update-termius-localize.ps1""", 0, False
