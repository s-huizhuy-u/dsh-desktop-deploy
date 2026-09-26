# ============================================================================
#  DSH Desktop 专业部署包 - 环境检测与诊断工具
#  Test-DSHEnvironment.ps1
# ----------------------------------------------------------------------------
#  编码要求：UTF-8 with BOM
# ----------------------------------------------------------------------------
#  用途：
#    1. 安装前预检：确认目标电脑是否满足安装条件
#    2. 安装后诊断：导出诊断报告供技术支持分析
# ----------------------------------------------------------------------------
#  用法：
#    .\Test-DSHEnvironment.ps1              屏幕输出检测结果
#    .\Test-DSHEnvironment.ps1 -Export      同时导出诊断报告文件
# ============================================================================

[CmdletBinding()]
param(
    [switch]$Export,
    [switch]$Silent,
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

Initialize-DeployLog -Tag 'diagnose' | Out-Null
Show-Banner

Write-Host '  环境检测与诊断' -ForegroundColor White

$report = New-Object System.Collections.Generic.List[string]
function Add-Report {
    param([string]$Line = '')
    $report.Add($Line) | Out-Null
}

$addHeader = {
    param([string]$T)
    Add-Report ''
    Add-Report ('=' * 70)
    Add-Report ('  ' + $T)
    Add-Report ('=' * 70)
}

$addItem = {
    param([string]$K, [string]$V)
    # 按显示宽度补齐，保证报告里中文键名也能对齐
    Add-Report ('  ' + (Format-PadRight -Text $K -Width 24) + ': ' + $V)
}

& $addHeader ($Script:Brand.ProductName + ' — 环境诊断报告')
& $addItem '报告生成时间' (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
& $addItem '产品版本' $Script:Brand.ProductVersion
& $addItem '目标应用' ($Script:App.Name + ' (v' + $Script:App.MinVersion + '+)')

# ============================================================================
#  一、系统信息
# ============================================================================
Write-Head '一、系统信息'
& $addHeader '一、系统信息'

$info = Get-SystemReport

Write-KeyValue -Key '计算机名'     -Value $info.ComputerName
& $addItem '计算机名' $info.ComputerName
Write-KeyValue -Key '当前用户'     -Value $info.UserName
& $addItem '当前用户' $info.UserName
Write-KeyValue -Key '操作系统'     -Value ($info.OSName + ' ' + $info.OSDisplay + ' Build ' + $info.OSBuild)
& $addItem '操作系统' ($info.OSName + ' ' + $info.OSDisplay + ' Build ' + $info.OSBuild)
Write-KeyValue -Key '系统版本号'   -Value $info.OSVersion.ToString()
& $addItem '系统版本号' $info.OSVersion.ToString()
Write-KeyValue -Key '处理器架构'   -Value $info.Architecture
& $addItem '处理器架构' $info.Architecture
Write-KeyValue -Key 'CPU 逻辑核心' -Value $info.ProcessorCount
& $addItem 'CPU 逻辑核心' $info.ProcessorCount
if ($info.TotalMemoryGB) {
    Write-KeyValue -Key '物理内存' -Value ($info.TotalMemoryGB.ToString() + ' GB')
    & $addItem '物理内存' ($info.TotalMemoryGB.ToString() + ' GB')
}
if ($info.DiskFreeGB) {
    Write-KeyValue -Key '系统盘可用' -Value ($info.DiskFreeGB.ToString() + ' GB / ' + $info.DiskTotalGB + ' GB')
    & $addItem '系统盘可用' ($info.DiskFreeGB.ToString() + ' GB / ' + $info.DiskTotalGB + ' GB')
}
Write-KeyValue -Key 'PowerShell' -Value ($info.PSVersion + ' (' + $info.PSEdition + ')')
& $addItem 'PowerShell' ($info.PSVersion + ' (' + $info.PSEdition + ')')
$adminTxt = if ($info.IsAdmin) { '是' } else { '否' }
Write-KeyValue -Key '管理员权限' -Value $adminTxt
& $addItem '管理员权限' $adminTxt

# ============================================================================
#  二、安装要求校验
# ============================================================================
Write-Head '二、安装要求校验'
& $addHeader '二、安装要求校验'

$blockers = @()
$cautions = @()

# --- 操作系统 ---
if ($info.OSVersion.Major -lt 10) {
    Write-Fail '操作系统版本过低'
    & $addItem '操作系统' ('不满足 — ' + $info.OSName)
    $blockers += '操作系统低于 Windows 10'
}
else {
    Write-Ok '操作系统版本符合要求'
    & $addItem '操作系统' '满足'
}

# --- 架构 ---
if ($info.Architecture -notmatch 'AMD64|x64|ARM64') {
    Write-Fail '处理器架构不受支持'
    & $addItem '处理器架构' '不满足'
    $blockers += '非 64 位系统'
}
else {
    Write-Ok '处理器架构符合要求'
    & $addItem '处理器架构' '满足'
}

# --- 磁盘 ---
if ($null -ne $info.DiskFreeGB) {
    if ($info.DiskFreeGB -lt 2) {
        Write-Fail ('系统盘空间不足（' + $info.DiskFreeGB + ' GB）')
        & $addItem '磁盘空间' '不满足'
        $blockers += '系统盘可用空间不足 2 GB'
    }
    elseif ($info.DiskFreeGB -lt 3) {
        Write-Alert ('系统盘空间偏低（' + $info.DiskFreeGB + ' GB）')
        & $addItem '磁盘空间' '偏低'
        $cautions += '建议清理至 3 GB 以上'
    }
    else {
        Write-Ok ('系统盘空间充足（' + $info.DiskFreeGB + ' GB）')
        & $addItem '磁盘空间' '满足'
    }
}

# --- PowerShell ---
if ([version]$info.PSVersion -lt [version]'5.1') {
    Write-Fail 'PowerShell 版本过低'
    & $addItem 'PowerShell' '不满足'
    $blockers += 'PowerShell 低于 5.1'
}
else {
    Write-Ok 'PowerShell 版本符合要求'
    & $addItem 'PowerShell' '满足'
}

# --- 执行策略 ---
try {
    $ep = Get-ExecutionPolicy -Scope CurrentUser
    $epAll = Get-ExecutionPolicy
    & $addItem '执行策略(当前用户)' $ep.ToString()
    & $addItem '执行策略(生效)' $epAll.ToString()
    if ($ep -eq 'Restricted' -or $epAll -eq 'Restricted') {
        Write-Alert '脚本执行被策略限制（安装器会自动绕过）'
        $cautions += '执行策略为 Restricted，已由安装器自动处理'
    }
    else {
        Write-Ok ('执行策略正常（' + $epAll + '）')
    }
}
catch {
    Write-Alert '无法读取执行策略'
}

# --- 磁盘中的临时目录 ---
try {
    $tmp = $env:TEMP
    $tmpFree = (New-Object System.IO.DriveInfo((Split-Path -Qualifier $tmp) + '\')).AvailableFreeSpace / 1GB
    if ($tmpFree -lt 1) {
        Write-Alert ('临时目录所在盘空间不足（' + [math]::Round($tmpFree,1) + ' GB）')
        $cautions += '临时目录空间不足，可能影响下载'
    }
    else {
        Write-Ok ('临时目录可用（' + $tmp + '）')
    }
    & $addItem '临时目录' $tmp
}
catch { }

# ============================================================================
#  三、网络连通性
# ============================================================================
Write-Head '三、网络连通性'
& $addHeader '三、网络连通性'

$targets = @(
    @{ N = '官方下载站'; U = 'https://dshdesktop.com' },
    @{ N = 'GitHub 备用源'; U = 'https://github.com' },
    @{ N = '基础连通性'; U = 'https://www.baidu.com' }
)

$reach = 0
foreach ($t in $targets) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $line = ''
    try {
        $req = [System.Net.HttpWebRequest]::Create($t.U)
        $req.Method = 'HEAD'
        $req.Timeout = 8000
        $req.UserAgent = 'DSHDeploy-Diag'
        $resp = $req.GetResponse()
        $code = [int]$resp.StatusCode
        $resp.Dispose()
        $sw.Stop()
        $line = ('可访问  HTTP ' + $code + '  ' + $sw.ElapsedMilliseconds + ' ms')
        Write-Ok ((Format-PadRight -Text $t.N -Width 16) + $line)
        $reach++
    }
    catch [System.Net.WebException] {
        $sw.Stop()
        if ($_.Exception.Response) {
            $line = ('可访问  HTTP ' + [int]$_.Exception.Response.StatusCode + '  ' + $sw.ElapsedMilliseconds + ' ms')
            Write-Ok ((Format-PadRight -Text $t.N -Width 16) + $line)
            $reach++
        }
        else {
            $line = ('不可达  ' + $_.Exception.Message)
            Write-Fail ((Format-PadRight -Text $t.N -Width 16) + $line)
        }
    }
    catch {
        $sw.Stop()
        $line = ('不可达  ' + $_.Exception.Message)
        Write-Fail ((Format-PadRight -Text $t.N -Width 16) + $line)
    }
    & $addItem $t.N $line
}

if ($reach -eq 0) {
    $blockers += '所有下载站点均不可达'
}

# --- 代理设置 ---
try {
    $proxy = [System.Net.WebRequest]::DefaultWebProxy
    $proxyDesc = '未启用'
    if ($proxy) {
        $pu = $proxy.GetProxy([Uri]'https://dshdesktop.com')
        if ($pu -and $pu.ToString() -ne 'https://dshdesktop.com/') {
            $proxyDesc = $pu.ToString()
            Write-Alert ('检测到代理服务器: ' + $pu)
            $cautions += '存在代理服务器，若下载失败请检查代理配置'
        }
        else {
            Write-Ok '未使用代理'
        }
    }
    else {
        Write-Ok '未使用代理'
    }
    & $addItem '系统代理' $proxyDesc
}
catch { }

# --- 下载速度抽样 ---
if ($reach -gt 0) {
    Write-Note '正在进行下载速度抽样测试...'
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $req = [System.Net.HttpWebRequest]::Create('https://dshdesktop.com/download/dsh-desktop-windows-x64-setup.exe')
        $req.Method = 'GET'
        $req.Timeout = 10000
        $req.ReadWriteTimeout = 10000
        $req.UserAgent = 'DSHDeploy-Diag'
        $req.AddRange(0, 524287)   # 只取前 512KB
        $resp = $req.GetResponse()
        $st = $resp.GetResponseStream()
        $buf = New-Object byte[] 65536
        $got = 0
        while ($got -lt 524288) {
            $r = $st.Read($buf, 0, $buf.Length)
            if ($r -le 0) { break }
            $got += $r
        }
        $st.Dispose(); $resp.Dispose(); $sw.Stop()
        $kbps = if ($sw.Elapsed.TotalSeconds -gt 0) { [math]::Round(($got / 1KB) / $sw.Elapsed.TotalSeconds, 0) } else { 0 }
        $speedTxt = ($kbps.ToString() + ' KB/s（实测抽样 ' + [math]::Round($got/1KB,0) + ' KB）')
        Write-Ok ('下载速度: ' + $speedTxt)
        & $addItem '下载速度抽样' $speedTxt
        if ($kbps -lt 100) {
            $cautions += '下载速度较慢，完整包约 200 MB，请预留时间'
        }
    }
    catch {
        Write-Alert ('速度抽样失败: ' + $_.Exception.Message)
        & $addItem '下载速度抽样' ('失败 — ' + $_.Exception.Message)
        $cautions += '无法完成速度抽样，可能网络受限'
    }
}

# ============================================================================
#  四、安装状态
# ============================================================================
Write-Head '四、安装状态'
& $addHeader '四、安装状态'

$installDir = $Script:App.DefaultDir
$recordFile = Join-Path $env:LOCALAPPDATA 'DSH-Deploy\install-record.json'
if (Test-Path $recordFile) {
    try {
        $rec = Get-Content $recordFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($rec.InstallPath) { $installDir = $rec.InstallPath }
        Write-Note ('发现安装记录（' + $rec.InstallTime + '）')
        & $addItem '安装记录' ('存在，记录时间 ' + $rec.InstallTime)
    }
    catch { }
}

$ver = Get-InstalledVersion -InstallDir $installDir
if ($ver) {
    Write-Ok ($Script:App.Name + ' 已安装，版本 ' + $ver)
    & $addItem '安装状态' ('已安装 v' + $ver)
    & $addItem '安装目录' $installDir

    # 检查卸载程序
    $un = Join-Path $installDir $Script:App.UninstallerName
    if (Test-Path $un) {
        Write-Ok '卸载程序完整'
        & $addItem '卸载程序' '存在'
    }
    else {
        Write-Alert '未找到卸载程序'
        $cautions += '缺少官方卸载程序，卸载时将由部署包强制清理'
    }
}
else {
    Write-Note '未检测到已安装的 ' + $Script:App.Name
    & $addItem '安装状态' '未安装'
}

# 运行中进程
$procName = [System.IO.Path]::GetFileNameWithoutExtension($Script:App.ExeName)
$running = Get-Process -Name $procName -ErrorAction SilentlyContinue
if ($running) {
    Write-Note ('程序正在运行（' + $running.Count + ' 个进程）')
    & $addItem '运行状态' ('运行中，' + $running.Count + ' 个进程')
}
else {
    & $addItem '运行状态' '未运行'
}

# 快捷方式
$deskLnk = Join-Path (Get-DesktopPath) ($Script:App.Name + '.lnk')
& $addItem '桌面快捷方式' $(if (Test-Path $deskLnk) { '存在' } else { '不存在' })

# 个人数据
$dataDirs = @(
    (Join-Path $env:APPDATA 'dsh-desktop'),
    (Join-Path $env:LOCALAPPDATA 'dsh-desktop'),
    (Join-Path $env:USERPROFILE '.dsh')
)
$foundData = @()
foreach ($d in $dataDirs) { if (Test-Path $d) { $foundData += $d } }
if ($foundData.Count -gt 0) {
    Write-Note ('个人数据目录: ' + ($foundData -join '; '))
    & $addItem '个人数据' ($foundData.Count.ToString() + ' 个目录')
}
else {
    & $addItem '个人数据' '无'
}

# ============================================================================
#  五、常见干扰项排查
# ============================================================================
Write-Head '五、常见干扰项排查'
& $addHeader '五、常见干扰项排查'

# --- 安全软件 ---
$avNames = @('360tray','360safe','ZhuDongFangYu','QQPCTray','QQPCRTP','kxetray','kavstart',
             'avp','MsMpEng','McAfee','NortonSecurity','BaiduSd','HipsTray','usysdiag')
$foundAv = @()
foreach ($p in $avNames) {
    if (Get-Process -Name $p -ErrorAction SilentlyContinue) { $foundAv += $p }
}
if ($foundAv.Count -gt 0) {
    $avTxt = ($foundAv -join ', ')
    Write-Alert ('检测到安全软件进程: ' + $avTxt)
    Write-Note '若安装被拦截，请临时退出安全软件或将其加入白名单'
    & $addItem '安全软件' $avTxt
    $cautions += '检测到安全软件，可能拦截安装，建议临时退出或加白名单'
}
else {
    Write-Ok '未检测到常见安全软件进程（不代表绝对没有）'
    & $addItem '安全软件' '未检测到常见进程'
}

# --- Windows Defender 实时防护 ---
try {
    $mp = Get-MpComputerStatus -ErrorAction Stop
    $rt = if ($mp.RealTimeProtectionEnabled) { '已开启' } else { '已关闭' }
    & $addItem 'Defender 实时防护' $rt
    if ($mp.RealTimeProtectionEnabled) {
        Write-Note ('Windows Defender 实时防护: ' + $rt + '（正常，一般不影响安装）')
    }
}
catch {
    & $addItem 'Defender 实时防护' '无法读取'
}

# --- 系统盘权限 ---
try {
    $testFile = Join-Path $env:LOCALAPPDATA ('dsh-write-test-' + [Guid]::NewGuid().ToString('N').Substring(0,6) + '.tmp')
    Set-Content -Path $testFile -Value 'test' -ErrorAction Stop
    Remove-Item $testFile -Force -ErrorAction SilentlyContinue
    Write-Ok '用户目录可写'
    & $addItem '用户目录写入' '正常'
}
catch {
    Write-Fail '用户目录不可写'
    & $addItem '用户目录写入' '失败'
    $blockers += '当前用户目录不可写，可能受权限策略限制'
}

# --- 长路径支持（新版插件可能路径较深） ---
try {
    $lp = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name LongPathsEnabled -ErrorAction Stop
    $lpTxt = if ($lp.LongPathsEnabled -eq 1) { '已启用' } else { '未启用' }
    & $addItem '长路径支持' $lpTxt
    if ($lp.LongPathsEnabled -ne 1) {
        $cautions += '长路径支持未启用，若插件安装异常可尝试启用'
    }
}
catch {
    & $addItem '长路径支持' '无法读取'
}

# --- 系统时间（影响 HTTPS 证书校验） ---
$now = Get-Date
$diffDays = [math]::Abs(($now - (Get-Date).ToUniversalTime().ToLocalTime()).TotalDays)
& $addItem '系统时间' ($now.ToString('yyyy-MM-dd HH:mm:ss'))
if ($now.Year -lt 2020 -or $now.Year -gt 2100) {
    Write-Fail '系统时间异常，会导证书校验失败'
    & $addItem '系统时间检查' '异常'
    $blockers += '系统时间异常，将导致 HTTPS 下载失败'
}
else {
    Write-Ok '系统时间正常'
}

# ============================================================================
#  六、结论
# ============================================================================
Write-Head '六、结论'
& $addHeader '六、结论'

if ($blockers.Count -eq 0) {
    Show-Box -Lines @('✓   环境检测通过，可以开始安装') -Color Green
    Add-Report ''
    Add-Report '  >>> 结论: 环境检测通过，可以开始安装 <<<'
}
else {
    Show-Box -Lines @('×   存在阻断性问题', '暂不满足安装条件') -Color Red
    Write-Host '  阻断性问题:' -ForegroundColor Red
    foreach ($b in $blockers) { Write-Host ('    × ' + $b) -ForegroundColor Red }
    Add-Report ''
    Add-Report '  >>> 结论: 存在阻断性问题，暂不满足安装条件 <<<'
    Add-Report '  阻断性问题:'
    foreach ($b in $blockers) { Add-Report ('    × ' + $b) }
}

if ($cautions.Count -gt 0) {
    Write-Host ''
    Write-Host '  需要注意（不影响安装）:' -ForegroundColor Yellow
    foreach ($c in $cautions) { Write-Host ('    ! ' + $c) -ForegroundColor Yellow }
    Add-Report ''
    Add-Report '  需要注意（不影响安装）:'
    foreach ($c in $cautions) { Add-Report ('    ! ' + $c) }
}

# ============================================================================
#  导出报告
# ============================================================================
if ($Export -or (-not $Silent -and $blockers.Count -gt 0)) {
    $outDir = Join-Path $Script:ProductRoot 'logs'
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $outFile = Join-Path $outDir ('诊断报告-' + $stamp + '.txt')

    Add-Report ''
    Add-Report ('=' * 70)
    Add-Report '  技术支持提示'
    Add-Report ('=' * 70)
    Add-Report '  请把本文件完整发送给技术支持人员，可大幅加快问题定位速度。'
    Add-Report ''
    Add-Report ('  技术支持: ' + $Script:Brand.VendorContact + '   ' + $Script:Brand.VendorPhone)
    Add-Report ('  产品: ' + $Script:Brand.ProductName + ' v' + $Script:Brand.ProductVersion)

    try {
        $report | Set-Content -Path $outFile -Encoding UTF8
        Write-Host ''
        Write-Ok ('诊断报告已导出: ' + $outFile)
        Write-Host '  请把该文件发送给技术支持，可加快问题解决' -ForegroundColor Yellow
    }
    catch {
        Write-Alert ('报告导出失败: ' + $_.Exception.Message)
    }
}

$logPath = Get-LogPath
if ($logPath) {
    Write-Host ''
    Write-Host ('  运行日志: ' + $logPath) -ForegroundColor DarkGray
}

Write-Host ''
if (-not $Silent -and (Test-NeedPause)) { Wait-ForKeypress -Message '按任意键关闭本窗口...' }

if ($blockers.Count -gt 0) { exit $Script:ExitCode.RequirementFail }
exit $Script:ExitCode.Success
