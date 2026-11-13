#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateRange(1, 100)]
    [int]$ReleaseLimit = 10,

    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'Programs\Rotorflight Tools'),

    [string]$HelixInstaller = '',

    [switch]$Help
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Apps = [ordered]@{
    configurator = @{
        Name = 'Rotorflight Configurator'
        Repo = 'rotorflight/rotorflight-configurator'
        Asset = 'rotorflight-configurator_[^/]+_win_x86_64\.zip$'
        Directory = 'Rotorflight Configurator'
        Executable = 'rotorflight-configurator.exe'
        Kind = 'Portable'
    }
    blackbox = @{
        Name = 'Rotorflight Blackbox'
        Repo = 'rotorflight/rotorflight-blackbox'
        Asset = 'rotorflight-blackbox-installer_[^/]+_win64\.exe$'
        Kind = 'Installer'
    }
    expresslrs = @{
        Name = 'ExpressLRS Configurator'
        Repo = 'ExpressLRS/ExpressLRS-Configurator'
        Asset = 'ExpressLRS-Configurator-Setup-[^/]+\.exe$'
        Kind = 'Installer'
    }
    blackbox_lab = @{
        Name = 'Blackbox Lab'
        Repo = 'hillbilly1975/Blackbox_Lab'
        Asset = 'Blackbox\.Lab-win32-x64-[^/]+\.zip$'
        Directory = 'Blackbox Lab'
        Executable = 'Blackbox Lab.exe'
        Kind = 'Portable'
    }
    radio_updater = @{
        Name = 'Rotorflight Radio Updater'
        Repo = 'rotorflight/rotorflight-lua-edgetx-updater'
        Asset = 'rotorflight-lua-edgetx-updater-[^/]+-windows-x64\.zip$'
        Directory = 'Rotorflight Radio Updater'
        Executable = 'rotorflight-lua-edgetx-updater.exe'
        Kind = 'Portable'
    }
}

function Show-Help {
    @'
Rotorflight Tools Installer for Windows

Installs or updates:
  - Rotorflight Configurator
  - Rotorflight Blackbox
  - ExpressLRS Configurator
  - Blackbox Lab
  - Rotorflight Radio Updater
  - HELI-X 11

Usage:
  powershell -ExecutionPolicy Bypass -File .\bin\rotorflight-tools-installer.ps1
  .\bin\rotorflight-tools-installer.ps1 -ReleaseLimit 20
  .\bin\rotorflight-tools-installer.ps1 -HelixInstaller C:\Downloads\setupHeli-X11_win64.exe

Portable applications are installed per user under:
  %LOCALAPPDATA%\Programs\Rotorflight Tools

Options:
  -ReleaseLimit N       Number of recent GitHub releases to query (default: 10)
  -InstallRoot PATH     Destination for portable applications
  -HelixInstaller PATH  Use a previously downloaded HELI-X installer
  -Help                 Show this help

Windows USB/DFU drivers are managed by each application or by Windows. There are
no udev rules on Windows.
'@
}

function Get-GitHubReleases([string]$Repository) {
    $headers = @{
        Accept = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
        'User-Agent' = 'rotorflight-tools-installer'
    }
    $uri = "https://api.github.com/repos/$Repository/releases?per_page=$ReleaseLimit"
    Invoke-RestMethod -Uri $uri -Headers $headers
}

function Get-CompatibleReleases([string]$AppId) {
    $app = $Apps[$AppId]
    Write-Host "`nFetching $($app.Name) releases..."
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($release in (Get-GitHubReleases $app.Repo)) {
        $asset = $release.assets | Where-Object { $_.name -match $app.Asset } | Select-Object -First 1
        if ($asset) {
            $rows.Add([pscustomobject]@{
                Tag = $release.tag_name
                Name = $release.name
                Published = [datetime]$release.published_at
                Prerelease = [bool]$release.prerelease
                AssetName = $asset.name
                Url = $asset.browser_download_url
            })
        }
    }
    return $rows
}

