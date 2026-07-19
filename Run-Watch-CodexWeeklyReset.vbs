Option Explicit

Dim shell
Dim fileSystem
Dim scriptDirectory
Dim powerShellScript
Dim command

Set shell = CreateObject("WScript.Shell")
Set fileSystem = CreateObject("Scripting.FileSystemObject")

' このVBSファイルが置かれているフォルダを取得する
scriptDirectory = fileSystem.GetParentFolderName( _
    WScript.ScriptFullName _
)

' 同じフォルダにあるPowerShellスクリプトを指定する
powerShellScript = scriptDirectory & _
    "\Watch-CodexWeeklyReset.ps1"

' PowerShellスクリプトを通常モードで実行する
command = _
    "powershell.exe " & _
    "-NoProfile " & _
    "-ExecutionPolicy Bypass " & _
    "-File """ & powerShellScript & """"

' 第2引数の0でウィンドウを非表示にする
' 第3引数のFalseでPowerShellの終了を待たずにVBSを終了する
shell.Run command, 0, False

Set fileSystem = Nothing
Set shell = Nothing