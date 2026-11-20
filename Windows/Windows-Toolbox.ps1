#Requires -Version 5.1
<#
.SYNOPSIS
    Windows 工具箱(优化版)
.PARAMETER Drive
    目标盘符,默认 D
#>
param(
    [ValidatePattern('^[A-Za-z]$')]
    [string]$Drive = "D"
)

$ErrorActionPreference = "Stop"
$Drive = $Drive.ToUpper()

# ==========================================
# 配置
# ==========================================

$RegPath    = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"

# 核心文件夹(默认迁移)
$CoreFolders = [ordered]@{
    "Desktop"                                = "Desktop"
    "{374DE290-123F-4565-9164-39C4925E467B}" = "Downloads"
    "Personal"                               = "Documents"
    "My Pictures"                            = "Pictures"
    "My Video"                               = "Videos"
    "My Music"                               = "Music"
}

# 可选文件夹(迁移时单独询问)
$ExtraFolders = [ordered]@{
    "Favorites"                              = "Favorites"
    "{4C5C32FF-BB9D-43B0-BF8D-7E6B4A7A6E1C}" = "Saved Games"
    "{56784854-C6CB-462B-8169-88E350ACB882}" = "Contacts"
    "{BFB9D5E0-C6A9-404C-B2B2-AE6DB6AF4968}" = "Links"
    "{7D1D3A04-DEBB-4115-95CF-2F29DA2920DA}" = "Searches"
    "{31C0DD25-9439-4F12-BF41-7FF4EDA38722}" = "3D Objects"
}

# ==========================================
# 通用函数
# ==========================================

function Pause-Menu {
    Write-Host ""
    [void](Read-Host "按 Enter 继续")
}

function Test-Admin {
    $Identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object Security.Principal.WindowsPrincipal($Identity)
    return $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Restart-AsAdmin {
    if (-not $PSCommandPath) {
        Write-Host "无法获取脚本路径,请手动以管理员身份运行 PowerShell。" -ForegroundColor Red
        return
    }
    $ArgList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Drive $Drive"
    try {
        Start-Process -FilePath "powershell.exe" -ArgumentList $ArgList -Verb RunAs
        exit
    }
    catch {
        Write-Host "提权已取消或失败:$($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Confirm-Yes([string]$Prompt) {
    $Answer = Read-Host "`n$Prompt(输入 Y 确认)"
    return ($Answer -ceq "y")
}

# 目标盘必须存在且为本地固定磁盘
function Test-TargetDrive([string]$Letter = $Drive) {
    $Root = "${Letter}:\"
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        Write-Host "$Letter 盘不存在!" -ForegroundColor Red
        return $false
    }
    $Disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='${Letter}:'" -ErrorAction SilentlyContinue
    if ($Disk -and $Disk.DriveType -ne 3) {
        Write-Host "$Letter 盘不是本地固定磁盘(可能是U盘/网络盘),为避免开机找不到路径,已拒绝。" -ForegroundColor Red
        return $false
    }
    return $true
}

# 列出可用的本地磁盘(排除系统盘),让用户选择目标盘
function Select-TargetDrive {
    $SysDrive = $env:SystemDrive.TrimEnd(':').ToUpper()
    $Disks = @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue |
               Where-Object { $_.DeviceID.TrimEnd(':').ToUpper() -ne $SysDrive } |
               Sort-Object DeviceID)

    if ($Disks.Count -eq 0) {
        Write-Host "没有找到可用的其他本地磁盘。" -ForegroundColor Red
        return $null
    }

    Write-Host "`n可用的目标磁盘:" -ForegroundColor Cyan
    $Letters = @()
    foreach ($Disk in $Disks) {
        $L = $Disk.DeviceID.TrimEnd(':').ToUpper()
        $Letters += $L
        $Label = if ($Disk.VolumeName) { $Disk.VolumeName } else { "本地磁盘" }
        Write-Host ("  [{0}] {1,-16} 可用 {2} / 共 {3}" -f $L, $Label, (Format-Size ([int64]$Disk.FreeSpace)), (Format-Size ([int64]$Disk.Size)))
    }

    $Default = if ($Letters -contains $Drive) { $Drive } else { $Letters[0] }
    $Answer  = Read-Host "`n请输入目标盘符(直接回车默认 $Default)"
    $Pick    = if ([string]::IsNullOrWhiteSpace($Answer)) { $Default } else { $Answer.Trim().TrimEnd(':').ToUpper() }

    if ($Letters -notcontains $Pick) {
        Write-Host "无效的盘符:$Pick" -ForegroundColor Red
        return $null
    }
    return $Pick
}

