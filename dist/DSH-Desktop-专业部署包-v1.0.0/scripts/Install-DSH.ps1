# ============================================================================
#  DSH Desktop 专业部署包 - 安装引擎
#  Install-DSH.ps1
# ----------------------------------------------------------------------------
#  编码要求：UTF-8 with BOM
# ----------------------------------------------------------------------------
#  用法示例：
#    .\Install-DSH.ps1                      交互式安装
#    .\Install-DSH.ps1 -Silent              静默安装（企业批量）
#    .\Install-DSH.ps1 -Offline             使用随包安装文件（离线部署）
#    .\Install-DSH.ps1 -InstallPath "D:\App\DSH Desktop"
#    .\Install-DSH.ps1 -Force               强制重新安装
# ============================================================================

[CmdletBinding()]
param(
    [string]$InstallPath,
    [switch]$Silent,
    [switch]$Force,
    [switch]$Offline,
    [switch]$SkipRequirementCheck,
    [switch]$NoLaunch,
    [switch]$NoPause,
    # 显式允许强制关闭正在运行的程序。
    # 默认拒绝：静默强杀程序可能让用户丢失未保存的会话内容，
    # 商业部署必须以数据安全优先，由部署方显式授权。
    [switch]$ForceClose,
    [string]$DownloadUrl
)

$ErrorActionPreference = 'Stop'

# --- 加载公共库 ---
$common = Join-Path $PSScriptRoot 'Common.ps1'
if (-not (Test-Path $common)) {
    Write-Host '[致命错误] 缺少文件 scripts\Common.ps1，部署包不完整。' -ForegroundColor Red
    Write-Host '请重新解压完整压缩包后再运行。' -ForegroundColor Yellow
    exit 1
}
. $common

# BAT 启动器接管暂停行为
if ($NoPause) { $Script:NoPause = $true }

# 未指定安装目录时使用默认目录
if (-not $InstallPath) { $InstallPath = $Script:App.DefaultDir }

$totalSteps = 6
$step = 0

function Show-StepHeader {
    param([string]$Title)
    $Script:step++
    Write-Host ''
    Write-Host ('  【' + $Script:step + '/' + $totalSteps + '】' + $Title) -ForegroundColor White
    Write-Log -Message ('步骤 ' + $Script:step + '/' + $totalSteps + '：' + $Title) -Level 'STEP'
}

# ============================================================================
#  启动
# ============================================================================
Initialize-DeployLog -Tag 'install' | Out-Null
Show-Banner

if ($Silent) {
    Write-Note '运行模式：静默安装（无交互）'
}

$Script:startTime = Get-Date

# ============================================================================
#  步骤 1 / 6 —— 系统环境检测
# ============================================================================
Show-StepHeader '系统环境检测'

if ($SkipRequirementCheck) {
    Write-Alert '已按参数要求跳过系统检测（-SkipRequirementCheck）'
}
else {
    $check = Test-SystemRequirements

    if ($check.Warnings.Count -gt 0) {
        Write-Host ''
        Write-Host '  以下项目不影响安装，但建议关注:' -ForegroundColor Yellow
        foreach ($w in $check.Warnings) { Write-Host ('    · ' + $w) -ForegroundColor DarkYellow }
    }

    if (-not $check.Passed) {
        Write-Host ''
        Write-Host '  以下条件不满足，无法继续安装:' -ForegroundColor Red
        foreach ($f in $check.Failures) { Write-Host ('    × ' + $f) -ForegroundColor Red }
        Stop-Deploy -Reason '系统环境不满足安装要求' `
                    -Hint '请对照 docs\03-部署手册.md 的「系统要求」章节处理后重试' `
                    -Code $Script:ExitCode.RequirementFail -NoPause:$Silent
    }
    Write-Ok '系统环境满足安装要求'
}

# ============================================================================
#  步骤 2 / 6 —— 安装状态检查
# ============================================================================
Show-StepHeader '安装状态检查'

$existingVersion = Get-InstalledVersion -InstallDir $InstallPath
$isUpgrade = $false