function Select-Release([string]$AppId, [switch]$LatestStable) {
    $app = $Apps[$AppId]
    $releases = @(Get-CompatibleReleases $AppId)
    if ($releases.Count -eq 0) {
        throw "No compatible Windows x64 asset found for $($app.Name)."
    }
    if ($LatestStable) {
        $selected = $releases | Where-Object { -not $_.Prerelease } | Select-Object -First 1
        if (-not $selected) { throw "No stable Windows release found for $($app.Name)." }
        Write-Host "Automatically selected: $($selected.Tag) ($($selected.AssetName))"
        return $selected
    }

    Write-Host "`nAvailable releases:"
    for ($index = 0; $index -lt $releases.Count; $index++) {
        $release = $releases[$index]
        $status = if ($release.Prerelease) { 'pre-release' } else { 'stable' }
        Write-Host ('  {0,2}) {1,-24} {2,-12} {3:yyyy-MM-dd}' -f ($index + 1), $release.Tag, $status, $release.Published)
        Write-Host "      $($release.AssetName)"
    }
    Write-Host '   q) Cancel'
    while ($true) {
        $choice = Read-Host "Choose the release for $($app.Name) [1]"
        if ([string]::IsNullOrWhiteSpace($choice)) { $choice = '1' }
        if ($choice -match '^[qQ]$') { return $null }
        $number = 0
        if ([int]::TryParse($choice, [ref]$number) -and $number -ge 1 -and $number -le $releases.Count) {
            return $releases[$number - 1]
        }
        Write-Warning "Enter a number between 1 and $($releases.Count), or q to cancel."
    }
}

function Save-Download([string]$Url, [string]$Destination) {
    Write-Host "Downloading $(Split-Path $Destination -Leaf)..."
    $oldProgress = $ProgressPreference
    $ProgressPreference = 'Continue'
    try {
        Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
    }
    finally {
        $ProgressPreference = $oldProgress
    }
}

function Find-Executable([string]$Root, [string]$Name) {
    Get-ChildItem -Path $Root -Filter $Name -File -Recurse | Select-Object -First 1
}

function New-AppShortcut([hashtable]$App, [string]$ExecutablePath) {
    $shell = New-Object -ComObject WScript.Shell
    $startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Rotorflight Tools'
    $desktop = [Environment]::GetFolderPath('Desktop')
    New-Item -ItemType Directory -Path $startMenu -Force | Out-Null
    foreach ($shortcutPath in @(
        (Join-Path $startMenu "$($App.Name).lnk"),
        (Join-Path $desktop "$($App.Name).lnk")
    )) {
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $ExecutablePath
        $shortcut.WorkingDirectory = Split-Path $ExecutablePath -Parent
        $shortcut.IconLocation = "$ExecutablePath,0"
        $shortcut.Save()
    }
}

