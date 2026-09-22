#Requires -Version 5.1
<#
.SYNOPSIS
    nautice — a notification CLI that lets an agent get a human's attention (Windows).
.DESCRIPTION
    The macOS / Linux implementation is bin/nautice. docs/cli.md is the contract
    for both; change them together, test/conformance catches divergence.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Redirected output is encoded with this; the ANSI default (e.g. 1252) turns
# Korean into literal '?' bytes in hook logs and --plan output, while console
# output looks fine. Does not change the parent console's code page (checked on CP437).
[Console]::OutputEncoding = [Text.Encoding]::UTF8

# With a comma decimal mark, [double]::TryParse("0.4") quietly gives 4 (max
# volume) and "{0:F3}" prints "0,400" (de-DE, fr-FR). Switch the whole thread
# to InvariantCulture; keep the real culture for the language fallback.
$SystemCulture = [Globalization.CultureInfo]::CurrentCulture
[Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture

$VERSION = '0.4.0'

# SAPI Rate is -10..10 and speed is roughly 3^(Rate/10); rate 1.0 is Rate 0.
$RateBase = 3

# Empty string when unset; for dynamic names like NAUTICE_VOICE_<LANG>.
function Get-EnvOrEmpty($name) {
    $v = [Environment]::GetEnvironmentVariable($name)
    if ([string]::IsNullOrWhiteSpace($v)) { return '' }
    return $v
}

function Get-Env($name, $fallback) {
    $v = [Environment]::GetEnvironmentVariable($name)
    if ([string]::IsNullOrWhiteSpace($v)) { return $fallback }
    return $v
}

$Defaults = @{
    Voice   = Get-Env 'NAUTICE_VOICE'   'auto'
    Lang    = Get-Env 'NAUTICE_LANG' 'auto'
    Vol     = [double](Get-Env 'NAUTICE_VOL'  '0.6')
    Rate    = [double](Get-Env 'NAUTICE_RATE' '1.0')
    Channel = Get-Env 'NAUTICE_CHANNEL' 'sound'
}

# Neutral on purpose: the tool is not tied to any agent. Spoken twice, so short.
$CallMessage = Get-Env 'NAUTICE_CALL_MESSAGE' '에이전트가 부릅니다'

function Die($msg) { [Console]::Error.WriteLine("nautice: $msg"); exit 1 }

# ── Argument parsing ────────────────────────────────────────────────────────
# PowerShell parameter binding is case-insensitive and cannot tell -v (voice)
# from -V (volume), so $args is parsed by hand with case-sensitive -ceq.
$ValueOpts = @('-v', '--voice', '-V', '--vol', '-r', '--rate',
               '-t', '--tone', '-n', '--repeat', '-g', '--gap',
               '-c', '--channel', '-l', '--lang')

# A bare [double] cast would show `-r abc` as a .NET exception stack.
function ConvertTo-Num([string] $v, [string] $label) {
    # Pin the syntax with a regex; a culture-aware parser would reintroduce the bug.
    if ($v -notmatch '^[+-]?(\d+(\.\d*)?|\.\d+)$') { Die "$label 은 숫자다: $v" }
    return [double]::Parse($v, [Globalization.CultureInfo]::InvariantCulture)
}

# --repeat must be an integer: [int] would round 2.7 to 3, while bash crashes.
function ConvertTo-Int([string] $v, [string] $label) {
    if ($v -notmatch '^[+-]?\d+$') { Die "$label 은 정수다: $v" }
    return [int]::Parse($v, [Globalization.CultureInfo]::InvariantCulture)
}

function Parse-Args([string[]] $argv) {
    $o = @{
        Voice = ''; Vol = $null; Rate = $null; Tone = ''; Channel = ''
        Lang = ''
        Repeat = 1; Gap = 0.4; Quiet = $false; Async = $false; Hold = $false; Plan = $false; PlanName = ''
        RepeatGiven = $false; Rest = @(); Command = ''
    }
    $rest = New-Object System.Collections.Generic.List[string]
    $i = 0
    while ($i -lt $argv.Count) {
        $a = $argv[$i]
        # Catch a missing value before the switch reads $argv[$i + 1], or
        # `nautice say -r` shows an IndexOutOfRange stack. -ccontains is case-sensitive.
        if (($ValueOpts -ccontains $a) -and ($i + 1 -ge $argv.Count)) { Die "$a 에 값이 없다" }
        $needsValue = $true
        switch -CaseSensitive ($a) {
            { $_ -ceq '-v' -or $_ -ceq '--voice'  } { $o.Voice = $argv[$i + 1] }
            { $_ -ceq '-V' -or $_ -ceq '--vol'    } { $o.Vol   = ConvertTo-Num $argv[$i + 1] '--vol' }
            { $_ -ceq '-r' -or $_ -ceq '--rate'   } { $o.Rate  = ConvertTo-Num $argv[$i + 1] '--rate' }
            { $_ -ceq '-t' -or $_ -ceq '--tone'   } { $o.Tone  = $argv[$i + 1] }
            { $_ -ceq '-c' -or $_ -ceq '--channel'} { $o.Channel = $argv[$i + 1] }
            { $_ -ceq '-l' -or $_ -ceq '--lang'   } { $o.Lang    = $argv[$i + 1] }
            { $_ -ceq '-n' -or $_ -ceq '--repeat' } { $o.Repeat = ConvertTo-Int $argv[$i + 1] '--repeat'; $o.RepeatGiven = $true }
            { $_ -ceq '-g' -or $_ -ceq '--gap'    } { $o.Gap   = ConvertTo-Num $argv[$i + 1] '--gap' }
            { $_ -ceq '-a' -or $_ -ceq '--async'  } { $o.Async = $true;  $needsValue = $false }
            { $_ -ceq '-q' -or $_ -ceq '--quiet'  } { $o.Quiet = $true;  $needsValue = $false }
            { $_ -ceq '--hold' }                     { $o.Hold  = $true;  $needsValue = $false }
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

# ── Unit conversion ─────────────────────────────────────────────────────────
# Multiplier -> SAPI Rate: the inverse of 3^(Rate/10), clamped to -10..10.
function ConvertTo-SapiRate([double] $multiplier) {
    if ($multiplier -le 0) { return 0 }
    $r = [Math]::Round(10 * [Math]::Log($multiplier, $RateBase))
    return [int][Math]::Max(-10, [Math]::Min(10, $r))
}

function ConvertTo-SapiVolume([double] $vol) {
    return [int][Math]::Max(0, [Math]::Min(100, [Math]::Round($vol * 100)))
}

# ── Language detection ──────────────────────────────────────────────────────
# Script -> language. Order is priority and must match docs/cli.md (kana wins
# over Han). .NET regex ranges compare UTF-16 code units, culture-free.
$ScriptLangs = @(
    @{ Lang = 'ko'; Re = '[\uAC00-\uD7A3]' }   # Hangul syllables
    @{ Lang = 'ja'; Re = '[\u3040-\u30FF]' }   # kana
    @{ Lang = 'zh'; Re = '[\u4E00-\u9FFF]' }   # Han
    @{ Lang = 'ru'; Re = '[\u0400-\u04FF]' }   # Cyrillic
    @{ Lang = 'el'; Re = '[\u0370-\u03FF]' }   # Greek
    @{ Lang = 'ar'; Re = '[\u0600-\u06FF]' }   # Arabic
    @{ Lang = 'he'; Re = '[\u0590-\u05FF]' }   # Hebrew
    @{ Lang = 'th'; Re = '[\u0E00-\u0E7F]' }   # Thai
    @{ Lang = 'hi'; Re = '[\u0900-\u097F]' }   # Devanagari
)

# The locale decides Latin text only when it is one of these, so a Korean
# locale does not read English in Korean.
$LatinLangs = @(
    'af','ca','cs','cy','da','de','en','es','et','eu','fi','fr','ga','gl','hr',
    'hu','id','is','it','lt','lv','ms','nb','nl','nn','no','pl','pt','ro','sk',
    'sl','sq','sv','sw','tl','tr','vi'
)

function Resolve-Lang([hashtable] $o, [string] $text) {
    $want = if ($o.Lang) { $o.Lang } else { $Defaults.Lang }
    if ($want -cne 'auto') { return $want }
    foreach ($e in $ScriptLangs) { if ($text -match $e.Re) { return $e.Lang } }
    # Latin script: the text cannot tell, so use the OS culture (saved before
    # the switch to InvariantCulture).
    $loc = $SystemCulture.TwoLetterISOLanguageName
    if ($loc -and ($LatinLangs -contains $loc)) { return $loc }
    return 'en'
}

# ── Visual channel (banner) ─────────────────────────────────────────────────
# A NotifyIcon balloon shows only while the process holds the tray icon;
# disposing at once shows nothing. Hold it through the sound, then at least
# $BannerHoldMs. macOS/Linux hand off to a daemon and need no wait.
$BannerHoldMs = 2000

# --hold needs a WinRT toast with scenario="reminder": since Windows 10 the OS
# decides balloon lifetime and ignores ShowBalloonTip's timeout.
# A toast needs a registered AppUserModelID — an unknown one shows nothing and
# raises nothing — so borrow Windows PowerShell's, present on every Windows.
$ToastAumid = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'

# A reminder with no actions degrades to an ordinary, expiring toast.
function Show-HeldToast([string] $text) {
    try {
        [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType = WindowsRuntime]
    } catch { Die "--hold 에 필요한 WinRT 알림 API 를 못 불러왔다: $($_.Exception.Message)" }
    $doc = New-Object Windows.Data.Xml.Dom.XmlDocument
    $doc.LoadXml(@"
<toast scenario="reminder">
  <visual><binding template="ToastGeneric"><text>nautice</text><text>$([Security.SecurityElement]::Escape($text))</text></binding></visual>
  <actions><action content="확인" arguments="dismiss" activationType="system"/></actions>
</toast>
"@)
    $toast = New-Object Windows.UI.Notifications.ToastNotification $doc
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($ToastAumid).Show($toast)
}

function New-Banner([hashtable] $o, [string] $text) {
    if ($o.Channel -ceq 'sound') { return $null }
    # The notification platform owns the toast; no need to hold the process.
    if ($o.Hold) { Show-HeldToast $text; return $null }
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

# Suffix for the status line when a banner was shown too.
function Get-ChanNote([hashtable] $o) {
    if ($o.Channel -ceq 'sound') { return '' } else { return ' +배너' }
}

# ── Sounds ──────────────────────────────────────────────────────────────────
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

# Bundled sounds first, so a tone means the same thing on every OS.
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
# SAPI takes volume and rate at synthesis time, so no render-to-file or cache.
function New-Synth([hashtable] $o, [string] $text, [string] $lang) {
    Add-Type -AssemblyName System.Speech
    $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
    $synth.Rate = ConvertTo-SapiRate ([double](Coalesce $o.Rate $Defaults.Rate))
    $synth.Volume = ConvertTo-SapiVolume ([double](Coalesce $o.Vol $Defaults.Vol))

    $installed = @($synth.GetInstalledVoices() | Where-Object { $_.Enabled } | ForEach-Object { $_.VoiceInfo })
    if (-not $installed) { Die '설치된 음성이 하나도 없다' }

    $want = if ($o.Voice) { $o.Voice } else { $Defaults.Voice }
    if ($want -eq 'auto' -or $want -eq 'best') {
        # Per-language override such as NAUTICE_VOICE_KO.
        $want = Get-EnvOrEmpty "NAUTICE_VOICE_$($lang.ToUpper())"
    }
    # Windows exposes no quality tiers: best is the same as auto.
    if ($want -eq 'auto' -or $want -eq 'best') { $want = '' }

    $pick = $null
    if ($want) {
        $pick = $installed | Where-Object { $_.Name -like "*$want*" } | Select-Object -First 1
        if (-not $pick) { Die "그런 보이스가 없다: $want (nautice list voices)" }
    }
    # Voice for the language, else fall back rather than fail (docs/cli.md).
    # Only installed language packs have voices, so this falls back often.
    if (-not $pick) {
        $pick = $installed | Where-Object { $_.Culture.TwoLetterISOLanguageName -eq $lang } | Select-Object -First 1
    }
    if (-not $pick) {
        $pick = $installed | Where-Object { $_.Culture.Name -eq $SystemCulture.Name } | Select-Object -First 1
    }
    if ($pick) { $synth.SelectVoice($pick.Name) }
    return $synth
}

function Coalesce($a, $b) { if ($null -eq $a) { return $b } else { return $a } }

# ── Playback ────────────────────────────────────────────────────────────────
# SoundPlayer has no volume: --vol applies to TTS only (docs/cli.md).
function Invoke-Sfx([string] $path) {
    $player = New-Object System.Media.SoundPlayer $path
    try { $player.PlaySync() } finally { $player.Dispose() }
}

# Repeat one unit (chime, speech, or both) --repeat times.
function Invoke-Emit([hashtable] $o, [string] $chime, $synth, [string] $text) {
    for ($i = 1; $i -le $o.Repeat; $i++) {
        if ($chime) { Invoke-Sfx $chime }
        if ($synth) { $synth.Speak($text) }
        if ($i -lt $o.Repeat -and $o.Gap -gt 0) {
            Start-Sleep -Milliseconds ([int]($o.Gap * 1000))
        }
    }
}

# The resolved plan, without sound, for test/conformance. voice stays empty
# (resolving it needs System.Speech); lang is comparable across OSes.
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
    Write-Output "hold=$(if ($o.Hold) { 1 } else { 0 })"
    Write-Output "text=$text"
    Write-Output "lang=$(Resolve-Lang $o $text)"
    Write-Output "backend=windows"
    Write-Output "backend_rate=$(ConvertTo-SapiRate $rate)"
    Write-Output "backend_vol=$(ConvertTo-SapiVolume $vol)"
    Write-Output "backend_visual=$(if ($o.Hold) { 'toast' } else { 'notifyicon' })"
}

function Write-Status([hashtable] $o, [string] $line) {
    if (-not $o.Quiet) { Write-Output "nautice: $line" }
}

function Read-Text([hashtable] $o) {
    $text = ($o.Rest -join ' ').Trim()
    if (-not $text -and -not [Console]::IsInputRedirected) { Die '말할 내용이 없다' }
    # Read stdin as UTF-8 ourselves: [Console]::In decodes with the console code
    # page and turns Korean into garbage on CP437. --plan round-trips through the
    # same code page, so the damage is invisible there.
    if (-not $text) {
        $reader = New-Object System.IO.StreamReader ([Console]::OpenStandardInput()), (New-Object System.Text.UTF8Encoding $false)
        try { $text = ($reader.ReadToEnd()).Trim() } finally { $reader.Dispose() }
    }
    if (-not $text) { Die '말할 내용이 없다' }
    return $text
}

# ── Commands ────────────────────────────────────────────────────────────────
function Invoke-Say([hashtable] $o) {
    $text = Read-Text $o
    if ($o.Plan) { Write-Plan $o 'say' '' $text; return }
    $banner = New-Banner $o $text
    if ($o.Channel -ceq 'visual') { Write-Status $o 'say 배너만'; Close-Banner $banner; return }
    $synth = New-Synth $o $text (Resolve-Lang $o $text)
    try {
        Write-Status $o "say x$($o.Repeat) [$($synth.Voice.Name)]$(Get-ChanNote $o)"
        Invoke-Emit $o '' $synth $text
    } finally { $synth.Dispose(); Close-Banner $banner }
}

function Invoke-Play([hashtable] $o) {
    if ($o.Rest.Count -eq 0) { Die '사운드 이름이나 경로가 필요하다 (nautice list sounds)' }
    # A sound has no text to put in a banner.
    if ($o.Channel -cne 'sound') { Die 'play 는 문구가 없어 시각 채널을 못 쓴다 (--channel sound)' }
    # Resolve before planning: an unknown sound fails under --plan too, as in bash.
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
    $synth = New-Synth $o $text (Resolve-Lang $o $text)
    try {
        Write-Status $o "alert x$($o.Repeat) [$($synth.Voice.Name)]$(Get-ChanNote $o)"
        Invoke-Emit $o $chime $synth $text
    } finally { $synth.Dispose(); Close-Banner $banner }
}

function Invoke-Call([hashtable] $o) {
    # Calling a human: once is easy to miss, so twice unless --repeat is given.
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
        # Languages with a voice. Others fall back silently under -q.
        $langs = @($voices | ForEach-Object { $_.VoiceInfo.Culture.TwoLetterISOLanguageName } | Sort-Object -Unique)
        Write-Output ("  {0,-11} {1} — 더하려면 설정 > 시간 및 언어 > 음성" -f '보이스 언어', ($langs -join ' '))
    } catch {
        Write-Output ("  {0,-11} System.Speech 를 못 불러왔다: {1}" -f 'TTS', $_.Exception.Message)
        $ok = 1
    }
    Write-Output ("  {0,-11} System.Media.SoundPlayer — 볼륨을 못 받는다. --vol 은 TTS 에만 걸린다" -f '재생기')
    Write-Output ("  {0,-11} System.Windows.Forms.NotifyIcon — 데스크톱 세션이 있어야 뜬다" -f '배너')
    Write-Output ("  {0,-11} {1}" -f '효과음', (Get-SoundsDir))
    Write-Output ("  {0,-11} 쓰지 않는다 (SAPI 가 볼륨·속도를 직접 받는다)" -f '캐시')
    # Same F3 format as --plan; a bare [double]1.0 prints "1", unlike bash's "1.0".
    Write-Output ("  {0,-11} vol={1:F3} rate={2:F3}" -f '기본값', $Defaults.Vol, $Defaults.Rate)
    exit $ok
}

function Invoke-Cache([hashtable] $o) {
    # Nothing to clear on Windows, but still reject unknown arguments.
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
  -l, --lang CODE    두 글자 언어 코드     (기본 auto — 문구에서 가린다)
      --hold         배너를 지울 때까지 띄워 둔다 (시각 채널에만)
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

# ── Entry point ─────────────────────────────────────────────────────────────
$o = Parse-Args $args

Assert-Range $o.Vol    0   10 '--vol'
Assert-Range $o.Rate   0.1 10 '--rate'
Assert-Range $o.Repeat 1   20 '--repeat'
Assert-Range $o.Gap    0   10 '--gap'

if (-not $o.Lang) { $o.Lang = $Defaults.Lang }
if ($o.Lang -cne 'auto' -and $o.Lang -notmatch '^[a-z]{2}$') {
    Die "--lang 은 auto 이거나 두 글자 언어 코드다: $($o.Lang)"
}

if (-not $o.Channel) { $o.Channel = $Defaults.Channel }
if ($o.Channel -cne 'sound' -and $o.Channel -cne 'visual' -and $o.Channel -cne 'both') {
    Die "--channel 은 sound | visual | both 다: $($o.Channel)"
}

# Start-Process joins -ArgumentList with spaces and no quoting. Voice names
# contain spaces (`Microsoft Heami Desktop`), so the child would read
# `-v Microsoft` and speak the rest — exit 0, wrong voice, wrong text.
# Quote by CommandLineToArgvW rules.
function Format-CmdArg([string] $a) {
    # Double only backslashes before a quote and before the closing quote.
    $s = $a -replace '(\\*)"', '$1$1\"'
    $s = $s -replace '(\\+)$', '$1$1'
    return '"' + $s + '"'
}

# Hooks must not block the agent. Arguments are validated before detaching, so
# bad input still fails here with exit 1.
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