function Get-DirSize([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return [int64]0 }
    $Sum = (Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
    if ($null -eq $Sum) { return [int64]0 }
    return [int64]$Sum
}

function Format-Size([int64]$Bytes) {
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N1} MB" -f ($Bytes / 1MB) }
    return "{0:N0} KB" -f ($Bytes / 1KB)
}

# 读取注册表中某文件夹当前的实际路径
function Get-CurrentFolderPath([string]$RegName, [string]$FolderName) {
    $Props = Get-ItemProperty -Path $RegPath -ErrorAction SilentlyContinue
    $Prop  = if ($Props) { $Props.PSObject.Properties[$RegName] } else { $null }
    if ($Prop -and $Prop.Value) {
        return [Environment]::ExpandEnvironmentVariables([string]$Prop.Value)
    }
    return Join-Path $env:USERPROFILE $FolderName
}

# 清空目录内容(保留目录本身);遇到目录联接/符号链接只删除链接,不会跟进删除目标内容
function Remove-FolderContents([string]$Path) {
    Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $Item = $_
        if ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            cmd.exe /c "rmdir `"$($Item.FullName)`"" 2>$null | Out-Null
            if (Test-Path -LiteralPath $Item.FullName) {
                cmd.exe /c "del /f /q `"$($Item.FullName)`"" 2>$null | Out-Null
            }
        }
        elseif ($Item.PSIsContainer) {
            cmd.exe /c "rmdir /s /q `"$($Item.FullName)`"" 2>$null | Out-Null
        }
        else {
            Remove-Item -LiteralPath $Item.FullName -Force -ErrorAction SilentlyContinue
        }
    }
}

# ==========================================
# 1. 迁移用户文件夹
# ==========================================

function Move-UserFolders {

    $MoveDrive = Select-TargetDrive
    if (-not $MoveDrive) { return }
    if (-not (Test-TargetDrive $MoveDrive)) { return }
    $MoveRoot = "${MoveDrive}:\Users\$env:USERNAME"

    $Selected = [ordered]@{}
    foreach ($Entry in $CoreFolders.GetEnumerator()) { $Selected[$Entry.Key] = $Entry.Value }

    Write-Host "`n目标目录:$MoveRoot" -ForegroundColor Cyan
    Write-Host "将迁移:$($CoreFolders.Values -join '、')"

    $IncludeExtra = Read-Host "`n是否同时迁移不常用文件夹($($ExtraFolders.Values -join '、'))?[y/N]"
    if ($IncludeExtra -match '^[Yy]') {
        foreach ($Entry in $ExtraFolders.GetEnumerator()) { $Selected[$Entry.Key] = $Entry.Value }
    }

    # 空间检查
    $Need = [int64]0
    foreach ($Entry in $Selected.GetEnumerator()) {
        $Src  = Get-CurrentFolderPath $Entry.Key $Entry.Value
        $Dest = Join-Path $MoveRoot $Entry.Value
        if ($Src -ine $Dest) { $Need += Get-DirSize $Src }
    }
    $Free = [int64](Get-PSDrive -Name $MoveDrive).Free
    Write-Host "`n需要空间:$(Format-Size $Need)    $MoveDrive 盘可用:$(Format-Size $Free)"
    if ($Need -gt $Free) {
        Write-Host "目标盘空间不足!" -ForegroundColor Red
        return
    }

    Write-Host "说明:文件会被【移动】到新位置(先复制并校验,校验通过后才删除原文件;失败则保留原文件)。" -ForegroundColor Yellow
    if (-not (Confirm-Yes "确认开始迁移")) {
        Write-Host "已取消。" -ForegroundColor Yellow
        return
    }

    New-Item -ItemType Directory -Path $MoveRoot -Force | Out-Null

    $Done = 0; $Skipped = 0; $Failed = 0

    foreach ($Entry in $Selected.GetEnumerator()) {

        $RegName     = $Entry.Key
        $FolderName  = $Entry.Value
        $Source      = Get-CurrentFolderPath $RegName $FolderName
        $Destination = Join-Path $MoveRoot $FolderName

        Write-Host "`n正在处理:$FolderName" -ForegroundColor Cyan

        if ($Source -ieq $Destination) {
            Write-Host "已在目标位置,跳过。" -ForegroundColor DarkGray
            $Skipped++
            continue
        }

        New-Item -ItemType Directory -Path $Destination -Force | Out-Null

        if (Test-Path -LiteralPath $Source) {
            robocopy.exe $Source $Destination /E /COPY:DAT /DCOPY:DAT /R:2 /W:2 /XJ /NFL /NDL /NP /NJH
            if ($LASTEXITCODE -ge 8) {
                Write-Host "复制失败(robocopy 代码 $LASTEXITCODE),跳过路径修改:$FolderName" -ForegroundColor Red
                $Failed++
                continue
            }
        }

        # 校验:再做一次只列出不复制的比对,0=完全一致,2=目标多出额外文件,均视为安全
        $Verified = $true
        if (Test-Path -LiteralPath $Source) {
            robocopy.exe $Source $Destination /E /L /XJ /NFL /NDL /NP /NJH /NJS | Out-Null
            if (@(0, 2) -notcontains $LASTEXITCODE) { $Verified = $false }
        }

        # 只修改 User Shell Folders;Shell Folders 是系统缓存,由系统自动刷新
        Set-ItemProperty -Path $RegPath -Name $RegName -Value $Destination -Type ExpandString

        if (-not $Verified) {
            Write-Host "校验发现差异(可能有文件在复制期间被修改),已保留原目录:$Source" -ForegroundColor Yellow
        }
        elseif (Test-Path -LiteralPath $Source) {
            Remove-FolderContents $Source
            $Left = @(Get-ChildItem -LiteralPath $Source -Force -ErrorAction SilentlyContinue).Count
            if ($Left -gt 0) {
                Write-Host "原目录仍有 $Left 项被占用未能删除,重启后可手动清理:$Source" -ForegroundColor Yellow
            }
        }

        Write-Host "完成:$Destination" -ForegroundColor Green
        $Done++
    }

    Write-Host "`n结果:成功 $Done,跳过 $Skipped,失败 $Failed" -ForegroundColor Cyan
    if ($Done -gt 0) {
        Write-Host "请【注销或重启】Windows 使设置生效。" -ForegroundColor Yellow
    }
}

