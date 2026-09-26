# ============================================================================
#  DSH Desktop 专业部署包 - 公共函数库
#  Common.ps1
# ----------------------------------------------------------------------------
#  编码要求：本文件必须以 UTF-8 with BOM 保存
#  PowerShell 5.1 在无 BOM 时会把中文误判为 ANSI，导致语法错误
# ----------------------------------------------------------------------------
#  兼容性：Windows PowerShell 5.1 / PowerShell 7.x
# ============================================================================

# 说明：刻意不启用 Set-StrictMode。
# 面向客户现场的部署脚本以「稳定完成」优先，严格模式会把可选属性的缺失
# 升级为致命错误，反而降低兼容性。所有高风险调用均已单独 try/catch。
$ErrorActionPreference = 'Stop'

# ============================================================================
#  【品牌配置区】修改此处即可完成产品改名（二次销售/OEM 定制）
# ============================================================================
$Script:Brand = @{
    ProductName    = 'DSH Desktop 专业部署包'
    ProductShort   = 'DSH 部署包'
    ProductVersion = '1.0.0'
    BuildDate      = '2026-01-15'
    Vendor         = '您的公司名称'          # ← 改成你的公司名
    VendorContact  = 'support@example.com'  # ← 改成你的客服邮箱
    VendorPhone    = '400-000-0000'         # ← 改成你的客服电话
    License        = '商业授权 / Commercial License'
}

# ============================================================================
#  【目标应用配置区】
# ============================================================================
$Script:App = @{
    Name            = 'DSH Desktop'
    Publisher       = 'DataElement'
    ExeName         = 'DSH Desktop.exe'
    UninstallerName = 'Uninstall DSH Desktop.exe'
    DefaultDir      = Join-Path $env:LOCALAPPDATA 'Programs\DSH Desktop'
    MinVersion      = '0.9.0'
}

# 下载地址（按顺序尝试，第一个失败自动切换下一个）
$Script:DownloadMirrors = @(
    'https://dshdesktop.com/download/dsh-desktop-windows-x64-setup.exe'
    'https://github.com/dataelement/dsh-desktop/releases/latest/download/dsh-desktop-windows-x64-setup.exe'
)
$Script:InstallerFileName = 'dsh-desktop-windows-x64-setup.exe'
$Script:OfficialSite      = 'https://dshdesktop.com'
$Script:OfficialRepo      = 'https://github.com/dataelement/dsh-desktop'

# 退出码约定（供企业批量部署脚本判断结果）
$Script:ExitCode = @{
    Success          = 0
    GenericFailure   = 1
    RequirementFail  = 2
    DownloadFail     = 3
    InstallFail      = 4
    VerifyFail       = 5
    UserCancelled    = 6
}

# ============================================================================
#  路径解析
# ============================================================================
$Script:ScriptsDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$Script:ProductRoot = Split-Path -Parent $Script:ScriptsDir
if (-not $Script:ProductRoot) { $Script:ProductRoot = $Script:ScriptsDir }

$Script:LogDir  = Join-Path $Script:ProductRoot 'logs'
$Script:DocsDir = Join-Path $Script:ProductRoot 'docs'
$Script:LogFile = $null

# 暂停行为控制。
# BAT 启动器会传入 -NoPause 并自行负责"按任意键"，
# 这样直接运行 .ps1 时仍有暂停，经启动器运行时不会出现双重暂停。
$Script:NoPause = $false

