# claude-call

Claude Code 가 사람을 불러야 할 때 **소리로 알리는** 작은 CLI.
한국어 TTS 로 문구를 읽거나 짧은 비프 차임을 울린다.

> 현재는 Windows 전용 (PowerShell 5.1 + System.Speech).
> 나중에 여러 OS 를 지원하는 상위 저장소로 통합할 예정이라, 우선 임시로 따로 둔다.

## 구성

| 파일 | 역할 |
|---|---|
| `bin/claude-call.ps1` | 본체. UTF-8 BOM 으로 저장되어야 한글 문구가 깨지지 않는다 |
| `bin/claude-call.cmd` | cmd / PowerShell 에서 `claude-call` 로 부르기 위한 런처 |
| `bin/claude-call` | Git Bash 등 POSIX 셸용 셈 (확장자가 없어야 bash 가 찾는다) |

## 설치

`bin/` 의 세 파일을 PATH 에 있는 디렉터리로 복사하면 끝이다. 별도 런타임이 필요 없다.

```powershell
# 예: 이미 PATH 에 있는 개인 bin 디렉터리로
Copy-Item .\bin\* "$env:USERPROFILE\.local\bin\"
```

PATH 에 없다면 한 번 등록해 준다.

```powershell
[Environment]::SetEnvironmentVariable(
  'Path',
  [Environment]::GetEnvironmentVariable('Path', 'User') + ";$env:USERPROFILE\.local\bin",
  'User')
```

## 사용

```
claude-call                          # 기본: "클로드가 부릅니다. 확인해주세요." 2회
claude-call -Mode beep               # 880 -> 1175 -> 1568 Hz 3음 차임
claude-call -Mode both -Repeat 3     # 차임 + 음성, 3회
claude-call "빌드가 끝났습니다"        # 문구 지정 (첫 인자)
claude-call -Quiet                   # 표준 출력 없이 (훅에서 쓸 때)
claude-call -ListVoices              # 설치된 음성 목록
```

| 옵션 | 기본값 | 설명 |
|---|---|---|
| `-Mode` | `tts` | `tts` / `beep` / `both` |
| `-Repeat` | `2` | 1–20 회 반복 |
| `-Rate` | `0` | 말하기 속도 −10(느림) ~ 10(빠름) |
| `-Volume` | `100` | 0–100 |
| `-Gap` | `0.4` | 반복 사이 간격(초) |
| `-Voice` | 자동 | 음성 이름의 일부 (예: `Heami`) |
| `-Quiet` | off | 상태 줄을 찍지 않는다 |
| `-ListVoices` | – | 음성 목록만 출력하고 종료 |

한글이 섞인 문구면 ko-KR 음성(예: Microsoft Heami)을 자동으로 고르고,
없으면 시스템 로캘 음성으로 폴백한다.

## Claude Code 훅으로 물리기

자동으로 울리게 하려면 `~/.claude/settings.json` 에 훅을 추가한다. (지금은 걸어두지 않았다.)

```json
{
  "hooks": {
    "Notification": [
      { "hooks": [{ "type": "command", "command": "claude-call -Quiet -Mode both", "async": true }] }
    ]
  }
}
```

## 알려진 제약

- `[Console]::Beep` 은 출력 장치가 아니라 시스템 스피커 경로를 쓰므로, 환경에 따라 `-Mode beep` 이 들리지 않을 수 있다. 그럴 땐 `-Mode tts` 를 쓴다.
- 콘솔 코드페이지에 따라 한글 인자가 화면에 `????` 로 보일 수 있지만, 실제로 전달되는 문자열은 온전하다 (읽어주는 내용에는 영향 없음).
