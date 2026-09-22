#Requires -Version 5.1
<#
.SYNOPSIS
    nautice — 에이전트가 사람의 주의를 끄는 알림 CLI (Windows).
.DESCRIPTION
    macOS / Linux 구현은 bin/nautice 에 있다. 동작 계약은 docs/cli.md 가 단일 출처다.
    양쪽을 같이 고쳐야 하며, test/conformance 가 어긋남을 잡는다.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 출력이 파이프나 파일로 갈 때 PowerShell 은 이 인코딩으로 바이트를 쓴다. 기본값은
# ANSI 코드페이지(이 기계는 1252)라 한글이 표시가 아니라 **바이트째** '?'(0x3f) 로
# 바뀐다 — 훅 로그나 `--plan` 출력을 받아 보면 `text=??? ?????` 가 남는다. 콘솔로
# 직접 나갈 때는 WriteConsoleW 를 타서 멀쩡하므로 눈으로는 안 보이는 고장이다.
# 리다이렉트된 핸들에는 SetConsoleOutputCP 를 부르지 않아 부모 콘솔의 코드페이지는
# 건드리지 않는다 (CP437 콘솔에서 실측).
[Console]::OutputEncoding = [Text.Encoding]::UTF8

# 숫자 파싱과 서식을 문화권에서 뗀다. 소수점이 쉼표인 문화권에서는
# [double]::TryParse("0.4") 가 조용히 4 를 내놓고(`--vol 0.4` 가 최대 음량이 된다)
# "{0:F3}" -f 0.4 는 "0,400" 을 찍어 적합성 비교까지 깨진다 (de-DE·fr-FR 실측).
# 부르는 곳마다 InvariantCulture 를 넘기는 방식은 한 군데만 빠뜨려도 다시 새므로
# 스레드 문화권 자체를 바꾼다.
# 보이스 폴백은 사용자의 실제 지역 설정을 봐야 하니 바꾸기 전에 붙잡아 둔다.
$SystemCulture = [Globalization.CultureInfo]::CurrentCulture
[Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture

$VERSION = '0.3.0'

# 부를 때마다 두 번 반복하므로 짧아야 한다.
$CallMessage = '클로드가 부릅니다'
# SAPI 의 Rate 는 -10..10 이고 속도는 대략 3^(Rate/10) 배다. 배속 1.0 이 Rate 0.
$RateBase = 3

function Get-Env($name, $fallback) {
    $v = [Environment]::GetEnvironmentVariable($name)
    if ([string]::IsNullOrWhiteSpace($v)) { return $fallback }
    return $v
}

$Defaults = @{
    Voice   = Get-Env 'NAUTICE_VOICE'   'auto'
    VoiceKo = Get-Env 'NAUTICE_VOICE_KO' 'best'
    VoiceEn = Get-Env 'NAUTICE_VOICE_EN' 'best'
    Vol     = [double](Get-Env 'NAUTICE_VOL'  '0.6')
    Rate    = [double](Get-Env 'NAUTICE_RATE' '1.0')
    Channel = Get-Env 'NAUTICE_CHANNEL' 'sound'
}

function Die($msg) { [Console]::Error.WriteLine("nautice: $msg"); exit 1 }

# ── 인자 파싱 ───────────────────────────────────────────────────────────────
# PowerShell 의 기본 파라미터 바인딩은 이름을 대소문자 구분 없이 맞추므로
# -v(보이스) 와 -V(볼륨) 를 구분하지 못한다. docs/cli.md 의 계약을 그대로
# 지키려면 $args 를 직접 훑어야 한다. -ceq 가 대소문자를 구분한다.
$ValueOpts = @('-v', '--voice', '-V', '--vol', '-r', '--rate',
               '-t', '--tone', '-n', '--repeat', '-g', '--gap',
               '-c', '--channel')

# [double] 캐스트를 그냥 쓰면 `-r abc` 가 .NET 의 변환 예외 스택을 사용자에게
# 뱉는다. bash 쪽은 awk 가 범위를 재다 실패해 제 문구로 죽으므로 여기서 맞춘다.
function ConvertTo-Num([string] $v, [string] $label) {
    # 받아들이는 문법을 정규식으로 못박는다 — 문화권에 안 기대려는 것인데 판정을
    # 다시 문화권 타는 파서에 맡기면 같은 자리로 돌아온다.
    if ($v -notmatch '^[+-]?(\d+(\.\d*)?|\.\d+)$') { Die "$label 은 숫자다: $v" }
    return [double]::Parse($v, [Globalization.CultureInfo]::InvariantCulture)
}

# 반복 횟수는 정수여야 한다. [int] 캐스트는 2.7 을 조용히 3 으로 올려 세 번 내고
# bash 쪽은 for (( )) 가 산술 오류로 죽는다 — 같은 명령이 OS 마다 다르게 깨지므로
# 문법에서 잘라낸다.
function ConvertTo-Int([string] $v, [string] $label) {
    if ($v -notmatch '^[+-]?\d+$') { Die "$label 은 정수다: $v" }
    return [int]::Parse($v, [Globalization.CultureInfo]::InvariantCulture)
}

function Parse-Args([string[]] $argv) {
    $o = @{
        Voice = ''; Vol = $null; Rate = $null; Tone = ''; Channel = ''
        Repeat = 1; Gap = 0.4; Quiet = $false; Async = $false; Plan = $false; PlanName = ''
        RepeatGiven = $false; Rest = @(); Command = ''
    }
    $rest = New-Object System.Collections.Generic.List[string]
    $i = 0
    while ($i -lt $argv.Count) {
        $a = $argv[$i]
        # switch 본문이 $argv[$i + 1] 을 먼저 읽으므로 값이 빠진 걸 여기서 걸러야
        # 한다. 안 그러면 `nautice say -r` 이 .NET 의 IndexOutOfRange 스택을 그대로
        # 사용자에게 뱉는다. -ccontains 가 -v 와 -V 를 구분한다.
        if (($ValueOpts -ccontains $a) -and ($i + 1 -ge $argv.Count)) { Die "$a 에 값이 없다" }
        $needsValue = $true
        switch -CaseSensitive ($a) {
            { $_ -ceq '-v' -or $_ -ceq '--voice'  } { $o.Voice = $argv[$i + 1] }
            { $_ -ceq '-V' -or $_ -ceq '--vol'    } { $o.Vol   = ConvertTo-Num $argv[$i + 1] '--vol' }
            { $_ -ceq '-r' -or $_ -ceq '--rate'   } { $o.Rate  = ConvertTo-Num $argv[$i + 1] '--rate' }
            { $_ -ceq '-t' -or $_ -ceq '--tone'   } { $o.Tone  = $argv[$i + 1] }
            { $_ -ceq '-c' -or $_ -ceq '--channel'} { $o.Channel = $argv[$i + 1] }
            { $_ -ceq '-n' -or $_ -ceq '--repeat' } { $o.Repeat = ConvertTo-Int $argv[$i + 1] '--repeat'; $o.RepeatGiven = $true }
            { $_ -ceq '-g' -or $_ -ceq '--gap'    } { $o.Gap   = ConvertTo-Num $argv[$i + 1] '--gap' }
            { $_ -ceq '-a' -or $_ -ceq '--async'  } { $o.Async = $true;  $needsValue = $false }
            { $_ -ceq '-q' -or $_ -ceq '--quiet'  } { $o.Quiet = $true;  $needsValue = $false }
            { $_ -ceq '--plan' }                     { $o.Plan  = $true;  $needsValue = $false }
            { $_ -ceq '-h' -or $_ -ceq '--help'   } { Show-Usage; exit 0 }
            { $_ -ceq '--version' }                 { Write-Output "nautice $VERSION"; exit 0 }
            '--' { for ($j = $i + 1; $j -lt $argv.Count; $j++) { $rest.Add($argv[$j]) }; $i = $argv.Count; $needsValue = $false }
            default {
                if ($a -like '-*') { Die "모르는 옵션: $a" }
                $rest.Add($a); $needsValue = $false
            }
        }
        if ($needsValue) { $i += 2 } else { $i += 1 }
    }
    if ($rest.Count -gt 0) {
        $o.Command = $rest[0]
        if ($rest.Count -gt 1) { $o.Rest = $rest[1..($rest.Count - 1)] } else { $o.Rest = @() }
    }
    return $o
}

function Assert-Range($value, $lo, $hi, $label) {
    if ($null -eq $value) { return }
    if ($value -lt $lo -or $value -gt $hi) { Die "$label 은 $lo ~ $hi 이다: $value" }
}

# ── 단위 환산 ───────────────────────────────────────────────────────────────
# 계약은 배속(1.0 = 보통). SAPI 는 -10..10 이고 속도가 3^(Rate/10) 배이므로
# 역함수 10*log3(배속) 으로 환산하고 범위를 자른다.
function ConvertTo-SapiRate([double] $multiplier) {
    if ($multiplier -le 0) { return 0 }
    $r = [Math]::Round(10 * [Math]::Log($multiplier, $RateBase))
    return [int][Math]::Max(-10, [Math]::Min(10, $r))
}

function ConvertTo-SapiVolume([double] $vol) {
    return [int][Math]::Max(0, [Math]::Min(100, [Math]::Round($vol * 100)))
}

function Test-Hangul([string] $text) { return $text -match '[가-힣]' }

# ── 시각 채널 (배너) ────────────────────────────────────────────────────────
# NotifyIcon 의 벌룬은 프로세스가 트레이 아이콘을 잡고 있는 동안만 뜬다. 바로
# Dispose 하면 아무것도 안 보인다. 그래서 띄워 두고 소리를 낸 뒤 정리하며,
# 소리가 더 짧게 끝났으면 남은 만큼 기다린다. macOS·Linux 는 알림 데몬에 넘기고
# 바로 끝나므로 이 대기가 없다 — docs/cli.md 의 플랫폼 차이에 적혀 있다.
$BannerHoldMs = 2000

function New-Banner([hashtable] $o, [string] $text) {
    if ($o.Channel -ceq 'sound') { return $null }
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $ni = New-Object System.Windows.Forms.NotifyIcon
    $ni.Icon = [System.Drawing.SystemIcons]::Information
    $ni.Visible = $true
    $ni.ShowBalloonTip($BannerHoldMs, 'nautice', $text, [System.Windows.Forms.ToolTipIcon]::Info)
    return @{ Icon = $ni; Watch = [Diagnostics.Stopwatch]::StartNew() }
}

function Close-Banner($b) {
    if ($null -eq $b) { return }
    $left = $BannerHoldMs - $b.Watch.ElapsedMilliseconds
    if ($left -gt 0) { Start-Sleep -Milliseconds $left }
    $b.Icon.Visible = $false
    $b.Icon.Dispose()
}

# 상태 줄에 배너를 같이 냈다는 것을 덧붙인다.
function Get-ChanNote([hashtable] $o) {
    if ($o.Channel -ceq 'sound') { return '' } else { return ' +배너' }
}

# ── 효과음 ──────────────────────────────────────────────────────────────────
function Get-SoundsDir {
    $env_ = [Environment]::GetEnvironmentVariable('NAUTICE_SOUNDS')
    if (-not [string]::IsNullOrWhiteSpace($env_)) { return $env_ }
    $here = Split-Path -Parent $PSCommandPath
    foreach ($c in @('..\share\sounds', '..\share\nautice\sounds')) {
        $p = Join-Path $here $c
        if (Test-Path $p) { return (Resolve-Path $p).Path }
    }
    Die '번들 효과음을 못 찾았다. NAUTICE_SOUNDS 로 경로를 지정하라'
}

# 번들을 먼저 본다. 세 OS 가 같은 소리를 내야 알림의 뜻이 기계마다 안 흔들린다.
function Resolve-Sfx([string] $name) {
    if (Test-Path -LiteralPath $name -PathType Leaf) { return (Resolve-Path $name).Path }
    $bundled = Join-Path (Get-SoundsDir) "$name.wav"
    if (Test-Path $bundled) { return $bundled }
    if ($env:SystemRoot) {
        $media = Join-Path $env:SystemRoot "Media\$name.wav"
        if (Test-Path $media) { return $media }
    }
    Die "그런 사운드가 없다: $name (nautice list sounds)"
}

# ── TTS ─────────────────────────────────────────────────────────────────────
# macOS 와 달리 SAPI 는 볼륨·속도를 합성 시점에 직접 받는다. 파일로 렌더할
# 이유가 없어서 캐시를 쓰지 않는다 (docs/cli.md 의 플랫폼 차이 참고).
function New-Synth([hashtable] $o, [string] $text) {
    Add-Type -AssemblyName System.Speech
    $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
    $synth.Rate = ConvertTo-SapiRate ([double](Coalesce $o.Rate $Defaults.Rate))
    $synth.Volume = ConvertTo-SapiVolume ([double](Coalesce $o.Vol $Defaults.Vol))

    $installed = @($synth.GetInstalledVoices() | Where-Object { $_.Enabled } | ForEach-Object { $_.VoiceInfo })
    if (-not $installed) { Die '설치된 음성이 하나도 없다' }

    $want = if ($o.Voice) { $o.Voice } else { $Defaults.Voice }
    if ($want -eq 'auto' -or $want -eq 'best') {
        # Windows 는 품질 등급을 노출하지 않는다. best 는 auto 와 같다.
        $want = if (Test-Hangul $text) { $Defaults.VoiceKo } else { $Defaults.VoiceEn }
        if ($want -eq 'auto' -or $want -eq 'best') { $want = '' }
    }

    $pick = $null
    if ($want) {
        $pick = $installed | Where-Object { $_.Name -like "*$want*" } | Select-Object -First 1
        if (-not $pick) { Die "그런 보이스가 없다: $want (nautice list voices)" }
    }
    if (-not $pick -and (Test-Hangul $text)) {
        $pick = $installed | Where-Object { $_.Culture.Name -eq 'ko-KR' } | Select-Object -First 1
    }
    if (-not $pick) {
        $pick = $installed | Where-Object { $_.Culture.Name -eq $SystemCulture.Name } | Select-Object -First 1
    }
    if ($pick) { $synth.SelectVoice($pick.Name) }
    return $synth
}

function Coalesce($a, $b) { if ($null -eq $a) { return $b } else { return $a } }

# ── 재생 ────────────────────────────────────────────────────────────────────
# System.Media.SoundPlayer 에는 볼륨이 없다. --vol 은 TTS 에만 걸리고 효과음은
# 시스템 볼륨으로 난다 (docs/cli.md 의 플랫폼 차이에 적어 둔 의도된 차이다).
function Invoke-Sfx([string] $path) {
    $player = New-Object System.Media.SoundPlayer $path
    try { $player.PlaySync() } finally { $player.Dispose() }
}

# 한 번의 알림 단위(차임 / 발화 / 둘 다)를 --repeat 회 되풀이한다.
function Invoke-Emit([hashtable] $o, [string] $chime, $synth, [string] $text) {
    for ($i = 1; $i -le $o.Repeat; $i++) {
        if ($chime) { Invoke-Sfx $chime }
        if ($synth) { $synth.Speak($text) }
        if ($i -lt $o.Repeat -and $o.Gap -gt 0) {
            Start-Sleep -Milliseconds ([int]($o.Gap * 1000))
        }
    }
}

# 소리를 내지 않고 해석 결과만 찍는다. 앞쪽 블록은 OS 와 무관하게 같아야 하고,
# backend_* 는 docs/cli.md 의 환산식대로 나와야 한다 — test/conformance 가 본다.
# 보이스 해석은 System.Speech 를 타므로 여기서는 요구값만 찍는다. lang 은 그
# 해석의 근거이고 System.Speech 없이 나오므로, voice 와 달리 양쪽을 맞댈 수 있다.
function Write-Plan([hashtable] $o, [string] $cmd, [string] $tone, [string] $text) {
    $vol  = [double](Coalesce $o.Vol  $Defaults.Vol)
    $rate = [double](Coalesce $o.Rate $Defaults.Rate)
    $req  = if ($o.Voice) { $o.Voice } else { $Defaults.Voice }
    Write-Output "command=$cmd"
    Write-Output "voice_req=$req"
    Write-Output "voice="
    Write-Output ("vol={0:F3}" -f $vol)
    Write-Output ("rate={0:F3}" -f $rate)
    Write-Output "repeat=$($o.Repeat)"
    Write-Output ("gap={0:F3}" -f $o.Gap)
    Write-Output "tone=$tone"
    Write-Output "channel=$($o.Channel)"
    Write-Output "text=$text"
    Write-Output "lang=$(if (Test-Hangul $text) { 'ko' } else { 'en' })"
    Write-Output "backend=windows"
    Write-Output "backend_rate=$(ConvertTo-SapiRate $rate)"
    Write-Output "backend_vol=$(ConvertTo-SapiVolume $vol)"
    Write-Output "backend_visual=notifyicon"
}

function Write-Status([hashtable] $o, [string] $line) {
    if (-not $o.Quiet) { Write-Output "nautice: $line" }
}

function Read-Text([hashtable] $o) {
    $text = ($o.Rest -join ' ').Trim()
    if (-not $text -and -not [Console]::IsInputRedirected) { Die '말할 내용이 없다' }
    # [Console]::In 은 콘솔 입력 코드페이지로 디코드한다. CP437 콘솔에 UTF-8 을
    # 흘리면 '한글' 이 6 글자 쓰레기가 되고, 그대로 합성돼 엉뚱한 소리가 난다.
    # --plan 으로는 같은 코드페이지로 되쓰느라 왕복해서 멀쩡해 보인다.
    if (-not $text) {
        $reader = New-Object System.IO.StreamReader ([Console]::OpenStandardInput()), (New-Object System.Text.UTF8Encoding $false)
        try { $text = ($reader.ReadToEnd()).Trim() } finally { $reader.Dispose() }
    }
    if (-not $text) { Die '말할 내용이 없다' }
    return $text
}

# ── 명령 ────────────────────────────────────────────────────────────────────
function Invoke-Say([hashtable] $o) {
    $text = Read-Text $o
    if ($o.Plan) { Write-Plan $o 'say' '' $text; return }
    $banner = New-Banner $o $text
    if ($o.Channel -ceq 'visual') { Write-Status $o 'say 배너만'; Close-Banner $banner; return }
    $synth = New-Synth $o $text
    try {
        Write-Status $o "say x$($o.Repeat) [$($synth.Voice.Name)]$(Get-ChanNote $o)"
        Invoke-Emit $o '' $synth $text
    } finally { $synth.Dispose(); Close-Banner $banner }
}

function Invoke-Play([hashtable] $o) {
    if ($o.Rest.Count -eq 0) { Die '사운드 이름이나 경로가 필요하다 (nautice list sounds)' }
    # 효과음에는 문구가 없어 배너에 적을 것이 없다.
    if ($o.Channel -cne 'sound') { Die 'play 는 문구가 없어 시각 채널을 못 쓴다 (--channel sound)' }
    # 해석이 계획보다 먼저다. 없는 사운드는 --plan 에서도 1 로 죽어야 bash 와 같다.
    $file = Resolve-Sfx $o.Rest[0]
    if ($o.Plan) { Write-Plan $o 'play' $o.Rest[0] ''; return }
    Write-Status $o "play x$($o.Repeat) [$($o.Rest[0])]"
    Invoke-Emit $o $file $null ''
}

function Invoke-Alert([hashtable] $o) {
    if (-not $o.PlanName) { $o.PlanName = 'alert' }
    $text = Read-Text $o
    $tone = if ($o.Tone) { $o.Tone } else { 'ask' }
    if ($o.Plan) { Write-Plan $o $o.PlanName $tone $text; return }
    $banner = New-Banner $o $text
    if ($o.Channel -ceq 'visual') { Write-Status $o "$($o.PlanName) 배너만"; Close-Banner $banner; return }
    $chime = Resolve-Sfx $tone
    $synth = New-Synth $o $text
    try {
        Write-Status $o "alert x$($o.Repeat) [$($synth.Voice.Name)]$(Get-ChanNote $o)"
        Invoke-Emit $o $chime $synth $text
    } finally { $synth.Dispose(); Close-Banner $banner }
}

function Invoke-Call([hashtable] $o) {
    # 사람을 부르는 게 목적이라 한 번으로는 놓치기 쉽다. 따로 지정하지 않으면 두 번.
    if (-not $o.RepeatGiven) { $o.Repeat = 2 }
    $o.PlanName = 'call'
    if ($o.Rest.Count -eq 0) { $o.Rest = @($CallMessage) }
    Invoke-Alert $o
}

function Invoke-List([hashtable] $o) {
    $what = if ($o.Rest.Count -gt 0) { $o.Rest[0] } else { 'all' }
    switch ($what) {
        'sounds' {
            Write-Output '번들 (세 OS 공통):'
            Get-ChildItem (Get-SoundsDir) -Filter *.wav | ForEach-Object { "  $($_.BaseName)" }
            $media = if ($env:SystemRoot) { Join-Path $env:SystemRoot 'Media' } else { $null }
            if ($media -and (Test-Path $media)) {
                Write-Output ''
                Write-Output 'Windows 시스템 사운드:'
                Get-ChildItem $media -Filter *.wav | ForEach-Object { "  $($_.BaseName)" }
            }
        }
        'voices' {
            Add-Type -AssemblyName System.Speech
            $s = New-Object System.Speech.Synthesis.SpeechSynthesizer
            try {
                $s.GetInstalledVoices() | Where-Object { $_.Enabled } | ForEach-Object { $_.VoiceInfo } |
                    Sort-Object { $_.Culture.Name } |
                    ForEach-Object { "  {0,-32} {1}" -f $_.Name, $_.Culture.Name }
            } finally { $s.Dispose() }
        }
        'all' {
            Invoke-List @{ Rest = @('sounds'); Quiet = $o.Quiet }
            Write-Output ''
            Invoke-List @{ Rest = @('voices'); Quiet = $o.Quiet }
        }
        default { Die 'list 대상: voices | sounds | all' }
    }
}

function Invoke-Doctor([hashtable] $o) {
    $ok = 0
    Write-Output "nautice $VERSION (windows)"
    Write-Output ''
    try {
        Add-Type -AssemblyName System.Speech
        $s = New-Object System.Speech.Synthesis.SpeechSynthesizer
        $voices = @($s.GetInstalledVoices() | Where-Object { $_.Enabled })
        $s.Dispose()
        Write-Output ("  {0,-11} System.Speech — 음성 {1}개" -f 'TTS', $voices.Count)
        if ($voices.Count -eq 0) { $ok = 1 }
        $ko = @($voices | Where-Object { $_.VoiceInfo.Culture.Name -eq 'ko-KR' })
        if ($ko.Count -gt 0) {
            Write-Output ("  {0,-11} {1}" -f '한국어', ($ko | ForEach-Object { $_.VoiceInfo.Name }) -join ', ')
        } else {
            Write-Output ("  {0,-11} 없음 — 설정 > 시간 및 언어 > 음성 에서 한국어 음성을 추가하라" -f '한국어')
        }
    } catch {
        Write-Output ("  {0,-11} System.Speech 를 못 불러왔다: {1}" -f 'TTS', $_.Exception.Message)
        $ok = 1
    }
    Write-Output ("  {0,-11} System.Media.SoundPlayer — 볼륨을 못 받는다. --vol 은 TTS 에만 걸린다" -f '재생기')
    Write-Output ("  {0,-11} System.Windows.Forms.NotifyIcon — 데스크톱 세션이 있어야 뜬다" -f '배너')
    Write-Output ("  {0,-11} {1}" -f '효과음', (Get-SoundsDir))
    Write-Output ("  {0,-11} 쓰지 않는다 (SAPI 가 볼륨·속도를 직접 받는다)" -f '캐시')
    # --plan 과 같은 서식으로 찍는다. 그냥 흘리면 [double]1.0 이 "1" 로 나와
    # bash 쪽의 "1.0" 과 달라 보인다.
    Write-Output ("  {0,-11} vol={1:F3} rate={2:F3}" -f '기본값', $Defaults.Vol, $Defaults.Rate)
    exit $ok
}

function Invoke-Cache([hashtable] $o) {
    # Windows 는 TTS 를 파일로 렌더하지 않으므로 비울 것이 없다. 그래도 인자는
    # 계약대로 가린다 — 안 가리면 `cache clera` 같은 오타가 0 으로 통과한다.
    $what = if ($o.Rest.Count -gt 0) { $o.Rest[0] } else { 'info' }
    if ($what -cne 'info' -and $what -cne 'clear') { Die 'cache 대상: info | clear' }
    Write-Output '이 플랫폼은 렌더 캐시를 쓰지 않는다 (SAPI 가 볼륨·속도를 직접 받는다)'
}

function Show-Usage {
    @'
nautice — 에이전트가 사람의 주의를 끄는 알림 CLI

사용법
  nautice say   [옵션] <문구>       읽는다 (생략시 stdin)
  nautice play  [옵션] <이름|경로>  효과음을 낸다
  nautice alert [옵션] <문구>       효과음 뒤에 읽는다
  nautice call  [옵션] [문구]       사람을 부른다 (alert + 기본문구, 2회)
  nautice list  [voices|sounds]     목록
  nautice doctor                    환경 점검
  nautice cache [info|clear]        렌더 캐시

옵션
  -v, --voice NAME   보이스 (auto | best | 이름)
  -V, --vol N        0.0 ~ 1.0            (기본 0.6, 효과음에는 안 걸린다)
  -r, --rate N       배속, 1.0 이 보통     (기본 1.0)
  -t, --tone NAME    alert/call 의 효과음  (기본 ask)
  -c, --channel NAME sound | visual | both (기본 sound)
  -n, --repeat N     정수 1 ~ 20          (기본 1, call 은 2)
  -g, --gap SEC      반복 사이 간격        (기본 0.4)
  -a, --async        기다리지 않고 반환 (훅에서 필수)
  -q, --quiet        상태 줄을 찍지 않는다

효과음 이름표: ok error warn ask start notify

예시
  nautice call
  nautice say "빌드가 끝났습니다"
  nautice alert -t warn -n 3 "디스크가 찼습니다"
  nautice play -V 0.3 ok
  nautice call -c both              # 소리 + 알림 배너
'@ | Write-Output
}

# ── 진입 ────────────────────────────────────────────────────────────────────
$o = Parse-Args $args

Assert-Range $o.Vol    0   10 '--vol'
Assert-Range $o.Rate   0.1 10 '--rate'
Assert-Range $o.Repeat 1   20 '--repeat'
Assert-Range $o.Gap    0   10 '--gap'

if (-not $o.Channel) { $o.Channel = $Defaults.Channel }
if ($o.Channel -cne 'sound' -and $o.Channel -cne 'visual' -and $o.Channel -cne 'both') {
    Die "--channel 은 sound | visual | both 다: $($o.Channel)"
}

# Start-Process 는 -ArgumentList 의 원소를 공백으로 이어 붙이기만 하고 따옴표를
# 붙이지 않는다. 윈도 보이스 이름에는 공백이 있어서(`Microsoft Heami Desktop`)
# 그냥 넘기면 자식이 `-v Microsoft` 로 읽고 나머지를 문구로 삼는다 — 에러도 없고
# 종료코드도 0 인 채로 엉뚱한 보이스가 엉뚱한 문구를 읽는다. 소리는 나므로 귀로도
# 놓친다. CommandLineToArgvW 규칙대로 직접 감싼다.
function Format-CmdArg([string] $a) {
    # 따옴표 앞의 역슬래시와 닫는 따옴표 앞의 역슬래시만 두 배로 한다.
    $s = $a -replace '(\\*)"', '$1$1\"'
    $s = $s -replace '(\\+)$', '$1$1'
    return '"' + $s + '"'
}

# 훅에서 쓰려면 에이전트를 막지 않아야 한다. 인자를 다 검사한 뒤에 떼어내므로
# 인자가 틀렸으면 떼어내기 전에 여기서 죽는다.
if ($o.Async -and @('say', 'play', 'alert', 'call') -contains $o.Command) {
    $passthru = @($args | Where-Object { $_ -cne '-a' -and $_ -cne '--async' })
    $cmdline = (@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-q') + $passthru |
                ForEach-Object { Format-CmdArg $_ }) -join ' '
    Start-Process -FilePath 'powershell' -WindowStyle Hidden -ArgumentList $cmdline
    exit 0
}

switch ($o.Command) {
    'say'    { Invoke-Say   $o }
    'play'   { Invoke-Play  $o }
    'alert'  { Invoke-Alert $o }
    'call'   { Invoke-Call  $o }
    'list'   { Invoke-List  $o }
    'doctor' { Invoke-Doctor $o }
    'cache'  { Invoke-Cache $o }
    ''       { Show-Usage }
    'help'   { Show-Usage }
    default  { Die "모르는 명령: $($o.Command) (nautice --help)" }
}