if ($existingVersion) {
    Write-Alert ('检测到已安装 ' + $Script:App.Name + '，版本 ' + $existingVersion)
    Write-Note  ('安装目录: ' + $InstallPath)

    if ($Force -or $Silent) {
        Write-Note '按参数要求执行覆盖安装'
        $isUpgrade = $true
    }
    else {
        Write-Host ''
        Write-Host '  请选择操作:' -ForegroundColor White
        Write-Host '    [1] 覆盖安装 / 升级到最新版（推荐）' -ForegroundColor Gray
        Write-Host '    [2] 保留现状，退出安装' -ForegroundColor Gray
        Write-Host ''
        $choice = Read-Host '  请输入选项 (默认 1)'
        if ($choice -eq '2') {
            Write-Note '用户选择退出，未做任何修改'
            Write-Log -Message '用户主动取消安装' -Level 'INFO'
            Stop-Deploy -Reason '用户取消安装' -Hint '如需继续，请重新运行安装程序' `
                        -Code $Script:ExitCode.UserCancelled
        }
        $isUpgrade = $true
    }

    # 运行中进程的检查统一在下一步骤处理
}
else {
    Write-Ok ('未检测到已安装的 ' + $Script:App.Name + '，将执行全新安装')
    Write-Note ('计划安装目录: ' + $InstallPath)
}

# ---------------------------------------------------------------------------
#  运行中进程检查（无论全新安装还是覆盖安装都必须检查）
# ---------------------------------------------------------------------------
Write-Host ''
$procName = [System.IO.Path]::GetFileNameWithoutExtension($Script:App.ExeName)
$running  = Get-Process -Name $procName -ErrorAction SilentlyContinue

if ($running) {
    Write-Alert ($Script:App.Name + ' 正在运行中（' + $running.Count + ' 个进程）')
    Write-Note  '安装过程需要替换程序文件，必须先关闭该程序'

    if ($ForceClose) {
        # 部署方已显式授权强制关闭
        Write-Alert '已指定 -ForceClose，将强制关闭该程序'
        Write-Note  '提示：未保存的会话内容可能丢失'
        try {
            $running | Stop-Process -Force -ErrorAction Stop
            Start-Sleep -Seconds 2
            Write-Ok '已关闭正在运行的程序'
            Write-Log -Message '已强制关闭运行中的程序（ForceClose）' -Level 'WARN'
        }
        catch {
            Stop-Deploy -Reason '无法关闭正在运行的程序' `
                        -Hint '请手动退出 DSH Desktop 后重新运行安装程序' `
                        -Code $Script:ExitCode.InstallFail -NoPause:$Silent
        }
    }
    elseif ($Silent) {
        # 静默且未授权强制关闭 —— 拒绝执行，交由部署方决定
        Stop-Deploy -Reason ($Script:App.Name + ' 正在运行，静默模式下不会强制关闭') `
                    -Hint '请先关闭该程序；如确认可强制关闭，请加 -ForceClose 参数重新执行' `
                    -Code $Script:ExitCode.InstallFail -NoPause
    }
    else {
        Write-Host ''
        Write-Host '  请选择:' -ForegroundColor White
        Write-Host '    [1] 自动关闭该程序并继续安装（未保存的内容可能丢失）' -ForegroundColor Gray
        Write-Host '    [2] 我自己手动关闭，然后重新运行安装程序（更安全）' -ForegroundColor Gray
        Write-Host ''
        $ans = Read-Host '  请输入选项 (默认 2)'
        if ($ans -eq '1') {
            try {
                $running | Stop-Process -Force -ErrorAction Stop
                Start-Sleep -Seconds 2
                Write-Ok '已关闭正在运行的程序'
            }
            catch {
                Stop-Deploy -Reason '无法关闭正在运行的程序' `
                            -Hint '请手动退出 DSH Desktop 后重新运行安装程序' `
                            -Code $Script:ExitCode.InstallFail
            }
        }
        else {
            Stop-Deploy -Reason '需要先关闭正在运行的程序' `
                        -Hint '关闭 DSH Desktop 后，重新双击 "1-一键安装.bat" 即可' `
                        -Code $Script:ExitCode.UserCancelled
        }
    }
}
else {
    Write-Ok '当前没有正在运行的实例，可以安全安装'
}

# ============================================================================
#  步骤 3 / 6 —— 获取安装文件
# ============================================================================
Show-StepHeader '获取安装文件'

$tempDir       = Join-Path $env:TEMP ('dsh-deploy-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$installerPath = Join-Path $tempDir $Script:InstallerFileName
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

Write-Note ('临时目录: ' + $tempDir)

$usedOffline = $false
$localCandidates = @(
    (Join-Path $Script:ProductRoot $Script:InstallerFileName)
    (Join-Path $Script:ProductRoot ('packages\' + $Script:InstallerFileName))
    (Join-Path $Script:ScriptsDir $Script:InstallerFileName)
)
$localInstaller = $null
foreach ($c in $localCandidates) {
    if (Test-Path $c) { $localInstaller = $c; break }
}

if ($Offline) {
    if (-not $localInstaller) {
        Stop-Deploy -Reason '离线模式未找到安装文件' `
                    -Hint ('请把 ' + $Script:InstallerFileName + ' 放到部署包根目录后重试') `
                    -Code $Script:ExitCode.DownloadFail -NoPause:$Silent
    }
    Write-Ok ('离线模式：使用随包安装文件 ' + $localInstaller)
    Copy-Item $localInstaller $installerPath -Force
    $usedOffline = $true
}
elseif ($localInstaller) {
    Write-Ok ('发现随包安装文件，直接使用（无需下载）')
    Write-Note $localInstaller
    Copy-Item $localInstaller $installerPath -Force
    $usedOffline = $true
}
else {
    Write-Note '未发现随包安装文件，将从官方站点下载'

    $urls = @()
    if ($DownloadUrl) { $urls += $DownloadUrl }
    $urls += $Script:DownloadMirrors

    Write-Note ('共 ' + $urls.Count + ' 个下载源，失败自动切换，单个源最多重试 3 次')
    Write-Host ''

    $downloaded = Invoke-ResilientDownload -Urls $urls -Destination $installerPath -MaxRetries 3

    if (-not $downloaded) {
        Stop-Deploy -Reason '所有下载源均失败' `
                    -Hint '请检查网络/代理设置，或访问官网手动下载后改用 -Offline 离线安装' `
                    -Code $Script:ExitCode.DownloadFail -NoPause:$Silent
    }
}

# --- 文件完整性校验 ---
Write-Host ''
Write-Note '校验安装文件完整性...'

if (-not (Test-InstallerFile -Path $installerPath)) {
    Stop-Deploy -Reason '安装文件校验失败（文件损坏或下载不完整）' `
                -Hint '请删除后重新下载，或从官网重新获取安装包' `
                -Code $Script:ExitCode.DownloadFail -NoPause:$Silent
}

$fi      = Get-Item $installerPath
$sizeMB  = [math]::Round($fi.Length / 1MB, 1)
$sha256  = Get-FileHashSafe -Path $installerPath

Write-Ok ('文件校验通过：' + $sizeMB + ' MB')
if ($sha256) { Write-Note ('SHA256: ' + $sha256) }

# --- 数字签名信息（仅展示，不强制） ---
try {
    $sig = Get-AuthenticodeSignature -FilePath $installerPath -ErrorAction Stop
    if ($sig.Status -eq 'Valid') {
        Write-Ok ('数字签名有效：' + $sig.SignerCertificate.Subject)
    }
    else {
        Write-Alert ('数字签名状态: ' + $sig.Status + '（不影响安装，仅作提示）')
    }
}
catch {
    Write-Log -Message '数字签名检查不可用' -Level 'WARN'
}

# ============================================================================
#  步骤 4 / 6 —— 执行安装
# ============================================================================
Show-StepHeader '执行安装'

$installArgs = @('/S')
if ($InstallPath -ne $Script:App.DefaultDir) {
    # electron-builder / NSIS 约定：/D 必须位于最后且不带引号
    $installArgs += ('/D=' + $InstallPath)
}

Write-Note ('安装参数: ' + ($installArgs -join ' '))
Write-Note ('目标目录: ' + $InstallPath)

if (-not (Test-IsAdministrator)) {
    Write-Note '以当前用户身份安装（安装到用户目录，无需管理员权限）'
}

Write-Host ''
Write-Host '  正在安装，请勿关闭本窗口...' -ForegroundColor Yellow
Write-Host ''

$installOk = $false
$exitCode  = -1
$installStarted = Get-Date

try {
    $proc = Start-Process -FilePath $installerPath `
                          -ArgumentList $installArgs `
                          -PassThru -Wait -ErrorAction Stop
    $exitCode = $proc.ExitCode
    Write-Log -Message ('安装程序退出码: ' + $exitCode) -Level 'INFO'
    $installOk = ($exitCode -eq 0 -or $exitCode -eq 3010 -or $exitCode -eq 1641)
}
catch {
    Write-Log -Message ('启动安装程序异常: ' + $_.Exception.Message) -Level 'ERROR'
    $installOk = $false
}

if (-not $installOk) {
    $hint = '请以管理员身份重新运行；若问题依旧，请查看 docs\06-故障排查.md'
    if ($exitCode -eq 2)  { $hint = '安装程序被中断，请关闭杀毒软件后重试' }
    if ($exitCode -eq 5)  { $hint = '安装程序拒绝访问，请右键以管理员身份运行' }
    if ($exitCode -eq 1603) { $hint = '安装被系统策略阻止，请检查组策略或联系 IT' }

    if ($exitCode -ge 0) {
        Stop-Deploy -Reason ('安装程序返回错误码 ' + $exitCode) -Hint $hint `
                    -Code $Script:ExitCode.InstallFail -NoPause:$Silent
    }
    else {
        Stop-Deploy -Reason '安装程序未能启动' -Hint $hint `
                    -Code $Script:ExitCode.InstallFail -NoPause:$Silent
    }
}

if ($exitCode -eq 3010 -or $exitCode -eq 1641) {
    Write-Alert '安装完成，但系统提示需要重启后完全生效'
}

Write-Ok '安装程序执行完毕'

# ============================================================================
#  步骤 5 / 6 —— 安装结果验证
# ============================================================================
Show-StepHeader '安装结果验证'

$installedExe     = Join-Path $InstallPath $Script:App.ExeName
$installedVersion = $null
$verified         = $false

# NSIS 有极小概率把程序装到默认目录，这里做兜底探测
if (-not (Test-Path $installedExe)) {
    $alt = Join-Path $Script:App.DefaultDir $Script:App.ExeName
    if (Test-Path $alt) {
        Write-Note '安装目录与预期不一致，已定位到实际目录'
        $InstallPath  = $Script:App.DefaultDir
        $installedExe = $alt
    }
}

if (Test-Path $installedExe) {
    $verified = $true
    $installedVersion = Get-InstalledVersion -InstallDir $InstallPath
    Write-Ok ($Script:App.Name + ' 主程序已就位')
    Write-KeyValue -Key '安装目录' -Value $InstallPath
    if ($installedVersion) { Write-KeyValue -Key '程序版本' -Value $installedVersion -Color Green }

    # --- 时间戳佐证 ---
    # 安装程序返回成功、但主程序文件时间戳早于本次安装开始时间，
    # 说明安装器实际没有替换文件（例如被安全软件静默拦截）。
    # 这里只提示不判定失败：合法的"已是最新版本"场景也不会更新文件时间戳。
    try {
        $exeTime = (Get-Item $installedExe).LastWriteTime
        Write-Log -Message ('主程序时间戳: ' + $exeTime.ToString('yyyy-MM-dd HH:mm:ss')) -Level 'INFO'
        if ($exeTime -lt $installStarted.AddMinutes(-1)) {
            Write-Alert '主程序文件时间戳早于本次安装时间，安装器可能未真正替换文件'
            Write-Note  '若程序可正常启动则无需处理；否则请查看 docs\06-故障排查.md'
        }
        else {
            Write-Ok '主程序文件已更新'
        }
    }
    catch {
        Write-Log -Message '无法读取主程序时间戳' -Level 'WARN'
    }

    # --- 创建桌面快捷方式 ---
    $desktopLnk = Join-Path (Get-DesktopPath) ($Script:App.Name + '.lnk')
    if (New-AppShortcut -ShortcutPath $desktopLnk -TargetPath $installedExe `
                        -WorkingDirectory $InstallPath `
                        -Description ($Script:App.Name + ' - DeepSeek Harness 桌面版')) {
        Write-Ok '已创建桌面快捷方式'
    }
    else {
        Write-Alert '桌面快捷方式创建失败（不影响使用，可从开始菜单启动）'
    }

    # --- 创建开始菜单快捷方式 ---
    $startDir = Join-Path (Get-StartMenuPath) $Script:App.Name
    $startLnk = Join-Path $startDir ($Script:App.Name + '.lnk')
    if (New-AppShortcut -ShortcutPath $startLnk -TargetPath $installedExe `
                        -WorkingDirectory $InstallPath `
                        -Description ($Script:App.Name + ' - DeepSeek Harness 桌面版')) {
        Write-Ok '已创建开始菜单快捷方式'
    }
    else {
        Write-Alert '开始菜单快捷方式创建失败（不影响使用）'
    }
}
else {
    Write-Fail '未找到主程序，安装可能未真正完成'
    Stop-Deploy -Reason '安装结果验证失败' `
                -Hint '请尝试以管理员身份重新运行，或查看 docs\06-故障排查.md' `
                -Code $Script:ExitCode.VerifyFail -NoPause:$Silent
}

# ============================================================================
#  步骤 6 / 6 —— 收尾与清理
# ============================================================================
Show-StepHeader '收尾与清理'

# 清理临时文件（离线包本身保留，不删用户文件）
try {
    if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
    Write-Ok '已清理临时文件'
}
catch {
    Write-Log -Message '临时文件清理失败（可忽略）' -Level 'WARN'
}

# 写入安装记录，便于后续卸载与技术支持
try {
    $recordDir = Join-Path $env:LOCALAPPDATA 'DSH-Deploy'
    if (-not (Test-Path $recordDir)) { New-Item -ItemType Directory -Path $recordDir -Force | Out-Null }
    $record = @{
        ProductName    = $Script:Brand.ProductName
        ProductVersion = $Script:Brand.ProductVersion
        AppVersion     = $installedVersion
        InstallPath    = $InstallPath
        InstallTime    = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        Upgrade        = $isUpgrade
        OfflineInstall = $usedOffline
        InstallerSha256= $sha256
        Computer       = $env:COMPUTERNAME
        User           = $env:USERNAME
    }
    $record | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $recordDir 'install-record.json') -Encoding UTF8
    Write-Ok '已写入安装记录（供售后追溯）'
}
catch {
    Write-Log -Message '安装记录写入失败（可忽略）' -Level 'WARN'
}

$elapsed = [math]::Round(((Get-Date) - $Script:startTime).TotalSeconds, 1)
Write-Note ('全程耗时 ' + $elapsed + ' 秒')

# ============================================================================
#  完成
# ============================================================================
Show-SuccessBanner -InstallDir $InstallPath -Version $installedVersion

$logPath = Get-LogPath
if ($logPath) { Write-Host ('  诊断日志: ' + $logPath) -ForegroundColor DarkGray }

# --- 启动程序 ---
$shouldLaunch = $false
if ($NoLaunch -or $Silent) {
    $shouldLaunch = $false
}
else {
    Write-Host ''
    $ans = Read-Host '  是否立即启动 DSH Desktop? (Y/N，直接回车=是)'
    if ($ans -eq '' -or $ans -eq 'Y' -or $ans -eq 'y') { $shouldLaunch = $true }
}

if ($shouldLaunch) {
    try {
        Start-Process -FilePath $installedExe -WorkingDirectory $InstallPath
        Write-Ok 'DSH Desktop 已启动，首次使用请按向导配置 AI 模型'
        Write-Log -Message '已启动应用程序' -Level 'OK'
    }
    catch {
        Write-Alert ('启动失败，请手动双击桌面图标：' + $_.Exception.Message)
    }
}
else {
    Write-Note '未自动启动，可随时双击桌面图标使用'
}

Write-Host ''
Write-Host '  感谢使用 ' + $Script:Brand.ProductName -ForegroundColor Cyan
if ($Script:Brand.Vendor -ne '您的公司名称') {
    Write-Host ('  技术支持: ' + $Script:Brand.VendorContact + '   ' + $Script:Brand.VendorPhone) -ForegroundColor DarkGray
}
Write-Host ''

Complete-Deploy -Code $Script:ExitCode.Success
