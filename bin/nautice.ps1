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
    Preroll = Get-Env 'NAUTICE_PREROLL' '0.25'
}

# Neutral on purpose: the tool is not tied to any agent. Spoken twice, so short.
$CallMessage = Get-Env 'NAUTICE_CALL_MESSAGE' 'Your agent is calling'

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
    if ($v -notmatch '^[+-]?(\d+(\.\d*)?|\.\d+)$') { Die "$label must be a number: $v" }
    return [double]::Parse($v, [Globalization.CultureInfo]::InvariantCulture)
}

# --repeat must be an integer: [int] would round 2.7 to 3, while bash crashes.
function ConvertTo-Int([string] $v, [string] $label) {
    if ($v -notmatch '^[+-]?\d+$') { Die "$label must be an integer: $v" }
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
        if (($ValueOpts -ccontains $a) -and ($i + 1 -ge $argv.Count)) { Die "$a needs a value" }
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
                if ($a -like '-*') { Die "unknown option: $a" }
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
    if ($value -lt $lo -or $value -gt $hi) { Die "$label must be between $lo and ${hi}: $value" }
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
    } catch { Die "cannot load the WinRT notification API needed by --hold: $($_.Exception.Message)" }
    $doc = New-Object Windows.Data.Xml.Dom.XmlDocument
    $doc.LoadXml(@"
<toast scenario="reminder">
  <visual><binding template="ToastGeneric"><text>nautice</text><text>$([Security.SecurityElement]::Escape($text))</text></binding></visual>
  <actions><action content="Dismiss" arguments="dismiss" activationType="system"/></actions>
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
    if ($o.Channel -ceq 'sound') { return '' } else { return ' +banner' }
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
    Die 'bundled sounds not found; set NAUTICE_SOUNDS'
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
    Die "no such sound: $name (nautice list sounds)"
}

