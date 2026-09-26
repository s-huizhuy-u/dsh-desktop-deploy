# ============================================================================
#  DSH Desktop 专业部署包 - 卸载工具
#  Uninstall-DSH.ps1
# ----------------------------------------------------------------------------
#  编码要求：UTF-8 with BOM
# ----------------------------------------------------------------------------
#  用法示例：
#    .\Uninstall-DSH.ps1                交互式卸载（保留个人数据）
#    .\Uninstall-DSH.ps1 -Silent        静默卸载
#    .\Uninstall-DSH.ps1 -PurgeData     卸载并清除所有个人数据
# ============================================================================

[CmdletBinding()]
param(
    [string]$InstallPath,
    [switch]$Silent,
    [switch]$PurgeData,
    [switch]$KeepData,
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'

$common = Join-Path $PSScriptRoot 'Common.ps1'
if (-not (Test-Path $common)) {
    Write-Host '[致命错误] 缺少文件 scripts\Common.ps1，部署包不完整。' -ForegroundColor Red
    exit 1
}
. $common

if ($NoPause) { $Script:NoPause = $true }

Initialize-DeployLog -Tag 'uninstall' | Out-Null
Show-Banner

Write-Host '  卸载工具' -ForegroundColor White
Write-Host ''

# ============================================================================
#  1. 定位安装信息
# ============================================================================
$recordFile = Join-Path $env:LOCALAPPDATA 'DSH-Deploy\install-record.json'
$record = $null
if (Test-Path $recordFile) {
    try { $record = Get-Content $recordFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
}

if (-not $InstallPath) {
    if ($record -and $record.InstallPath) { $InstallPath = $record.InstallPath }
    else { $InstallPath = $Script:App.DefaultDir }
}

$exePath = Join-Path $InstallPath $Script:App.ExeName

Write-Head '检查安装状态'
Write-Note ('目标目录: ' + $InstallPath)

if (-not (Test-Path $InstallPath)) {
    Write-Alert '未找到安装目录，程序可能已经卸载'
    # 仍然尝试清理快捷方式与记录
    $orphan = $true
}
elseif (-not (Test-Path $exePath)) {
    Write-Alert '目录存在但未找到主程序，可能安装不完整'
    $orphan = $true
}
else {
    $orphan = $false
    $ver = Get-InstalledVersion -InstallDir $InstallPath
    Write-Ok ($Script:App.Name + ' 已安装')
    Write-KeyValue -Key '安装目录' -Value $InstallPath
    if ($ver) { Write-KeyValue -Key '程序版本' -Value $ver }
}

# ============================================================================
#  2. 用户数据说明与选择
# ============================================================================
$userDataDirs = @(
    (Join-Path $env:APPDATA 'dsh-desktop')
    (Join-Path $env:LOCALAPPDATA 'dsh-desktop')
    (Join-Path $env:USERPROFILE '.dsh')
)

$existingData = @()
foreach ($d in $userDataDirs) {
    if (Test-Path $d) {
        try {
            $sz = (Get-ChildItem $d -Recurse -Force -ErrorAction SilentlyContinue |
                   Measure-Object -Property Length -Sum).Sum
            $szMB = if ($sz) { [math]::Round($sz / 1MB, 1) } else { 0 }
        }
        catch { $szMB = 0 }
        $existingData += [PSCustomObject]@{ Path = $d; SizeMB = $szMB }
    }
}

$purge = $false
if ($existingData.Count -gt 0) {
    Write-Head '个人数据'
    Write-Host '  检测到以下用户数据（包含配置、会话历史、API 密钥等）:' -ForegroundColor Yellow
    foreach ($d in $existingData) {
        Write-Host ('    · ' + $d.Path + '   (' + $d.SizeMB + ' MB)') -ForegroundColor Gray
    }
    Write-Host ''

    if ($PurgeData) {
        $purge = $true
        Write-Alert '按参数要求：将一并删除上述个人数据'
    }
    elseif ($KeepData) {
        $purge = $false
        Write-Note '按参数要求：保留个人数据'
    }
    elseif ($Silent) {
        $purge = $false
        Write-Note '静默模式：默认保留个人数据（如需清除请加 -PurgeData）'
    }
    else {
        Write-Host '  请选择:' -ForegroundColor White
        Write-Host '    [1] 保留个人数据（推荐，重装后可继续使用原配置）' -ForegroundColor Gray
        Write-Host '    [2] 彻底清除所有个人数据（不可恢复）' -ForegroundColor Gray
        Write-Host ''
        $c = Read-Host '  请输入选项 (默认 1)'
        if ($c -eq '2') {
            Write-Host ''
            Write-Host '  ⚠ 警告：此操作将永久删除配置、会话记录与已保存的 API 密钥，且无法恢复。' -ForegroundColor Red
            $confirm = Read-Host '  请输入 DELETE 以确认'
            if ($confirm -ceq 'DELETE') { $purge = $true }
            else { Write-Note '确认失败，将保留个人数据' }
        }
    }
}

# ============================================================================
#  3. 确认卸载
# ============================================================================
if (-not $Silent -and -not $orphan) {
    Write-Host ''
    $ans = Read-Host '  确认卸载 DSH Desktop? (Y/N)'
    if ($ans -ne 'Y' -and $ans -ne 'y') {
        Write-Note '已取消，未做任何修改'
        Write-Log -Message '用户取消卸载' -Level 'INFO'
        Complete-Deploy -Code $Script:ExitCode.UserCancelled
    }
}

# ============================================================================
#  4. 关闭运行中的程序
# ============================================================================
Write-Head '关闭运行中的程序'

$procName = [System.IO.Path]::GetFileNameWithoutExtension($Script:App.ExeName)
$running = Get-Process -Name $procName -ErrorAction SilentlyContinue
if ($running) {
    Write-Alert ('检测到 ' + $running.Count + ' 个运行中的进程，正在关闭...')
    try {
        $running | Stop-Process -Force -ErrorAction Stop
        Start-Sleep -Seconds 2
        Write-Ok '已关闭'
    }
    catch {
        Write-Alert '部分进程无法关闭，卸载可能不完整'
        Write-Log -Message ('关闭进程失败: ' + $_.Exception.Message) -Level 'WARN'
    }
}
else {
    Write-Ok '没有运行中的实例'
}

# ============================================================================
#  5. 执行卸载
# ============================================================================
if (-not $orphan) {
    Write-Head '执行卸载'

    $uninstaller = Join-Path $InstallPath $Script:App.UninstallerName
    $uninstalled = $false

    if (Test-Path $uninstaller) {
        Write-Note '调用官方卸载程序（静默模式）'
        try {
            $p = Start-Process -FilePath $uninstaller -ArgumentList '/S' -PassThru -Wait -ErrorAction Stop
            Write-Log -Message ('卸载程序退出码: ' + $p.ExitCode) -Level 'INFO'
            # NSIS 卸载器会把自己复制到临时目录后删除原目录，需等待其收尾
            Start-Sleep -Seconds 3
            $uninstalled = $true
            Write-Ok '官方卸载程序执行完毕'
        }
        catch {
            Write-Alert ('官方卸载程序执行失败: ' + $_.Exception.Message)
        }
    }
    else {
        Write-Alert ('未找到官方卸载程序: ' + $uninstaller)
    }

    # 兜底：目录仍存在则强制移除
    if (Test-Path $InstallPath) {
        Write-Note '清理残留文件...'
        try {
            Remove-Item -Path $InstallPath -Recurse -Force -ErrorAction Stop
            Write-Ok '残留文件已清理'
        }
        catch {
            Write-Alert ('部分文件无法删除（可能被占用）: ' + $_.Exception.Message)
            Write-Note '请重启电脑后手动删除该目录'
        }
    }
}
else {
    Write-Head '执行卸载'
    if (Test-Path $InstallPath) {
        try {
            Remove-Item -Path $InstallPath -Recurse -Force -ErrorAction Stop
            Write-Ok '已清理残留目录'
        }
        catch {
            Write-Alert ('目录清理失败: ' + $_.Exception.Message)
        }
    }
}

# ============================================================================
#  6. 清理快捷方式
# ============================================================================
Write-Head '清理快捷方式'

$shortcuts = @(
    (Join-Path (Get-DesktopPath) ($Script:App.Name + '.lnk'))
    (Join-Path (Join-Path (Get-StartMenuPath) $Script:App.Name) ($Script:App.Name + '.lnk'))
)

foreach ($s in $shortcuts) {
    if (Test-Path $s) {
        try {
            Remove-Item $s -Force -ErrorAction Stop
            Write-Ok ('已删除 ' + $s)
        }
        catch {
            Write-Alert ('删除失败 ' + $s)
        }
    }
}

# 清理空的开始菜单文件夹
$startFolder = Join-Path (Get-StartMenuPath) $Script:App.Name
if (Test-Path $startFolder) {
    try {
        $left = Get-ChildItem $startFolder -Force -ErrorAction SilentlyContinue
        if (-not $left) {
            Remove-Item $startFolder -Force -ErrorAction Stop
            Write-Ok '已删除空的开始菜单文件夹'
        }
    }
    catch { }
}

# ============================================================================
#  7. 清理个人数据
# ============================================================================
if ($purge -and $existingData.Count -gt 0) {
    Write-Head '清除个人数据'
    foreach ($d in $existingData) {
        try {
            Remove-Item -Path $d.Path -Recurse -Force -ErrorAction Stop
            Write-Ok ('已删除 ' + $d.Path)
        }
        catch {
            Write-Alert ('删除失败 ' + $d.Path + ' — ' + $_.Exception.Message)
        }
    }
}
elseif ($existingData.Count -gt 0) {
    Write-Head '个人数据已保留'
    foreach ($d in $existingData) {
        Write-Note $d.Path
    }
    Write-Host '  如需彻底清除，请重新运行: .\Uninstall-DSH.ps1 -PurgeData' -ForegroundColor DarkGray
}

# ============================================================================
#  8. 清理安装记录
# ============================================================================
try {
    if (Test-Path $recordFile) {
        Remove-Item $recordFile -Force -ErrorAction Stop
        Write-Log -Message '已删除安装记录' -Level 'OK'
    }
}
catch { }

# ============================================================================
#  完成
# ============================================================================
Show-Box -Lines @('卸 载 完 成') -Color Green

if ($purge) {
    Write-Note '程序与个人数据均已清除'
}
else {
    Write-Note '程序已卸载，个人数据已保留'
}

$logPath = Get-LogPath
if ($logPath) { Write-Host ('  诊断日志: ' + $logPath) -ForegroundColor DarkGray }
Write-Host ''

Complete-Deploy -Code $Script:ExitCode.Success