function Install-PortableApp([string]$AppId, $Release) {
    $app = $Apps[$AppId]
    $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("rotorflight-tools-" + [guid]::NewGuid())
    $archive = Join-Path $temp $Release.AssetName
    $extract = Join-Path $temp 'extract'
    $destination = Join-Path $InstallRoot $app.Directory
    try {
        New-Item -ItemType Directory -Path $extract -Force | Out-Null
        Save-Download $Release.Url $archive
        Write-Host 'Extracting...'
        Expand-Archive -LiteralPath $archive -DestinationPath $extract -Force
        $executable = Find-Executable $extract $app.Executable
        if (-not $executable) { throw "Executable $($app.Executable) was not found in $($Release.AssetName)." }
        $payload = $executable.Directory.FullName

        New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
        if (Test-Path $destination) {
            $backup = "$destination.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Move-Item -LiteralPath $destination -Destination $backup
            Write-Host "Backup created at $backup"
        }
        Move-Item -LiteralPath $payload -Destination $destination
        $installedExe = Join-Path $destination $app.Executable
        New-AppShortcut $app $installedExe
        Write-Host "$($app.Name) installed/updated to $($Release.Tag)."
    }
    finally {
        if (Test-Path $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
    }
}

function Install-Exe([string]$Name, [string]$Url, [string]$FileName) {
    $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("rotorflight-tools-" + [guid]::NewGuid())
    $installer = Join-Path $temp $FileName
    try {
        New-Item -ItemType Directory -Path $temp -Force | Out-Null
        Save-Download $Url $installer
        Write-Host "Starting $Name installer..."
        $process = Start-Process -FilePath $installer -Wait -PassThru
        if ($process.ExitCode -ne 0) { throw "$Name installer exited with code $($process.ExitCode)." }
        Write-Host "$Name installer completed."
    }
    finally {
        if (Test-Path $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
    }
}

function Install-GitHubApp([string]$AppId, [switch]$LatestStable) {
    $app = $Apps[$AppId]
    $release = Select-Release $AppId -LatestStable:$LatestStable
    if (-not $release) { return }
    $portable = $app.Kind -eq 'Portable'
    $receiptDirectory = if ($portable) { Join-Path $InstallRoot $app.Directory } else { Join-Path $InstallRoot '.releases' }
    $receiptName = if ($portable) { '.rotorflight-release.json' } else { ".rotorflight-release-$AppId.json" }
    $receipt = Join-Path $receiptDirectory $receiptName
    if ($script:UpdateOnly) {
        $installed = $null
        if (Test-Path -LiteralPath $receipt) {
            try { $installed = Get-Content -LiteralPath $receipt -Raw | ConvertFrom-Json } catch { $installed = $null }
        }
        $missingPortable = $portable -and -not (Test-Path -LiteralPath (Join-Path $receiptDirectory $app.Executable) -PathType Leaf)
        if (-not $missingPortable) {
            $installedDate = [datetime]::MinValue
            if (-not $installed.Tag -or -not [datetime]::TryParse([string]$installed.Published, [ref]$installedDate)) {
                Write-Host "$($app.Name): unknown installed version; skipped. Install once using options 1-9 to register it."
                return
            }
            if ($installed.Tag -eq $release.Tag -or $installedDate -ge $release.Published) {
                Write-Host "$($app.Name): $($installed.Tag) is current or newer; skipped."
                return
            }
        }
    }
    if ($app.Kind -eq 'Portable') {
        Install-PortableApp $AppId $release
    }
    else {
        Install-Exe $app.Name $release.Url $release.AssetName
        Write-Host "$($app.Name) installed/updated to $($release.Tag)."
    }
    New-Item -ItemType Directory -Path $receiptDirectory -Force | Out-Null
    @{ Tag = $release.Tag; Published = $release.Published.ToUniversalTime().ToString('o') } |
        ConvertTo-Json | Set-Content -LiteralPath $receipt -Encoding UTF8
}

function Install-Helix {
    if ($script:UpdateOnly) {
        Write-Host 'HELI-X: automatic version check unavailable; use the in-app updater.'
        return
    }
    if ($HelixInstaller) {
        if (-not (Test-Path -LiteralPath $HelixInstaller -PathType Leaf)) {
            throw "HELI-X installer not found: $HelixInstaller"
        }
        Write-Host 'Starting local HELI-X 11 installer...'
        $process = Start-Process -FilePath (Resolve-Path $HelixInstaller) -Wait -PassThru
        if ($process.ExitCode -ne 0) { throw "HELI-X installer exited with code $($process.ExitCode)." }
        return
    }
    $isArm64 = $env:PROCESSOR_ARCHITECTURE -eq 'ARM64'
    $file = if ($isArm64) { 'setupHeli-X11_arm64.exe' } else { 'setupHeli-X11_win64.exe' }
    Install-Exe 'HELI-X 11' "https://www.heli-x.info/2675/$file" $file
}

function Show-UsbDriverInfo {
    Write-Host @'

Windows USB/DFU note:
  Windows does not use udev rules. If DFU flashing is not detected, install the
  STM32 bootloader/WinUSB driver recommended by Rotorflight and reconnect the
  flight controller. Normal virtual COM ports are usually installed by Windows.
'@
}

function Select-Apps {
    Write-Host @'

What do you want to install/update?
  1) Rotorflight Configurator
  2) Rotorflight Blackbox
  3) ExpressLRS Configurator
  4) Rotorflight Configurator + Blackbox (default)
  5) Show Windows USB/DFU driver information
  6) HELI-X 11
  7) Rotorflight Radio Updater (EdgeTX/OpenTX)
  8) Blackbox Lab
  9) All - latest stable version, no release prompt
  10) Update all - install only newer stable releases
  q) Quit
'@
    $choice = Read-Host 'Choose [4 - Rotorflight Configurator + Blackbox]'
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = '4' }
    switch -Regex ($choice) {
        '^1$' { return ,@('configurator') }
        '^2$' { return ,@('blackbox') }
        '^3$' { return ,@('expresslrs') }
        '^4$' { return ,@('configurator', 'blackbox') }
        '^5$' { return ,@('drivers') }
        '^6$' { return ,@('helix') }
        '^7$' { return ,@('radio_updater') }
        '^8$' { return ,@('blackbox_lab') }
        '^9$' { $script:AutoStable = $true; return ,@('configurator', 'blackbox', 'expresslrs', 'blackbox_lab', 'radio_updater', 'helix') }
        '^10$' { $script:AutoStable = $true; $script:UpdateOnly = $true; return ,@('configurator', 'blackbox', 'expresslrs', 'blackbox_lab', 'radio_updater', 'helix') }
        '^[qQ]$' { return @() }
        default { Write-Warning 'Invalid option.'; return $null }
    }
}

if ($Help) { Show-Help; exit 0 }
if (-not $env:LOCALAPPDATA -or -not $env:APPDATA) {
    throw 'This script must be run on Windows with LOCALAPPDATA and APPDATA available.'
}

Write-Host 'Rotorflight Tools Installer for Windows'
Write-Host "Portable application directory: $InstallRoot"
$AutoStable = $false
do { $selectedApps = Select-Apps } while ($null -eq $selectedApps)
foreach ($appId in $selectedApps) {
    switch ($appId) {
        'drivers' { Show-UsbDriverInfo }
        'helix' { Install-Helix }
        default { Install-GitHubApp $appId -LatestStable:$AutoStable }
    }
}
Write-Host "`nDone."