# ============================================================================
#  日志系统
# ============================================================================
function Initialize-DeployLog {
    <#
    .SYNOPSIS  初始化日志文件。日志用于技术支持时快速定位问题。
    #>
    param([string]$Tag = 'deploy')

    try {
        if (-not (Test-Path $Script:LogDir)) {
            New-Item -ItemType Directory -Path $Script:LogDir -Force | Out-Null
        }
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $Script:LogFile = Join-Path $Script:LogDir ("{0}-{1}.log" -f $Tag, $stamp)

        $header = @(
            ('=' * 74)
            ("  {0}" -f $Script:Brand.ProductName)
            ("  版本: {0}    构建: {1}" -f $Script:Brand.ProductVersion, $Script:Brand.BuildDate)
            ("  开始时间: {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
            ("  计算机名: {0}    用户: {1}" -f $env:COMPUTERNAME, $env:USERNAME)
            ('=' * 74)
            ''
        )
        Add-Content -Path $Script:LogFile -Value $header -Encoding UTF8
        return $Script:LogFile
    }
    catch {
        # 日志不可写不应阻断安装主流程
        $Script:LogFile = $null
        return $null
    }
}

function Write-Log {
    <#
    .SYNOPSIS  写入日志文件（不输出到屏幕）
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'OK', 'WARN', 'ERROR', 'STEP')][string]$Level = 'INFO'
    )
    if (-not $Script:LogFile) { return }
    try {
        $line = '[{0}] [{1,-5}] {2}' -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message
        Add-Content -Path $Script:LogFile -Value $line -Encoding UTF8
    }
    catch { }
}

function Get-LogPath { return $Script:LogFile }

# ============================================================================
#  控制台编码
#  保证在任意系统区域设置（含英文 Windows）下中文都能正确显示
# ============================================================================
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
}
catch { }

