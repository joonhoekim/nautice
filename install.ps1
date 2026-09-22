#Requires -Version 5.1
<#
.SYNOPSIS
    Installs nautice (Windows). macOS / Linux: install.sh.
.DESCRIPTION
    docs/install.md is the contract for both; change them together.

      irm https://raw.githubusercontent.com/joonhoekim/nautice/main/install.ps1 | iex
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$Repo   = 'joonhoekim/nautice'
$Asset  = 'nautice-windows.zip'

function Get-EnvOr($name, $fallback) {
    $v = [Environment]::GetEnvironmentVariable($name)
    if ([string]::IsNullOrWhiteSpace($v)) { return $fallback }
    return $v
}

function Say($msg)  { Write-Output "nautice: $msg" }
function Die($msg)  { [Console]::Error.WriteLine("nautice: $msg"); exit 1 }

# Build the default only when NAUTICE_PREFIX is unset; as an argument, Join-Path
# would run first and fail where %LOCALAPPDATA% does not exist.
$Prefix = Get-EnvOr 'NAUTICE_PREFIX' ''
if (-not $Prefix) {
    if (-not $env:LOCALAPPDATA) { Die '%LOCALAPPDATA% 가 없다. NAUTICE_PREFIX 로 설치 위치를 지정하라' }
    $Prefix = [IO.Path]::Combine($env:LOCALAPPDATA, 'Programs', 'nautice')
}
$Version = Get-EnvOr 'NAUTICE_VERSION' 'latest'
$Archive = Get-EnvOr 'NAUTICE_ARCHIVE' ''
$BinDir  = Join-Path $Prefix 'bin'

# Under irm | iex there is no $args or $PSCommandPath; everything comes from
# environment variables.

# ── PATH ────────────────────────────────────────────────────────────────────
# The user PATH is a registry value: no file parsing, easy to add and remove
# without duplicates. Windows has no ~/.local/bin convention, so without it new
# shells would not find nautice.
function Split-UserPath {
    $raw = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $raw) { return @() }
    return @($raw -split ';' | Where-Object { $_ })
}

function Add-UserPath($dir) {
    $parts = Split-UserPath
    $norm  = $dir.TrimEnd('\')
    if ($parts | Where-Object { $_.TrimEnd('\') -eq $norm }) { return $false }
    [Environment]::SetEnvironmentVariable('Path', (($parts + $dir) -join ';'), 'User')
    return $true
}

function Remove-UserPath($dir) {
    $norm  = $dir.TrimEnd('\')
    $kept  = @(Split-UserPath | Where-Object { $_.TrimEnd('\') -ne $norm })
    [Environment]::SetEnvironmentVariable('Path', ($kept -join ';'), 'User')
}

# ── Uninstall ───────────────────────────────────────────────────────────────
if ((Get-EnvOr 'NAUTICE_UNINSTALL' '') -eq '1') {
    # Leave $Prefix itself: it may be shared with other software.
    foreach ($f in @('nautice', 'nautice.ps1', 'nautice.cmd')) {
        Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $BinDir $f)
    }
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue ([IO.Path]::Combine($Prefix, 'share', 'nautice'))
    Remove-UserPath $BinDir
    Say "지웠다: $Prefix (PATH 항목도 뺐다)"
    exit 0
}

# ── Download ────────────────────────────────────────────────────────────────
# Invoke-WebRequest -OutFile keeps bytes. irm decodes to a string, which strips
# nautice.ps1's UTF-8 BOM and corrupts .wav — hence one zip, not loose files.
function Get-File($url, $dest) {
    try {
        $old = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        try { Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing }
        finally { $ProgressPreference = $old }
    } catch { Die "못 받았다: $url ($($_.Exception.Message))" }
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("nautice." + [IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
    $zip = Join-Path $tmp $Asset
    if ($Archive) {
        # Lets CI exercise the real install path without a release.
        if (Test-Path -LiteralPath $Archive -PathType Leaf) { Copy-Item -LiteralPath $Archive $zip }
        else { Get-File $Archive $zip }
        Say "아카이브: $Archive (해시 검증 건너뜀)"
    } else {
        $base = if ($Version -eq 'latest') { "https://github.com/$Repo/releases/latest/download" }
                else                       { "https://github.com/$Repo/releases/download/$Version" }
        Say "받는 중: $base/$Asset"
        Get-File "$base/$Asset" $zip
        $sums = Join-Path $tmp 'SHA256SUMS'
        Get-File "$base/SHA256SUMS" $sums

        $want = $null
        foreach ($line in Get-Content $sums) {
            $f = $line -split '\s+'
            if ($f.Count -ge 2 -and $f[1] -eq $Asset) { $want = $f[0] }
        }
        if (-not $want) { Die "SHA256SUMS 에 $Asset 이 없다" }
        $got = (Get-FileHash -Algorithm SHA256 -LiteralPath $zip).Hash.ToLower()
        if ($got -ne $want.ToLower()) { Die "해시가 다르다 (기대 $want, 실제 $got)" }
        Say '해시 확인됨'
    }

    # ── Extract and copy ────────────────────────────────────────────────────
    $out = Join-Path $tmp 'x'
    try { Expand-Archive -LiteralPath $zip -DestinationPath $out -Force }
    catch { Die "아카이브를 못 풀었다 (받다 끊겼을 수 있다): $($_.Exception.Message)" }

    $src = Get-ChildItem -Directory $out | Where-Object { $_.Name -like 'nautice-*' } | Select-Object -First 1
    if (-not $src) { Die '아카이브 안에 nautice-* 디렉터리가 없다' }
    $srcBin = Join-Path $src.FullName 'bin'
    if (-not (Test-Path (Join-Path $srcBin 'nautice.ps1'))) { Die '아카이브 안에 bin/nautice.ps1 이 없다' }

    $soundDir = [IO.Path]::Combine($Prefix, 'share', 'nautice', 'sounds')
    New-Item -ItemType Directory -Path $BinDir   -Force | Out-Null
    New-Item -ItemType Directory -Path $soundDir -Force | Out-Null
    Copy-Item -Force (Join-Path $srcBin '*') $BinDir
    Copy-Item -Force ([IO.Path]::Combine($src.FullName, 'share', 'nautice', 'sounds', '*.wav')) $soundDir

    # Installed means the installed copy runs. doctor's exit code reflects missing
    # backends, not a failed install, so it is not checked.
    $ps1 = Join-Path $BinDir 'nautice.ps1'
    $ver = & $ps1 --version
    if ($LASTEXITCODE -ne 0 -or -not $ver) { Die '설치본이 --version 을 못 냈다' }
    Say "설치됨: $ps1 ($ver)"

    if (Add-UserPath $BinDir) { Say "PATH 에 넣었다: $BinDir (새 셸부터 반영된다)" }
    else                      { Say "PATH 에 이미 있다: $BinDir" }

    # Runtime dependencies are not installed; doctor reports what is missing.
    Write-Output ''
    & $ps1 doctor
    $global:LASTEXITCODE = 0
    Write-Output ''
    Say '에이전트에 물리는 법은 README 와 docs/agent-setup.md 에 있다'
} finally {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $tmp
}
