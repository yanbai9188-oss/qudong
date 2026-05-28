$ErrorActionPreference = 'Stop'
$root    = Split-Path $PSScriptRoot -Parent
$version = '2.2.2'
$tag     = "v$version"
$exe     = Join-Path $root "Yanbai_Driver_Setup_Online_$version.exe"

if (-not (Test-Path $exe)) { throw "Installer not found: $exe" }

# Build UTF-8 release notes bytes to avoid encoding issues
function Utf8Bytes([string]$s) { [System.Text.Encoding]::UTF8.GetBytes($s) }

$notes = [System.Text.Encoding]::UTF8.GetString(
    (Utf8Bytes "## v$version — 稳定性修复") +
    (Utf8Bytes "`n`n### Bug 修复 (8项)") +
    (Utf8Bytes "`n- **DriverDownloader**: 修复 ``foreach (\$args)`` 覆盖 PS 自动变量导致 EXE 驱动安装失败的 bug") +
    (Utf8Bytes "`n- **ServiceWorker**: 修复任务文件 Move 失败时静默丢失 Job 的问题；改为写入 ``failed`` 结果") +
    (Utf8Bytes "`n- **ServiceWorker**: 修复单项下载/安装时进度条卡住问题（per-item OnProgress 现在实际更新 Set-JobStatus）") +
    (Utf8Bytes "`n- **JobQueue**: 修复 ``rollbackOnError``/``createRestorePoint``/``verifyInstall`` 选项未序列化到 Job JSON") +
    (Utf8Bytes "`n- **GuiWorkers**: 修复 ``\$result`` 为 null 时 ``.GetType()`` 抛出异常") +
    (Utf8Bytes "`n- **GuiPages**: 修复回滚面板 ``Get-TransactionSummaryForGui`` 返回 null 时的 NullReferenceException") +
    (Utf8Bytes "`n- **CatalogDownloader**: 修复 MSU 内层 CAB 解压 exit code 未检查，解压失败不报错的问题") +
    (Utf8Bytes "`n- **AppBootstrap/GuiState**: 修复硬编码版本号 ``1.8.0`` 未跟随主版本更新") +
    (Utf8Bytes "`n`n### 其他改进") +
    (Utf8Bytes "`n- ServiceWorker 现在在 Job JSON 中记录 ``rolledBack`` 和 ``txId`` 字段，GUI 可正确反映回滚状态") +
    (Utf8Bytes "`n- 修复备份失败被静默吞掉，现在会写入日志")
)

$tmpNotes = [System.IO.Path]::GetTempFileName()
[System.IO.File]::WriteAllText($tmpNotes, $notes, [System.Text.Encoding]::UTF8)

Write-Host "Creating GitHub release $tag ..."
gh release create $tag $exe `
    --title "Yanbai Driver $tag" `
    --notes-file $tmpNotes

Remove-Item $tmpNotes -Force -ErrorAction SilentlyContinue
Write-Host "Release $tag published."