# ==========================================
# 2. 查看当前用户文件夹路径
# ==========================================

function Show-UserFolders {

    Write-Host "`n当前用户文件夹路径" -ForegroundColor Cyan
    Write-Host "========================================"

    $All = [ordered]@{}
    foreach ($Entry in $CoreFolders.GetEnumerator())  { $All[$Entry.Key] = $Entry.Value }
    foreach ($Entry in $ExtraFolders.GetEnumerator()) { $All[$Entry.Key] = $Entry.Value }

    foreach ($Entry in $All.GetEnumerator()) {
        $Value = Get-CurrentFolderPath $Entry.Key $Entry.Value
        Write-Host ("{0,-14} {1}" -f $Entry.Value, $Value)
    }
}

# ==========================================
# 3. 恢复用户文件夹默认路径
# ==========================================

function Restore-UserFolders {

    Write-Host "`n恢复用户文件夹路径到默认位置(%USERPROFILE%\xxx)" -ForegroundColor Cyan
    Write-Host "注意:仅修改路径指向,不会把文件从当前位置搬回 C 盘,需要请自行复制。" -ForegroundColor Yellow

    if (-not (Confirm-Yes "确认恢复")) {
        Write-Host "已取消。" -ForegroundColor Yellow
        return
    }

    $All = [ordered]@{}
    foreach ($Entry in $CoreFolders.GetEnumerator())  { $All[$Entry.Key] = $Entry.Value }
    foreach ($Entry in $ExtraFolders.GetEnumerator()) { $All[$Entry.Key] = $Entry.Value }

    foreach ($Entry in $All.GetEnumerator()) {
        $Default = "%USERPROFILE%\$($Entry.Value)"
        Set-ItemProperty -Path $RegPath -Name $Entry.Key -Value $Default -Type ExpandString
        Write-Host "已恢复:$($Entry.Value) -> $Default" -ForegroundColor Green
    }

    Write-Host "`n请注销或重启 Windows 使设置生效。" -ForegroundColor Yellow
}