# ============================================================================
#  显示宽度计算
# ----------------------------------------------------------------------------
#  中文/全角字符在控制台占 2 列。若用 String.Length 计算宽度，
#  所有边框、表格、对齐都会错位。以下函数按「显示列数」计算。
# ============================================================================
function Get-DisplayWidth {
    param([string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { return 0 }

    $width = 0
    foreach ($ch in $Text.ToCharArray()) {
        $c = [int]$ch
        $isWide =
            ($c -ge 0x1100 -and $c -le 0x115F) -or   # 谚文字母
            ($c -ge 0x2E80 -and $c -le 0x303E) -or   # 中日韩部首、标点
            ($c -ge 0x3041 -and $c -le 0x33FF) -or   # 假名、注音、兼容字符
            ($c -ge 0x3400 -and $c -le 0x4DBF) -or   # 中日韩扩展 A
            ($c -ge 0x4E00 -and $c -le 0x9FFF) -or   # 中日韩统一表意文字
            ($c -ge 0xA000 -and $c -le 0xA4CF) -or   # 彝文
            ($c -ge 0xAC00 -and $c -le 0xD7A3) -or   # 谚文音节
            ($c -ge 0xF900 -and $c -le 0xFAFF) -or   # 兼容表意文字
            ($c -ge 0xFE30 -and $c -le 0xFE6F) -or   # 兼容形式
            ($c -ge 0xFF00 -and $c -le 0xFF60) -or   # 全角形式
            ($c -ge 0xFFE0 -and $c -le 0xFFE6)       # 全角符号

        if ($isWide) { $width += 2 } else { $width += 1 }
    }
    return $width
}

function Format-PadRight {
    <# 按显示宽度右侧补空格，保证中英文混排时列对齐 #>
    param([string]$Text, [int]$Width)
    if ($null -eq $Text) { $Text = '' }
    $need = $Width - (Get-DisplayWidth -Text $Text)
    if ($need -le 0) { return $Text }
    return $Text + (' ' * $need)
}

function Get-Truncated {
    <# 按显示宽度截断，超出部分以 … 结尾 #>
    param([string]$Text, [int]$Width)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    if ((Get-DisplayWidth -Text $Text) -le $Width) { return $Text }

    $out = ''
    $w = 0
    foreach ($ch in $Text.ToCharArray()) {
        $cw = Get-DisplayWidth -Text ([string]$ch)
        if (($w + $cw) -gt ($Width - 1)) { break }
        $out += $ch
        $w += $cw
    }
    return ($out + '…')
}

# ============================================================================
#  界面输出（同时写日志）
# ============================================================================
function Write-Raw {
    param([string]$Text = '', [string]$Color = 'Gray', [switch]$NoNewline)
    if ($NoNewline) { Write-Host $Text -ForegroundColor $Color -NoNewline }
    else            { Write-Host $Text -ForegroundColor $Color }
}

function Write-Head {
    <# 章节标题（按显示宽度补齐横线，中文标题不会错位） #>
    param([string]$Message)
    $used  = 4 + (Get-DisplayWidth -Text $Message) + 1
    $fill  = [math]::Max(0, 62 - $used)
    Write-Host ''
    Write-Host ('  ── ' + $Message + ' ' + ('─' * $fill)) -ForegroundColor Magenta
    Write-Log -Message $Message -Level 'STEP'
}

function Write-Note {
    param([string]$Message)
    Write-Host ('  · ' + $Message) -ForegroundColor Gray
    Write-Log -Message $Message -Level 'INFO'
}

function Write-Ok {
    param([string]$Message)
    Write-Host ('  √ ' + $Message) -ForegroundColor Green
    Write-Log -Message $Message -Level 'OK'
}

function Write-Alert {
    param([string]$Message)
    Write-Host ('  ! ' + $Message) -ForegroundColor Yellow
    Write-Log -Message $Message -Level 'WARN'
}

function Write-Fail {
    param([string]$Message)
    Write-Host ('  × ' + $Message) -ForegroundColor Red
    Write-Log -Message $Message -Level 'ERROR'
}

function Write-KeyValue {
    param(
        [string]$Key,
        [string]$Value,
        [string]$Color = 'White',
        [int]$KeyWidth = 22
    )
    $k = Format-PadRight -Text $Key -Width $KeyWidth
    Write-Host ('    ' + $k + ': ') -ForegroundColor DarkGray -NoNewline
    Write-Host $Value -ForegroundColor $Color
    Write-Log -Message ("{0}: {1}" -f $Key, $Value) -Level 'INFO'
}

function Write-Bullet {
    <# 对齐的列表项：键 + 值 #>
    param([string]$Key, [string]$Value, [string]$Color = 'Gray')
    Write-Host ('    · ' + (Format-PadRight -Text $Key -Width 24) + $Value) -ForegroundColor $Color
}

function Format-Center {
    <# 按显示宽度居中 #>
    param([string]$Text, [int]$Width)
    if ($null -eq $Text) { $Text = '' }
    $w = Get-DisplayWidth -Text $Text
    if ($w -ge $Width) { return $Text }
    $total = $Width - $w
    $left  = [int][math]::Floor($total / 2)
    $right = $total - $left
    return (' ' * $left) + $Text + (' ' * $right)
}

function Show-Banner {
    <# 产品主横幅（按显示宽度绘制，中英文混排均不错位） #>
    $b = $Script:Brand
    $inner = 62
    $top = '  ╔' + ('═' * $inner) + '╗'
    $mid = '  ║' + (' ' * $inner) + '║'
    $bot = '  ╚' + ('═' * $inner) + '╝'

    Write-Host ''
    Write-Host $top -ForegroundColor Cyan
    Write-Host $mid -ForegroundColor Cyan
    Write-Host ('  ║' + (Format-Center -Text $b.ProductName -Width $inner) + '║') -ForegroundColor Cyan
    Write-Host ('  ║' + (Format-Center -Text 'DeepSeek Harness 桌面版 · 一键部署' -Width $inner) + '║') -ForegroundColor DarkCyan
    Write-Host $mid -ForegroundColor Cyan
    Write-Host ('  ║' + (Format-Center -Text ('版本 ' + $b.ProductVersion + '    构建 ' + $b.BuildDate) -Width $inner) + '║') -ForegroundColor DarkGray
    Write-Host $mid -ForegroundColor Cyan
    Write-Host $bot -ForegroundColor Cyan
    Write-Host ''
    Write-Log -Message ("会话启动 {0} v{1}" -f $b.ProductName, $b.ProductVersion) -Level 'STEP'
}

function Show-Box {
    <#
    .SYNOPSIS  绘制居中方框（按显示宽度计算，中文不会撑破边框）
    #>
    param(
        [string[]]$Lines,
        [string]$Color = 'Cyan',
        [int]$InnerWidth = 62
    )

    $top = '  ╔' + ('═' * $InnerWidth) + '╗'
    $bot = '  ╚' + ('═' * $InnerWidth) + '╝'

    Write-Host ''
    Write-Host $top -ForegroundColor $Color
    foreach ($l in $Lines) {
        Write-Host ('  ║' + (Format-Center -Text $l -Width $InnerWidth) + '║') -ForegroundColor $Color
    }
    Write-Host $bot -ForegroundColor $Color
    Write-Host ''
}

function Show-SuccessBanner {
    param([string]$InstallDir, [string]$Version)

    Write-Host ''
    Show-Box -Lines @('', '✓   部 署 成 功', '') -Color Green
    if ($Version) { Write-KeyValue -Key '已安装版本' -Value $Version -Color Green }
    if ($InstallDir) { Write-KeyValue -Key '安装位置' -Value $InstallDir }
    Write-Host ''
    Write-Host '  启动方式（任选其一）:' -ForegroundColor White
    Write-Host '    1. 双击桌面上的 "DSH Desktop" 图标' -ForegroundColor Gray
    Write-Host '    2. 开始菜单搜索 "DSH Desktop"' -ForegroundColor Gray
    Write-Host '    3. 直接运行安装目录下的 DSH Desktop.exe' -ForegroundColor Gray
    Write-Host ''
    Write-Host '  下一步: 首次启动后请配置 AI 模型，详见 docs\04-使用手册.md' -ForegroundColor Yellow
    Write-Host ''
}

function Show-FailBanner {
    param([string]$Reason, [string]$Hint)
    Show-Box -Lines @('部 署 未 完 成') -Color Red
    if ($Reason) { Write-Host ('  原因: ' + $Reason) -ForegroundColor Red }
    if ($Hint)   { Write-Host ('  建议: ' + $Hint) -ForegroundColor Yellow }
    Write-Host ''
}

# ============================================================================
#  下载进度条
# ============================================================================
function Show-DownloadProgress {
    param(
        [long]$Received,
        [long]$Total,
        [double]$Seconds,
        [switch]$Complete
    )

    $width = 34
    $mbRecv = $Received / 1MB
    $speed  = if ($Seconds -gt 0.5) { [math]::Round($mbRecv / $Seconds, 2) } else { 0 }

    if ($Total -gt 0) {
        $pct    = [int][math]::Floor($Received * 100 / $Total)
        if ($pct -gt 100) { $pct = 100 }
        $filled = [int][math]::Floor($width * $pct / 100)
        $bar    = ('█' * $filled) + ('░' * ($width - $filled))
        $line   = '    [{0}] {1,3}%   {2,7:N1} / {3:N1} MB   {4,6:N2} MB/s' -f $bar, $pct, $mbRecv, ($Total / 1MB), $speed
    }
    else {
        $dots = [int]($Received / 1MB) % ($width + 1)
        $bar  = ('█' * $dots) + ('░' * ($width - $dots))
        $line = '    [{0}]  --    {1,7:N1} MB            {2,6:N2} MB/s' -f $bar, $mbRecv, $speed
    }

    Write-Host ("`r" + $line) -ForegroundColor Cyan -NoNewline
    if ($Complete) {
        Write-Host ''
        Write-Log -Message ("下载完成 共 {0:N1} MB 用时 {1:N1} 秒 均速 {2:N2} MB/s" -f $mbRecv, $Seconds, $speed) -Level 'OK'
    }
}

# ============================================================================
#  网络下载（流式 + 进度 + 断点感知）
# ============================================================================
function Invoke-StreamDownload {
    <#
    .SYNOPSIS  单次流式下载，带实时进度条
    .OUTPUTS   成功返回 $true，失败抛出异常
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Destination,
        [int]$TimeoutMs = 60000
    )

    $request = $null; $response = $null; $stream = $null; $fileStream = $null

    try {
        $request = [System.Net.HttpWebRequest]::Create($Url)
        $request.UserAgent          = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) DSHDeploy/' + $Script:Brand.ProductVersion
        $request.Timeout            = $TimeoutMs
        $request.ReadWriteTimeout   = 300000
        $request.AllowAutoRedirect  = $true
        $request.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate

        $response = $request.GetResponse()
        $total    = $response.ContentLength
        $stream   = $response.GetResponseStream()

        $fileStream = [System.IO.File]::Create($Destination)
        $buffer     = New-Object byte[] 131072
        $received   = [long]0
        $watch      = [System.Diagnostics.Stopwatch]::StartNew()
        $lastDraw   = [DateTime]::MinValue

        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $fileStream.Write($buffer, 0, $read)
            $received += $read

            $now = [DateTime]::Now
            if (($now - $lastDraw).TotalMilliseconds -ge 150) {
                Show-DownloadProgress -Received $received -Total $total -Seconds $watch.Elapsed.TotalSeconds
                $lastDraw = $now
            }
        }

        $watch.Stop()
        Show-DownloadProgress -Received $received -Total $total -Seconds $watch.Elapsed.TotalSeconds -Complete

        if ($received -le 0) { throw '下载内容为空（0 字节）' }
        if ($total -gt 0 -and $received -ne $total) {
            throw ('下载不完整：预期 {0} 字节，实际 {1} 字节' -f $total, $received)
        }

        return $true
    }
    catch {
        if (Test-Path $Destination) {
            Remove-Item $Destination -Force -ErrorAction SilentlyContinue
        }
        throw
    }
    finally {
        if ($fileStream) { $fileStream.Dispose() }
        if ($stream)     { $stream.Dispose() }
        if ($response)   { $response.Dispose() }
    }
}

