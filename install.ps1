#Requires -Version 5.1
<#
.SYNOPSIS
    Installs nautice (Windows). macOS / Linux: install.sh.
.DESCRIPTION
    docs/install.md is the contract for both; change them together.

      irm https://github.com/joonhoekim/nautice/releases/latest/download/install.ps1 | iex
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
    if (-not $env:LOCALAPPDATA) { Die '%LOCALAPPDATA% is not set; set NAUTICE_PREFIX' }
    $Prefix = [IO.Path]::Combine($env:LOCALAPPDATA, 'Programs', 'nautice')
}
$Version = Get-EnvOr 'NAUTICE_VERSION' 'latest'
$Archive = Get-EnvOr 'NAUTICE_ARCHIVE' ''
$BinDir  = Join-Path $Prefix 'bin'

# Under irm | iex there is no $args or $PSCommandPath; everything comes from
# environment variables.

# -- PATH --------------------------------------------------------------------
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

# -- Uninstall ---------------------------------------------------------------
if ((Get-EnvOr 'NAUTICE_UNINSTALL' '') -eq '1') {
    # Leave $Prefix itself: it may be shared with other software.
    foreach ($f in @('nautice', 'nautice.ps1', 'nautice.cmd')) {
        Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $BinDir $f)
    }
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue ([IO.Path]::Combine($Prefix, 'share', 'nautice'))
    Remove-UserPath $BinDir
    Say "removed from $Prefix (PATH entry too)"
    exit 0
}

# -- Download ----------------------------------------------------------------
# Invoke-WebRequest -OutFile keeps bytes. irm decodes to a string, which strips
# nautice.ps1's UTF-8 BOM and corrupts .wav - hence one zip, not loose files.
function Get-File($url, $dest) {
    try {
        $old = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        try { Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing }
        finally { $ProgressPreference = $old }
    } catch { Die "download failed: $url ($($_.Exception.Message))" }
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("nautice." + [IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
    $zip = Join-Path $tmp $Asset
    if ($Archive) {
        # Lets CI exercise the real install path without a release.
        if (Test-Path -LiteralPath $Archive -PathType Leaf) { Copy-Item -LiteralPath $Archive $zip }
        else { Get-File $Archive $zip }
        Say "archive: $Archive (hash check skipped)"
    } else {
        $base = if ($Version -eq 'latest') { "https://github.com/$Repo/releases/latest/download" }
                else                       { "https://github.com/$Repo/releases/download/$Version" }
        Say "downloading $base/$Asset"
        Get-File "$base/$Asset" $zip
        $sums = Join-Path $tmp 'SHA256SUMS'
        Get-File "$base/SHA256SUMS" $sums

        $want = $null
        foreach ($line in Get-Content $sums) {
            $f = $line -split '\s+'
            if ($f.Count -ge 2 -and $f[1] -eq $Asset) { $want = $f[0] }
        }
        if (-not $want) { Die "$Asset is not listed in SHA256SUMS" }
        $got = (Get-FileHash -Algorithm SHA256 -LiteralPath $zip).Hash.ToLower()
        if ($got -ne $want.ToLower()) { Die "hash mismatch (expected $want, got $got)" }
        Say 'hash verified'
    }

    # -- Extract and copy ----------------------------------------------------
    $out = Join-Path $tmp 'x'
    try { Expand-Archive -LiteralPath $zip -DestinationPath $out -Force }
    catch { Die "cannot extract the archive (download may be truncated): $($_.Exception.Message)" }

    $src = Get-ChildItem -Directory $out | Where-Object { $_.Name -like 'nautice-*' } | Select-Object -First 1
    if (-not $src) { Die 'the archive has no nautice-* directory' }
    $srcBin = Join-Path $src.FullName 'bin'
    if (-not (Test-Path (Join-Path $srcBin 'nautice.ps1'))) { Die 'the archive has no bin/nautice.ps1' }

    $soundDir = [IO.Path]::Combine($Prefix, 'share', 'nautice', 'sounds')
    New-Item -ItemType Directory -Path $BinDir   -Force | Out-Null
    New-Item -ItemType Directory -Path $soundDir -Force | Out-Null
    Copy-Item -Force (Join-Path $srcBin '*') $BinDir
    Copy-Item -Force ([IO.Path]::Combine($src.FullName, 'share', 'nautice', 'sounds', '*.wav')) $soundDir

    # Installed means the installed copy runs. doctor's exit code reflects missing
    # backends, not a failed install, so it is not checked.
    $ps1 = Join-Path $BinDir 'nautice.ps1'
    $ver = & $ps1 --version
    if ($LASTEXITCODE -ne 0 -or -not $ver) { Die 'the installed copy failed to run --version' }
    Say "installed $ps1 ($ver)"

    if (Add-UserPath $BinDir) { Say "added to PATH: $BinDir (applies to new shells)" }
    else                      { Say "already on PATH: $BinDir" }

    # Runtime dependencies are not installed; doctor reports what is missing.
    Write-Output ''
    & $ps1 doctor
    $global:LASTEXITCODE = 0
    Write-Output ''
    Say 'to wire it to an agent, see README and docs/agent-setup.md'
} finally {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $tmp
}