# ==========================================
# 4. 创建软件安装目录(仅创建目录)
# ==========================================

function Set-SoftwareLocation {

    Write-Host "`n创建软件安装目录(仅创建目录,不修改系统安装路径)" -ForegroundColor Cyan

    if (-not (Test-TargetDrive)) { return }

    foreach ($Path in @("${Drive}:\Program Files", "${Drive}:\Program Files (x86)")) {
        try {
            if (-not (Test-Path -LiteralPath $Path)) {
                New-Item -ItemType Directory -Path $Path -Force -ErrorAction Stop | Out-Null
            }
            Write-Host "已就绪:$Path" -ForegroundColor Green
        }
        catch {
            Write-Host "创建失败:$Path - $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Write-Host "`n安装软件时请手动选择上述目录。" -ForegroundColor Yellow
}

# ==========================================
# 5. 修改 Windows 新内容保存位置
# ==========================================

function Set-WindowsSaveLocation {

    Write-Host "`n正在打开 Windows 存储设置..." -ForegroundColor Cyan

    try {
        Start-Process "ms-settings:savelocations"
        Write-Host "`n请在设置中将以下项目改为 $Drive 盘:" -ForegroundColor Yellow
        Write-Host "  新应用 / 新文档 / 新音乐 / 新照片和视频"
    }
    catch {
        Write-Host "打开设置失败:$($_.Exception.Message)" -ForegroundColor Red
    }
}

# ==========================================
# 6. 修改临时文件目录
# ==========================================

function Set-TempLocation {

    if (-not (Test-TargetDrive)) { return }

    $UserTemp   = "${Drive}:\Temp\$env:USERNAME"
    $SystemTemp = "${Drive}:\Temp\System"

    Write-Host "`n用户 TEMP/TMP -> $UserTemp" -ForegroundColor Cyan
    if (-not (Confirm-Yes "确认修改用户 TEMP")) {
        Write-Host "已取消。" -ForegroundColor Yellow
        return
    }

    New-Item -ItemType Directory -Path $UserTemp -Force | Out-Null
    [Environment]::SetEnvironmentVariable("TEMP", $UserTemp, "User")
    [Environment]::SetEnvironmentVariable("TMP",  $UserTemp, "User")
    $env:TEMP = $UserTemp
    $env:TMP  = $UserTemp
    Write-Host "用户 TEMP/TMP 已修改。" -ForegroundColor Green

    # 系统级:高风险,单独确认
    Write-Host "`n【高级/高风险】系统 TEMP/TMP -> $SystemTemp" -ForegroundColor Red
    Write-Host "若 $Drive 盘开机时未就绪,系统服务和安装程序可能异常。多数用户无需修改。" -ForegroundColor Yellow

    if (-not (Test-Admin)) {
        Write-Host "当前非管理员,跳过系统级修改。" -ForegroundColor DarkGray
    }
    elseif (Confirm-Yes "确认同时修改【系统级】TEMP") {
        New-Item -ItemType Directory -Path $SystemTemp -Force | Out-Null
        [Environment]::SetEnvironmentVariable("TEMP", $SystemTemp, "Machine")
        [Environment]::SetEnvironmentVariable("TMP",  $SystemTemp, "Machine")
        Write-Host "系统 TEMP/TMP 已修改。" -ForegroundColor Green
    }

    Write-Host "`n请重启 Windows 使环境变量完全生效。" -ForegroundColor Yellow
}

# ==========================================
# 7. 清理临时文件
# ==========================================

function Clear-TempFiles {

    Write-Host "`n清理临时文件" -ForegroundColor Cyan

    $Paths = @($env:TEMP)
    if (Test-Admin) {
        $Paths += "$env:WINDIR\Temp"
    }
    else {
        Write-Host "提示:非管理员,不清理 $env:WINDIR\Temp。" -ForegroundColor DarkGray
    }
    $Paths = $Paths | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique

    foreach ($Path in $Paths) {
        Write-Host "将清理:$Path"
    }
    Write-Host "(正在被占用的文件会自动跳过)" -ForegroundColor DarkGray

    if (-not (Confirm-Yes "确认清理")) {
        Write-Host "已取消。" -ForegroundColor Yellow
        return
    }

    foreach ($Path in $Paths) {

        Write-Host "`n正在清理:$Path" -ForegroundColor Cyan
        $Before = Get-DirSize $Path

        Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue |
            ForEach-Object {
                Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }

        $After = Get-DirSize $Path
        Write-Host "完成,释放约 $(Format-Size ($Before - $After))" -ForegroundColor Green
    }
}

# ==========================================
# 8. 查看 Windows 激活状态
# ==========================================

function Show-ActivationStatus {

    Write-Host "`n正在查询 Windows 激活状态..." -ForegroundColor Cyan

    $StatusMap = @{
        0 = "未授权"
        1 = "已激活"
        2 = "初始宽限期"
        3 = "额外宽限期"
        4 = "非正版宽限期"
        5 = "通知状态(未激活)"
        6 = "扩展宽限期"
    }

    try {
        $Product = Get-CimInstance SoftwareLicensingProduct -ErrorAction Stop |
            Where-Object {
                $_.ApplicationId -eq "55c92734-d682-4d71-983e-d6ec3f16059f" -and
                $_.PartialProductKey
            } | Select-Object -First 1
    }
    catch {
        Write-Host "查询失败:$($_.Exception.Message)" -ForegroundColor Red
        return
    }

    if (-not $Product) {
        Write-Host "未找到已安装产品密钥的 Windows 授权信息。" -ForegroundColor Yellow
        return
    }

    $Status = $StatusMap[[int]$Product.LicenseStatus]
    $Color  = if ($Product.LicenseStatus -eq 1) { "Green" } else { "Yellow" }
    $Os     = (Get-CimInstance Win32_OperatingSystem).Caption

    Write-Host "========================================"
    Write-Host ("系统版本    {0}" -f $Os)
    Write-Host ("授权产品    {0}" -f $Product.Name)
    Write-Host ("密钥后五位  {0}" -f $Product.PartialProductKey)
    Write-Host ("授权渠道    {0}" -f $Product.ProductKeyChannel)
    Write-Host "激活状态    " -NoNewline
    Write-Host $Status -ForegroundColor $Color
    Write-Host "========================================"

    # 到期信息(永久激活会显示"永久激活")
    Write-Host "`n到期信息:" -ForegroundColor Cyan
    cscript.exe //nologo "$env:WINDIR\System32\slmgr.vbs" /xpr
}

# ==========================================
# 9. 激活 Windows
# ==========================================

function Activate-Windows {

    Write-Host "`n正在启动 Microsoft Activation Scripts..." -ForegroundColor Yellow

    try {
        irm https://get.activated.win | iex
    }
    catch {
        Write-Host "启动失败：$($_.Exception.Message)" -ForegroundColor Red
    }
}

# ==========================================
# 菜单
# ==========================================

# 子菜单定义:每组包含标题和若干项目(文字 + 动作)
$MenuGroups = @(
    @{
        Title = "用户文件夹"
        Summary = "迁移用户文件夹(可选择目标盘 / 可一定程度改善C盘存储空间) / 查看当前路径 / 恢复默认路径"
        Items = @(
            @{ Text = "迁移用户文件夹(可选择目标盘 / 可一定程度改善C盘存储空间)"; Action = { Move-UserFolders } }
            @{ Text = "查看当前用户文件夹路径";                                   Action = { Show-UserFolders } }
            @{ Text = "恢复用户文件夹默认路径";                                   Action = { Restore-UserFolders } }
        )
    }
    @{
        Title = "软件与存储位置"
        Summary = "创建软件安装目录 / 打开新内容保存位置设置 / 修改临时文件目录"
        Items = @(
            @{ Text = "创建软件安装目录(仅创建目录)";     Action = { Set-SoftwareLocation } }
            @{ Text = "打开 Windows 新内容保存位置设置";   Action = { Set-WindowsSaveLocation } }
            @{ Text = "修改临时文件目录";                 Action = { Set-TempLocation } }
        )
    }
    @{
        Title = "清理与系统"
        Summary = "清理临时文件 / 激活Windows & Office / 查看 Windows 激活状态"
        Items = @(
            @{ Text = "清理临时文件";             Action = { Clear-TempFiles } }
            @{ Text = "激活Windows & Office";     Action = { Activate-Windows } }
            @{ Text = "查看 Windows 激活状态";    Action = { Show-ActivationStatus } }
        )
    }
)

function Write-MenuTitle([string]$Title) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}

function Invoke-MenuAction([scriptblock]$Action) {
    try {
        & $Action
    }
    catch {
        Write-Host "`n发生错误:$($_.Exception.Message)" -ForegroundColor Red
    }
    Pause-Menu
}

function Show-SubMenu($Group) {

    while ($true) {

        Clear-Host
        Write-MenuTitle ("Windows 工具箱 > " + $Group.Title)
        Write-Host ""

        for ($n = 0; $n -lt $Group.Items.Count; $n++) {
            Write-Host ("  [{0}] {1}" -f ($n + 1), $Group.Items[$n].Text)
        }

        Write-Host ""
        Write-Host "  [0] 返回上级"
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan

        $Choice = (Read-Host "请输入选项").Trim()

        if ($Choice -eq "0") { return }

        $Index = 0
        if ([int]::TryParse($Choice, [ref]$Index) -and $Index -ge 1 -and $Index -le $Group.Items.Count) {
            Invoke-MenuAction $Group.Items[$Index - 1].Action
        }
        else {
            Write-Host "`n无效选项!" -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}

function Show-MainMenu {

    Clear-Host

    $IsAdmin    = Test-Admin
    $AdminText  = if ($IsAdmin) { "管理员" } else { "普通用户" }
    $AdminColor = if ($IsAdmin) { "Green" } else { "Yellow" }

    Write-MenuTitle "Windows 工具箱"
    Write-Host "  目标盘:$Drive    权限:" -NoNewline
    Write-Host $AdminText -ForegroundColor $AdminColor
    Write-Host ""

    for ($n = 0; $n -lt $MenuGroups.Count; $n++) {
        Write-Host ("  [{0}] {1}" -f ($n + 1), $MenuGroups[$n].Title)
        Write-Host ("        {0}" -f $MenuGroups[$n].Summary) -ForegroundColor DarkGray
    }

    if (-not $IsAdmin) {
        Write-Host ""
        Write-Host "  [A] 以管理员身份重新运行"
    }
    Write-Host ""
    Write-Host "  [0] 退出"
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan

    $Choice = (Read-Host "请输入选项").Trim().ToUpper()

    if ($Choice -eq "0") { return $false }

    if ($Choice -eq "A" -and -not $IsAdmin) {
        Restart-AsAdmin
        Pause-Menu
        return $true
    }

    $Index = 0
    if ([int]::TryParse($Choice, [ref]$Index) -and $Index -ge 1 -and $Index -le $MenuGroups.Count) {
        Show-SubMenu $MenuGroups[$Index - 1]
    }
    else {
        Write-Host "`n无效选项!" -ForegroundColor Red
        Start-Sleep -Seconds 1
    }

    return $true
}

# ==========================================
# 启动
# ==========================================

while (Show-MainMenu) { }