function Invoke-ResilientDownload {
    <#
    .SYNOPSIS  多镜像 + 多次重试的健壮下载
    .PARAMETER Urls        候选下载地址列表（按优先级）
    .PARAMETER Destination 保存路径
    .PARAMETER MaxRetries  每个地址的最大尝试次数
    .OUTPUTS   成功返回 $true，全部失败返回 $false
    #>
    param(
        [Parameter(Mandatory = $true)][string[]]$Urls,
        [Parameter(Mandatory = $true)][string]$Destination,
        [int]$MaxRetries = 3
    )

    $total = $Urls.Count
    for ($i = 0; $i -lt $total; $i++) {
        $url = $Urls[$i]
        Write-Note ("下载源 [{0}/{1}] {2}" -f ($i + 1), $total, $url)

        for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
            if ($attempt -gt 1) {
                Write-Alert ("连接中断，正在进行第 {0}/{1} 次重试..." -f $attempt, $MaxRetries)
                Start-Sleep -Seconds (2 * $attempt)
            }
            try {
                [void](Invoke-StreamDownload -Url $url -Destination $Destination)
                return $true
            }
            catch {
                Write-Alert ('本次尝试失败: ' + $_.Exception.Message)
                Write-Log -Message ('下载异常 [' + $url + '] ' + $_.Exception.Message) -Level 'ERROR'
            }
        }

        if ($i -lt ($total - 1)) {
            Write-Alert '切换至备用下载源...'
        }
    }
    return $false
}

