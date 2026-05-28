#define MyAppName "Yanbai驱动"
#define MyAppNameEn "Yanbai Driver"
#define MyAppDir "Yanbai_Driver"
#define MyAppVersion "2.2.2"
#define OutputSuffix "_Online"
#define MyAppPublisher "Yanbai"
#define MyAppLauncher "{sys}\wscript.exe"

[Setup]
AppId={{A7B3C9D1-8E2F-4A5B-9C0D-1E2F3A4B5C6D}
AppName={#MyAppName}
AppVerName={#MyAppName} {#MyAppVersion}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={commonpf64}\{#MyAppDir}
DefaultGroupName={#MyAppName}
UsePreviousAppDir=no
DisableProgramGroupPage=yes
OutputDir=..
OutputBaseFilename=Yanbai_Driver_Setup{#OutputSuffix}_{#MyAppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\ui\yanbai.ico
SetupIconFile=..\ui\yanbai.ico
ShowLanguageDialog=no
SetupMutex=YanbaiDriverSetup

[Languages]
Name: "chinesesimplified"; MessagesFile: "Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加选项:"; Flags: checkedonce

[Files]
Source: "staging\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{#MyAppLauncher}"; Parameters: "//Nologo ""{app}\Launch.vbs"""; WorkingDir: "{app}"; IconFilename: "{app}\ui\yanbai.ico"
Name: "{group}\卸载 {#MyAppName}"; Filename: "{uninstallexe}"; IconFilename: "{app}\ui\yanbai.ico"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{#MyAppLauncher}"; Parameters: "//Nologo ""{app}\Launch.vbs"""; Tasks: desktopicon; WorkingDir: "{app}"; IconFilename: "{app}\ui\yanbai.ico"

[Run]
; Register the SYSTEM-level background worker task (installer already runs as admin).
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\scripts\install-task.ps1"" -AppDir ""{app}"""; Flags: runhidden waituntilterminated; StatusMsg: "正在注册后台安装服务..."
; Launch the app
Filename: "{#MyAppLauncher}"; Parameters: "//Nologo ""{app}\Launch.vbs"""; Description: "启动 {#MyAppName}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; Stop and delete the scheduled task on uninstall
Filename: "{sys}\schtasks.exe"; Parameters: "/Delete /TN YanbaiDriverWorker /F"; Flags: runhidden; RunOnceId: "DelWorkerTask"

[Messages]
SetupAppTitle=安装 {#MyAppName}
SetupWindowTitle=安装 - {#MyAppName} {#MyAppVersion}
WelcomeLabel1=欢迎使用 {#MyAppName} 安装向导
WelcomeLabel2=此程序将安装 {#MyAppName} {#MyAppVersion} 到您的计算机。%n%n建议在安装前关闭其他程序，然后点击「下一步」继续。
FinishedLabel=安装程序已完成 {#MyAppName} 的安装。%n%n点击「完成」退出安装向导。
