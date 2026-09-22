#Requires -Version 5.1
<#
.SYNOPSIS
    Claude Code 가 사용자를 부를 때 소리를 내는 알림 도구.

.DESCRIPTION
    한국어 TTS 로 호출 문구를 읽거나, 짧은 비프 차임을 울린다.
    Claude Code 의 Notification / Stop 훅에서 호출하는 용도.

.EXAMPLE
    claude-call
.EXAMPLE
    claude-call -Mode both -Repeat 3
.EXAMPLE
    claude-call "빌드가 끝났습니다" -Mode tts
#>
[CmdletBinding()]
param(
    # 읽을 문구. 생략하면 기본 호출 문구를 쓴다.
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]] $Message,

    # tts: 음성으로 읽기 / beep: 비프 차임 / both: 차임 뒤에 음성
    [ValidateSet('tts', 'beep', 'both')]
    [string] $Mode = 'tts',

    # 반복 횟수
    [ValidateRange(1, 20)]
    [int] $Repeat = 2,

    # 말하기 속도 (-10 느림 ~ 10 빠름)
    [ValidateRange(-10, 10)]
    [int] $Rate = 0,

    # 음량 (0-100)
    [ValidateRange(0, 100)]
    [int] $Volume = 100,

    # 반복 사이 간격(초)
    [ValidateRange(0, 10)]
    [double] $Gap = 0.4,

    # 쓸 음성 이름의 일부 (예: Heami, Zira)
    [string] $Voice,

    # 설치된 음성 목록만 출력하고 종료
    [switch] $ListVoices,

    # 표준 출력 없이 조용히 실행
    [switch] $Quiet
)

$ErrorActionPreference = 'Stop'

$defaultMessage = '클로드가 부릅니다. 확인해주세요.'
$text = if ($Message) { ($Message -join ' ').Trim() } else { $defaultMessage }
if (-not $text) { $text = $defaultMessage }

function Write-Status([string] $Line) {
    if (-not $Quiet) { Write-Host "claude-call: $Line" }
}

function Get-Synth {
    Add-Type -AssemblyName System.Speech
    $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
    $synth.Rate = $Rate
    $synth.Volume = $Volume

    $installed = @($synth.GetInstalledVoices() | Where-Object { $_.Enabled } | ForEach-Object { $_.VoiceInfo })
    if (-not $installed) { return $synth }

    $pick = $null
    if ($Voice) {
        $pick = $installed | Where-Object { $_.Name -like "*$Voice*" } | Select-Object -First 1
        if (-not $pick) { Write-Status "voice '$Voice' not found, falling back" }
    }
    if (-not $pick -and $text -match '[가-힣]') {
        # 한글이 섞여 있으면 한국어 음성을 우선한다
        $pick = $installed | Where-Object { $_.Culture.Name -eq 'ko-KR' } | Select-Object -First 1
    }
    if (-not $pick) {
        $pick = $installed | Where-Object { $_.Culture.Name -eq (Get-Culture).Name } | Select-Object -First 1
    }
    if ($pick) { $synth.SelectVoice($pick.Name) }
    return $synth
}

function Invoke-Chime {
    # 올라가는 3음 차임: 가청대역 한가운데라 작은 스피커에서도 잘 들린다
    [Console]::Beep(880, 150)
    [Console]::Beep(1175, 150)
    [Console]::Beep(1568, 260)
}

if ($ListVoices) {
    Add-Type -AssemblyName System.Speech
    $s = New-Object System.Speech.Synthesis.SpeechSynthesizer
    $s.GetInstalledVoices() | ForEach-Object { $_.VoiceInfo } |
        Select-Object Name, @{ n = 'Culture'; e = { $_.Culture.Name } }, Gender |
        Format-Table -AutoSize
    $s.Dispose()
    return
}

$synth = $null
try {
    if ($Mode -ne 'beep') { $synth = Get-Synth }

    Write-Status "$Mode x$Repeat"

    for ($i = 1; $i -le $Repeat; $i++) {
        if ($Mode -eq 'beep' -or $Mode -eq 'both') { Invoke-Chime }
        if ($Mode -eq 'tts' -or $Mode -eq 'both') { $synth.Speak($text) }
        if ($i -lt $Repeat -and $Gap -gt 0) { Start-Sleep -Milliseconds ([int]($Gap * 1000)) }
    }
}
finally {
    if ($synth) { $synth.Dispose() }
}