function Test-NetworkConnectivity {
    <#
    .SYNOPSIS  检测关键站点连通性
    .OUTPUTS   返回连通成功的目标数量
    #>
    param([string[]]$Targets)

    if (-not $Targets) {
        $Targets = @(
            'https://dshdesktop.com'
            'https://github.com'
            'https://www.baidu.com'
        )
    }

    $ok = 0
    foreach ($t in $Targets) {
        try {
            $req = [System.Net.HttpWebRequest]::Create($t)
            $req.Method = 'HEAD'
            $req.Timeout = 8000
            $req.UserAgent = 'DSHDeploy-ConnectivityCheck'
            $resp = $req.GetResponse()
            $code = [int]$resp.StatusCode
            $resp.Dispose()
            Write-Ok ("{0}  →  HTTP {1}" -f $t, $code)
            $ok++
        }
        catch [System.Net.WebException] {
            $we = $_.Exception
            if ($we.Response) {
                Write-Ok ("{0}  →  HTTP {1}（可访问）" -f $t, [int]$we.Response.StatusCode)
                $ok++
            }
            else {
                Write-Alert ("{0}  →  无法连接" -f $t)
            }
        }
        catch {
            Write-Alert ("{0}  →  无法连接" -f $t)
        }
    }
    return $ok
}

