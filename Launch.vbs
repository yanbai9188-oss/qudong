Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

appDir = fso.GetParentFolderName(WScript.ScriptFullName)
ps1 = appDir & "\DriverBooster.ps1"

If Not fso.FileExists(ps1) Then
    MsgBox "Cannot find DriverBooster.ps1" & vbCrLf & vbCrLf & _
           "Please reinstall the application." & vbCrLf & _
           "Path: " & ps1, vbCritical, "Yanbai Driver - Launch Error"
    WScript.Quit 1
End If

' Launch PowerShell hidden; DriverBooster.ps1 hides the console via P/Invoke itself.
' -WindowStyle Hidden prevents a black flash on UAC-aware systems.
cmd = "powershell.exe -NoProfile -Sta -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & ps1 & """"
WshShell.CurrentDirectory = appDir
WshShell.Run cmd, 0, False

' Wait up to 15 seconds for startup.log to confirm the process started.
Dim waited : waited = 0
Dim interval : interval = 500
Dim maxWait : maxWait = 15000

userLogDir    = WshShell.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\Yanbai_Driver\Logs"
legacyLogDir  = WshShell.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\CIODIY_DriverBooster\Logs"
appLogDir     = appDir & "\Logs"
startupLog    = ""

' Declare loop variables outside the Do loop (VBScript requires Dim at script/procedure scope)
Dim candidates(2)
Dim i
Dim f

candidates(0) = userLogDir   & "\startup.log"
candidates(1) = legacyLogDir & "\startup.log"
candidates(2) = appLogDir    & "\startup.log"

Do While waited < maxWait
    WScript.Sleep interval
    waited = waited + interval

    For i = 0 To 2
        If fso.FileExists(candidates(i)) Then
            Set f = fso.GetFile(candidates(i))
            If DateDiff("s", f.DateLastModified, Now) <= 60 Then
                startupLog = candidates(i)
                Exit Do
            End If
        End If
    Next
Loop

If startupLog <> "" Then
    ' Started successfully - nothing to do
    WScript.Quit 0
End If

' Startup log was never written within 15 seconds.
Dim logDir : logDir = ""
If fso.FolderExists(userLogDir) Then
    logDir = userLogDir
ElseIf fso.FolderExists(appLogDir) Then
    logDir = appLogDir
End If

Dim msg
msg = "Yanbai Driver did not start within 15 seconds." & vbCrLf & vbCrLf & _
      "Possible causes:" & vbCrLf & _
      "  1. Antivirus software is blocking PowerShell scripts" & vbCrLf & _
      "  2. PowerShell 5.1 or later is not installed" & vbCrLf & _
      "  3. Script execution policy is restricted" & vbCrLf

If logDir <> "" Then
    msg = msg & vbCrLf & "Log folder: " & logDir
End If

Dim choice
choice = MsgBox(msg & vbCrLf & vbCrLf & "Click YES to open the log folder, NO to retry.", _
                vbYesNo + vbExclamation, "Yanbai Driver - Launch Error")

If choice = vbYes Then
    If logDir <> "" Then
        WshShell.Run "explorer.exe """ & logDir & """", 1, False
    Else
        MsgBox "No log folder found. The application may not have started at all.", _
               vbInformation, "Yanbai Driver"
    End If
ElseIf choice = vbNo Then
    ' Retry once
    WshShell.Run cmd, 0, False
End If