# ── TTS ─────────────────────────────────────────────────────────────────────
# SAPI takes volume and rate at synthesis time, so no render-to-file or cache.
function New-Synth([hashtable] $o, [string] $text, [string] $lang) {
    Add-Type -AssemblyName System.Speech
    $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
    $synth.Rate = ConvertTo-SapiRate ([double](Coalesce $o.Rate $Defaults.Rate))
    $synth.Volume = ConvertTo-SapiVolume ([double](Coalesce $o.Vol $Defaults.Vol))

    $installed = @($synth.GetInstalledVoices() | Where-Object { $_.Enabled } | ForEach-Object { $_.VoiceInfo })
    if (-not $installed) { Die 'no voices installed' }

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
        if (-not $pick) { Die "no such voice: $want (nautice list voices)" }
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
# An HDMI display dropped the first ~0.1 s of a sound after a quiet spell, and
# only silence in the same stream helped (docs/cli.md, "Lead-in silence"). So
# the silence is spliced into the WAV bytes, as the bash side does; $null when
# that is not possible (8-bit PCM is unsigned, so its silence is not zeros).
# Only the first 4096 bytes are searched for the data chunk, as in bash.
function Add-WavLead([byte[]] $b, [int] $ms) {
    $ascii = [Text.Encoding]::ASCII
    if ($ms -le 0 -or $b.Length -lt 12) { return $null }
    if ($ascii.GetString($b, 0, 4) -cne 'RIFF' -or $ascii.GetString($b, 8, 4) -cne 'WAVE') { return $null }
    $fmt = 0; $rate = 0; $align = 0; $bits = 0
    $n = [Math]::Min($b.Length, 4096)
    $o = 12
    while ($o + 8 -le $n) {
        $id = $ascii.GetString($b, $o, 4)
        $s = [long][BitConverter]::ToUInt32($b, $o + 4)
        if ($id -ceq 'fmt ') {
            $fmt = [BitConverter]::ToUInt16($b, $o + 8); $rate = [BitConverter]::ToUInt32($b, $o + 16)
            $align = [BitConverter]::ToUInt16($b, $o + 20); $bits = [BitConverter]::ToUInt16($b, $o + 22)
        }
        if ($id -ceq 'data') {
            # 1 PCM, 3 float, 65534 extensible. A streamed size (0, ~4 GiB) is unknown.
            if ($align -lt 1 -or $bits -le 8 -or @(1, 3, 65534) -notcontains $fmt) { return $null }
            if ($s -lt 1 -or $s -gt [int]::MaxValue) { return $null }
            $z = [int]([Math]::Floor([double]$rate * $ms / 1000 / $align) * $align)
            $out = New-Object byte[] ($b.Length + $z)
            [Array]::Copy($b, 0, $out, 0, $o + 8)
            [Array]::Copy($b, $o + 8, $out, $o + 8 + $z, $b.Length - $o - 8)
            [BitConverter]::GetBytes([uint32]([BitConverter]::ToUInt32($b, 4) + $z)).CopyTo($out, 4)
            [BitConverter]::GetBytes([uint32]($s + $z)).CopyTo($out, $o + 4)
            return , $out
        }
        $o += 8 + $s + ($s % 2)
    }
    return $null
}

# SoundPlayer has no volume: --vol applies to TTS only (docs/cli.md).
function Invoke-Sfx([string] $path, [int] $leadMs) {
    $lead = Add-WavLead ([IO.File]::ReadAllBytes($path)) $leadMs
    $stream = $null
    if ($lead) { $stream = New-Object IO.MemoryStream (, $lead); $player = New-Object System.Media.SoundPlayer $stream }
    else       { $player = New-Object System.Media.SoundPlayer $path }
    try { $player.PlaySync() } finally { $player.Dispose(); if ($stream) { $stream.Dispose() } }
}

function Invoke-Speak($synth, [string] $text, [int] $leadMs) {
    if ($leadMs -le 0) { $synth.Speak($text); return }
    # PromptBuilder takes the thread culture by default, which is Invariant here
    # (see the top of this file); give it the voice's own.
    $p = New-Object System.Speech.Synthesis.PromptBuilder ($synth.Voice.Culture)
    $p.AppendBreak([TimeSpan]::FromMilliseconds($leadMs))
    $p.AppendText($text)
    $synth.Speak($p)
}

# Repeat one unit (chime, speech, or both) --repeat times. The lead-in goes
# before the first sound of each repetition only.
function Invoke-Emit([hashtable] $o, [string] $chime, $synth, [string] $text) {
    # Round half up, as bash's awk does; [Math]::Round would round half to even.
    $lead = [int][Math]::Floor($Preroll * 1000 + 0.5)
    for ($i = 1; $i -le $o.Repeat; $i++) {
        if ($chime) { Invoke-Sfx $chime $lead }
        if ($synth) { Invoke-Speak $synth $text $(if ($chime) { 0 } else { $lead }) }
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
    Write-Output ("preroll={0:F3}" -f $Preroll)
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
    if (-not $text -and -not [Console]::IsInputRedirected) { Die 'nothing to say' }
    # Read stdin as UTF-8 ourselves: [Console]::In decodes with the console code
    # page and turns Korean into garbage on CP437. --plan round-trips through the
    # same code page, so the damage is invisible there.
    if (-not $text) {
        $reader = New-Object System.IO.StreamReader ([Console]::OpenStandardInput()), (New-Object System.Text.UTF8Encoding $false)
        try { $text = ($reader.ReadToEnd()).Trim() } finally { $reader.Dispose() }
    }
    if (-not $text) { Die 'nothing to say' }
    return $text
}

# ── Commands ────────────────────────────────────────────────────────────────
function Invoke-Say([hashtable] $o) {
    $text = Read-Text $o
    if ($o.Plan) { Write-Plan $o 'say' '' $text; return }
    $banner = New-Banner $o $text
    if ($o.Channel -ceq 'visual') { Write-Status $o 'say banner only'; Close-Banner $banner; return }
    $synth = New-Synth $o $text (Resolve-Lang $o $text)
    try {
        Write-Status $o "say x$($o.Repeat) [$($synth.Voice.Name)]$(Get-ChanNote $o)"
        Invoke-Emit $o '' $synth $text
    } finally { $synth.Dispose(); Close-Banner $banner }
}

function Invoke-Play([hashtable] $o) {
    if ($o.Rest.Count -eq 0) { Die 'need a sound name or path (nautice list sounds)' }
    # A sound has no text to put in a banner.
    if ($o.Channel -cne 'sound') { Die 'play has no text for a banner (use --channel sound)' }
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
    if ($o.Channel -ceq 'visual') { Write-Status $o "$($o.PlanName) banner only"; Close-Banner $banner; return }
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
            Write-Output 'Bundled (all OSes):'
            Get-ChildItem (Get-SoundsDir) -Filter *.wav | ForEach-Object { "  $($_.BaseName)" }
            $media = if ($env:SystemRoot) { Join-Path $env:SystemRoot 'Media' } else { $null }
            if ($media -and (Test-Path $media)) {
                Write-Output ''
                Write-Output 'Windows system sounds:'
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
        default { Die 'list what: voices | sounds | all' }
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
        Write-Output ("  {0,-12} System.Speech ({1} voices)" -f 'TTS', $voices.Count)
        if ($voices.Count -eq 0) { $ok = 1 }
        # Languages with a voice. Others fall back silently under -q.
        $langs = @($voices | ForEach-Object { $_.VoiceInfo.Culture.TwoLetterISOLanguageName } | Sort-Object -Unique)
        Write-Output ("  {0,-12} {1} (add more: Settings > Time & language > Speech)" -f 'languages', ($langs -join ' '))
    } catch {
        Write-Output ("  {0,-12} cannot load System.Speech: {1}" -f 'TTS', $_.Exception.Message)
        $ok = 1
    }
    Write-Output ("  {0,-12} System.Media.SoundPlayer (no volume control; --vol applies to TTS only)" -f 'player')
    Write-Output ("  {0,-12} System.Windows.Forms.NotifyIcon (needs a desktop session)" -f 'banner')
    Write-Output ("  {0,-12} {1}" -f 'sounds', (Get-SoundsDir))
    Write-Output ("  {0,-12} not used (SAPI takes volume and rate directly)" -f 'cache')
    # Same F3 format as --plan; a bare [double]1.0 prints "1", unlike bash's "1.0".
    Write-Output ("  {0,-12} vol={1:F3} rate={2:F3}" -f 'defaults', $Defaults.Vol, $Defaults.Rate)
    exit $ok
}

function Invoke-Cache([hashtable] $o) {
    # Nothing to clear on Windows, but still reject unknown arguments.
    $what = if ($o.Rest.Count -gt 0) { $o.Rest[0] } else { 'info' }
    if ($what -cne 'info' -and $what -cne 'clear') { Die 'cache what: info | clear' }
    Write-Output 'no render cache on this platform (SAPI takes volume and rate directly)'
}

# Re-run the release's installer for this prefix; the install logic lives only
# in the installers (docs/cli.md, "Updating"). A new process with the same host:
# the installer replaces this very script.
function Invoke-Update([hashtable] $o) {
    $prefix = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
    if (-not (Test-Path ([IO.Path]::Combine($prefix, 'share', 'nautice', 'sounds')))) {
        Die "not installed by install.ps1 ($prefix); update it the way it was installed"
    }
    $url = 'https://github.com/joonhoekim/nautice/releases/latest/download/install.ps1'
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("nautice-install." + [IO.Path]::GetRandomFileName() + ".ps1")
    $ProgressPreference = 'SilentlyContinue'
    try { Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing }
    catch { Die "download failed: $url ($($_.Exception.Message))" }
    $env:NAUTICE_PREFIX = $prefix
    $rc = 1
    try {
        & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $tmp
        $rc = $LASTEXITCODE
    } finally { Remove-Item -Force -ErrorAction SilentlyContinue $tmp }
    exit $rc
}

function Show-Usage {
    @'
nautice — a notification CLI that lets an agent get a human's attention

Usage
  nautice say   [options] <text>        speak (stdin if omitted)
  nautice play  [options] <name|path>   play a sound
  nautice alert [options] <text>        play a sound, then speak
  nautice call  [options] [text]        call the human (alert + default text, twice)
  nautice list  [voices|sounds]         list voices or sounds
  nautice doctor                        check the environment
  nautice cache [info|clear]            render cache
  nautice update                        update this installation

Options
  -v, --voice NAME    voice (auto | best | name)
  -V, --vol N         0.0 to 1.0                (default 0.6; not applied to sounds)
  -r, --rate N        speed multiplier, 1.0 = normal (default 1.0)
  -t, --tone NAME     sound for alert/call      (default ask)
  -c, --channel NAME  sound | visual | both     (default sound)
  -l, --lang CODE     two-letter language code  (default auto: from the text)
      --hold          keep the banner until dismissed (visual channel only)
  -n, --repeat N      integer 1 to 20           (default 1, call 2)
  -g, --gap SEC       pause between repetitions (default 0.4)
  -a, --async         return without waiting (required in hooks)
  -q, --quiet         no status line

Sounds: ok error warn ask start notify

Examples
  nautice call
  nautice say "Build finished"
  nautice alert -t warn -n 3 "Disk is full"
  nautice play -V 0.3 ok
  nautice call -c both                  # sound + notification banner
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
    Die "--lang must be auto or a two-letter language code: $($o.Lang)"
}

if (-not $o.Channel) { $o.Channel = $Defaults.Channel }
if ($o.Channel -cne 'sound' -and $o.Channel -cne 'visual' -and $o.Channel -cne 'both') {
    Die "--channel must be sound, visual or both: $($o.Channel)"
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

# Only the sound commands use it; validated before detaching, as in bash.
$Preroll = 0.0
if (@('say', 'play', 'alert', 'call') -contains $o.Command) {
    $Preroll = ConvertTo-Num $Defaults.Preroll 'NAUTICE_PREROLL'
    Assert-Range $Preroll 0 2 'NAUTICE_PREROLL'
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
    'update' { Invoke-Update $o }
    ''       { Show-Usage }
    'help'   { Show-Usage }
    default  { Die "unknown command: $($o.Command) (nautice --help)" }
}