# ============================================================================
#  系统信息采集
# ============================================================================
function Get-SystemReport {
    <#
    .SYNOPSIS  采集系统信息，用于环境检测与日志
    .OUTPUTS   Hashtable
    #>
    $info = @{}

    # --- 操作系统 ---
    $osVer = [Environment]::OSVersion.Version
    $info.OSVersion = $osVer
    $info.OSName = 'Windows'
    try {
        $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        if ($cv.ProductName) { $info.OSName = $cv.ProductName }
        if ($cv.DisplayVersion) { $info.OSDisplay = $cv.DisplayVersion }
        if ($cv.CurrentBuild)   { $info.OSBuild = $cv.CurrentBuild }
        if ($cv.UBR)            { $info.OSBuild = ('{0}.{1}' -f $cv.CurrentBuild, $cv.UBR) }
    }
    catch { }

    # --- 处理器架构 ---
    $arch = $env:PROCESSOR_ARCHITECTURE
    if ($env:PROCESSOR_ARCHITEW6432) { $arch = $env:PROCESSOR_ARCHITEW6432 }
    $info.Architecture = $arch
    $info.ProcessorCount = [Environment]::ProcessorCount
    $info.Is64Bit = [Environment]::Is64BitOperatingSystem

    # --- 内存 ---
    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $info.TotalMemoryGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
    }
    catch {
        $info.TotalMemoryGB = $null
    }

    # --- 磁盘（系统盘） ---
    $sysDrive = ($env:SystemDrive + '\')
    try {
        $d = New-Object System.IO.DriveInfo($sysDrive)
        $info.SystemDrive      = $sysDrive
        $info.DiskFreeGB       = [math]::Round($d.AvailableFreeSpace / 1GB, 1)
        $info.DiskTotalGB      = [math]::Round($d.TotalSize / 1GB, 1)
    }
    catch {
        $info.SystemDrive = $sysDrive
        $info.DiskFreeGB  = $null
        $info.DiskTotalGB = $null
    }

    # --- PowerShell ---
    $info.PSVersion = $PSVersionTable.PSVersion.ToString()
    $info.PSEdition = if ($PSVersionTable.PSEdition) { $PSVersionTable.PSEdition } else { 'Desktop' }

    # --- 权限 ---
    $info.IsAdmin = Test-IsAdministrator

    # --- 显示与网络 ---
    $info.ComputerName = $env:COMPUTERNAME
    $info.UserName     = $env:USERNAME
    $info.TempPath     = $env:TEMP

    return $info
}

