#Requires -Version 5.1
<#
.SYNOPSIS
    nautice 설치 (Windows). macOS / Linux 는 install.sh 다.
.DESCRIPTION
    동작 계약은 docs/install.md 가 단일 출처다 — 양쪽을 같이 고쳐야 한다.

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

# 기본값은 NAUTICE_PREFIX 가 없을 때만 만든다. 인자로 넘기면 Join-Path 가 먼저
# 계산돼서, 지정을 했는데도 %LOCALAPPDATA% 가 없는 데서 그 자리가 터진다.
$Prefix = Get-EnvOr 'NAUTICE_PREFIX' ''
if (-not $Prefix) {
    if (-not $env:LOCALAPPDATA) { Die '%LOCALAPPDATA% 가 없다. NAUTICE_PREFIX 로 설치 위치를 지정하라' }
    $Prefix = [IO.Path]::Combine($env:LOCALAPPDATA, 'Programs', 'nautice')
}
$Version = Get-EnvOr 'NAUTICE_VERSION' 'latest'
$Archive = Get-EnvOr 'NAUTICE_ARCHIVE' ''
$BinDir  = Join-Path $Prefix 'bin'

# irm | iex 는 스크립트가 문자열로 들어와 $args 도 $PSCommandPath 도 없다.
# 고를 것은 전부 환경변수로 받는다 (docs/install.md).

# ── PATH ────────────────────────────────────────────────────────────────────
# 사용자 PATH 는 레지스트리 값이라 파일을 파싱하지 않고 중복 없이 넣고 뺄 수
# 있다. Windows 에는 ~/.local/bin 같은 관례가 없어서 등록하지 않으면 새 셸에서
# 못 따라온다 (docs/install.md).
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

# ── 지우기 ──────────────────────────────────────────────────────────────────
if ((Get-EnvOr 'NAUTICE_UNINSTALL' '') -eq '1') {
    # $Prefix 자체는 남긴다 — 남의 것이 같이 들어 있을 수 있는 디렉터리다.
    foreach ($f in @('nautice', 'nautice.ps1', 'nautice.cmd')) {
        Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $BinDir $f)
    }
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue ([IO.Path]::Combine($Prefix, 'share', 'nautice'))
    Remove-UserPath $BinDir
    Say "지웠다: $Prefix (PATH 항목도 뺐다)"
    exit 0
}

# ── 받기 ────────────────────────────────────────────────────────────────────
# Invoke-WebRequest -OutFile 로 받는다. irm 은 응답을 문자열로 디코드해서
# nautice.ps1 의 UTF-8 BOM 을 떼어내고 .wav 를 상하게 한다 — 그래서 알맹이는
# 개별 파일이 아니라 zip 으로 받는다 (docs/install.md).
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
        # 릴리스가 없어도 실제 설치 경로를 돌려 보려는 구멍이다 (CI 가 쓴다).
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

    # ── 풀고 복사 ───────────────────────────────────────────────────────────
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

    # 설치가 됐다는 것은 그 자리의 nautice 가 돈다는 뜻이다. doctor 는 백엔드가
    # 없어도 1 을 내므로 여기서 보지 않는다 (docs/install.md 의 종료 코드).
    $ps1 = Join-Path $BinDir 'nautice.ps1'
    $ver = & $ps1 --version
    if ($LASTEXITCODE -ne 0 -or -not $ver) { Die '설치본이 --version 을 못 냈다' }
    Say "설치됨: $ps1 ($ver)"

    if (Add-UserPath $BinDir) { Say "PATH 에 넣었다: $BinDir (새 셸부터 반영된다)" }
    else                      { Say "PATH 에 이미 있다: $BinDir" }

    # 런타임 의존성은 깔지 않는다. doctor 가 무엇이 없는지 말하는 것이 그 일이다.
    Write-Output ''
    & $ps1 doctor
    $global:LASTEXITCODE = 0
    Write-Output ''
    Say '에이전트에 물리는 법은 README 와 docs/agent-setup.md 에 있다'
} finally {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $tmp
}