function Test-IsAdministrator {
    try {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $p  = New-Object System.Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch { return $false }
}

function Test-SystemRequirements {
    <#
    .SYNOPSIS  逐项校验安装前置条件
    .OUTPUTS   Hashtable: Passed(bool) / Failures(数组) / Warnings(数组) / Info(报告)
    #>
    $result = @{
        Passed   = $true
        Failures = @()
        Warnings = @()
        Info     = $null
    }

    Write-Head '系统环境检测'

    $info = Get-SystemReport
    $result.Info = $info

    # 1) 操作系统版本
    $osLabel = '{0} {1} (Build {2})' -f $info.OSName, $info.OSDisplay, $info.OSBuild
    if ($info.OSVersion.Major -lt 10) {
        Write-Fail ('操作系统版本过低: ' + $osLabel)
        $result.Failures += '需要 Windows 10 或更高版本，当前为 ' + $osLabel
        $result.Passed = $false
    }
    else {
        Write-Ok ('操作系统: ' + $osLabel.Trim())
    }

    # 2) 架构
    if ($info.Architecture -notmatch 'AMD64|x64|ARM64') {
        Write-Fail ('处理器架构不受支持: ' + $info.Architecture)
        $result.Failures += '仅支持 64 位系统（x64 / ARM64），当前为 ' + $info.Architecture
        $result.Passed = $false
    }
    else {
        Write-Ok ('处理器架构: ' + $info.Architecture + '（64 位）')
    }

    # 3) 磁盘空间
    if ($null -ne $info.DiskFreeGB) {
        if ($info.DiskFreeGB -lt 2) {
            Write-Fail ('系统盘可用空间不足: ' + $info.DiskFreeGB + ' GB')
            $result.Failures += ('系统盘至少需要 3 GB 可用空间，当前仅剩 ' + $info.DiskFreeGB + ' GB')
            $result.Passed = $false
        }
        elseif ($info.DiskFreeGB -lt 3) {
            Write-Alert ('系统盘可用空间偏低: ' + $info.DiskFreeGB + ' GB（建议 3 GB 以上）')
            $result.Warnings += '可用空间偏低，可能影响后续插件安装'
        }
        else {
            Write-Ok ('系统盘可用空间: ' + $info.DiskFreeGB + ' GB')
        }
    }
    else {
        Write-Alert '无法读取磁盘空间信息'
        $result.Warnings += '无法读取磁盘空间，请自行确认系统盘剩余 3 GB 以上'
    }

    # 4) 内存（软性提示）
    if ($null -ne $info.TotalMemoryGB) {
        if ($info.TotalMemoryGB -lt 4) {
            Write-Alert ('物理内存偏低: ' + $info.TotalMemoryGB + ' GB（建议 8 GB）')
            $result.Warnings += '内存低于 4 GB，运行大模型任务时可能卡顿'
        }
        else {
            Write-Ok ('物理内存: ' + $info.TotalMemoryGB + ' GB')
        }
    }

    # 5) PowerShell 版本
    if ([version]$info.PSVersion -lt [version]'5.1') {
        Write-Fail ('PowerShell 版本过低: ' + $info.PSVersion)
        $result.Failures += '需要 PowerShell 5.1 或更高版本'
        $result.Passed = $false
    }
    else {
        Write-Ok ('PowerShell: ' + $info.PSVersion + ' (' + $info.PSEdition + ')')
    }

    # 6) 执行策略
    try {
        $ep = Get-ExecutionPolicy -Scope CurrentUser
        if ($ep -eq 'Restricted') {
            Write-Alert ('当前用户执行策略为 Restricted，可能阻止脚本运行')
            $result.Warnings += '执行策略受限，安装器将自动使用 Bypass 方式运行'
        }
        else {
            Write-Ok ('脚本执行策略: ' + $ep)
        }
    }
    catch { }

    # 7) 管理员权限（提示性）
    if ($info.IsAdmin) {
        Write-Ok '运行权限: 管理员'
    }
    else {
        Write-Alert '运行权限: 普通用户（安装到当前用户目录无需管理员，可继续）'
        $result.Warnings += '当前离线用户权限；安装到当前用户目录可正常完成'
    }

    # 8) 网络连通性
    Write-Head '网络连通性检测'
    $reachable = Test-NetworkConnectivity
    if ($reachable -eq 0) {
        Write-Fail '所有下载站点均不可达'
        $result.Failures += '网络不可达，请检查网络连接或代理设置'
        $result.Passed = $false
    }
    else {
        Write-Ok ('可访问的站点数: ' + $reachable)
    }

    return $result
}

# ============================================================================
#  文件校验
# ============================================================================
function Get-FileHashSafe {
    param([Parameter(Mandatory = $true)][string]$Path)
    try {
        return (Get-FileHash -Path $Path -Algorithm SHA256 -ErrorAction Stop).Hash
    }
    catch { return $null }
}

function Test-InstallerFile {
    <#
    .SYNOPSIS  校验下载文件是否为有效的 Windows 可执行程序
    .OUTPUTS   $true / $false
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        # 真实安装包约 200 MB；错误页/拦截页通常远小于 1 MB。
        # 阈值取 1 MB 既能识别异常内容，又不会误伤偏小的合法安装包。
        [long]$MinBytes = 1048576
    )

    if (-not (Test-Path $Path)) { return $false }

    $fi = Get-Item $Path
    if ($fi.Length -lt $MinBytes) {
        Write-Alert ('安装包体积异常（{0:N0} 字节），可能下载到了错误内容' -f $fi.Length)
        return $false
    }

    # 检查 PE 文件头 "MZ"
    try {
        $fs = [System.IO.File]::OpenRead($Path)
        $b0 = $fs.ReadByte()
        $b1 = $fs.ReadByte()
        $fs.Close()
        if ($b0 -ne 0x4D -or $b1 -ne 0x5A) {
            Write-Alert '安装包文件头校验失败，文件不是有效的 Windows 程序'
            return $false
        }
    }
    catch {
        Write-Alert ('无法读取安装包: ' + $_.Exception.Message)
        return $false
    }

    return $true
}

function Get-InstalledVersion {
    <#
    .SYNOPSIS  读取本机已安装的 DSH Desktop 版本
    .OUTPUTS   版本字符串；未安装返回 $null
    #>
    param([string]$InstallDir)

    if (-not $InstallDir) { $InstallDir = $Script:App.DefaultDir }
    $exe = Join-Path $InstallDir $Script:App.ExeName
    if (-not (Test-Path $exe)) { return $null }

    try {
        $vi = (Get-Item $exe).VersionInfo
        if ($vi.FileVersion) { return $vi.FileVersion }
        if ($vi.ProductVersion) { return $vi.ProductVersion }
    }
    catch { }
    return '未知'
}

# ============================================================================
#  快捷方式
# ============================================================================
function New-AppShortcut {
    param(
        [Parameter(Mandatory = $true)][string]$ShortcutPath,
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [string]$WorkingDirectory,
        [string]$Description
    )

    try {
        $dir = Split-Path -Parent $ShortcutPath
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

        $shell    = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($ShortcutPath)
        $shortcut.TargetPath       = $TargetPath
        if ($WorkingDirectory) { $shortcut.WorkingDirectory = $WorkingDirectory }
        if ($Description)      { $shortcut.Description      = $Description }
        $shortcut.IconLocation     = $TargetPath + ',0'
        $shortcut.Save()
        return $true
    }
    catch {
        Write-Log -Message ('创建快捷方式失败 [' + $ShortcutPath + '] ' + $_.Exception.Message) -Level 'WARN'
        return $false
    }
}

function Get-DesktopPath {
    try {
        $p = [Environment]::GetFolderPath('Desktop')
        if ($p -and (Test-Path $p)) { return $p }
    }
    catch { }
    return (Join-Path $env:USERPROFILE 'Desktop')
}

function Get-StartMenuPath {
    try {
        $p = [Environment]::GetFolderPath('Programs')
        if ($p) { return $p }
    }
    catch { }
    return (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs')
}

# ============================================================================
#  流程辅助
# ============================================================================
function Wait-ForKeypress {
    param([string]$Message = '按任意键继续...')
    Write-Host ''
    Write-Host ('  ' + $Message) -ForegroundColor DarkGray
    try { $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') }
    catch { Start-Sleep -Seconds 3 }
}

function Test-NeedPause {
    <# 是否需要暂停等待用户（BAT 启动器接管时为 $false） #>
    return (-not $Script:NoPause)
}

function Stop-Deploy {
    <#
    .SYNOPSIS  统一失败退出（写日志、打印横幅、返回约定退出码）
    #>
    param(
        [string]$Reason,
        [string]$Hint,
        [int]$Code = 1,
        [switch]$NoPause
    )

    Write-Log -Message ('流程终止: ' + $Reason + ' (退出码 ' + $Code + ')') -Level 'ERROR'
    Show-FailBanner -Reason $Reason -Hint $Hint

    $log = Get-LogPath
    if ($log) { Write-Host ('  诊断日志: ' + $log) -ForegroundColor DarkGray }
    Write-Host ''

    if (-not $NoPause -and (Test-NeedPause)) { Wait-ForKeypress }
    exit $Code
}

function Complete-Deploy {
    <#
    .SYNOPSIS  统一成功退出
    #>
    param(
        [int]$Code = 0,
        [switch]$HideLog
    )

    if (-not $HideLog) {
        $log = Get-LogPath
        if ($log) { Write-Host ('  诊断日志: ' + $log) -ForegroundColor DarkGray }
    }
    Write-Host ''

    if (Test-NeedPause) { Wait-ForKeypress -Message '按任意键关闭本窗口...' }
    exit $Code
}

function Show-LogTail {
    <# 失败时把日志尾部打印出来，方便用户直接截图求助 #>
    param([int]$Lines = 20)
    $log = Get-LogPath
    if (-not $log -or -not (Test-Path $log)) { return }
    Write-Host ''
    Write-Host ('  ── 最近 ' + $Lines + ' 条日志 ──────────────────────────────') -ForegroundColor DarkGray
    try {
        Get-Content $log -Tail $Lines -Encoding UTF8 | ForEach-Object {
            Write-Host ('    ' + $_) -ForegroundColor DarkGray
        }
    }
    catch { }
    Write-Host ''
}

Write-Log -Message '公共函数库加载完成' -Level 'INFO'
