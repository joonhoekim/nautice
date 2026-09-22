# nautice

[![ci](https://github.com/joonhoekim/nautice/actions/workflows/ci.yml/badge.svg)](https://github.com/joonhoekim/nautice/actions/workflows/ci.yml)

에이전트가 사람의 주의를 끄는 알림 CLI. **Windows · Linux · macOS.**

```
nautice call                          # 차임 + "클로드가 부릅니다", 2회
nautice say "빌드가 끝났습니다"
nautice play ok
nautice alert -t warn -n 3 "디스크가 찼습니다"
```

소리가 지금 있는 채널이고, 화면 깜빡임·텍스트 띄우기 같은 시각 채널을 같은
계약 위에 얹는 것이 목표다.

## 왜 OS 도구를 그냥 안 쓰나

| | `say`·`afplay` / `espeak-ng` / SAPI 직접 | `nautice` |
|---|---|---|
| 볼륨 | `say`·`espeak-ng` 에 옵션 없음 | `-V 0.4`, 세 OS 같은 단위 |
| 속도 | wpm / −10–10 / wpm 제각각 | `-r 1.5` 배속, 구현이 환산 |
| 동시 호출 | 섞여서 뭉개짐 | 락으로 직렬화 (bash 쪽) |
| 반복 문장 | 매번 재합성 | 해시 캐시 (bash 쪽) |
| 보이스 | 이름을 직접 알아야 함 | 한글이면 한국어, macOS 는 최고 품질 자동 |
| 효과음 | OS 마다 목록도 이름도 다름 | 같은 파일을 번들로 — 알림의 뜻이 안 흔들린다 |
| 훅에서 호출 | 재생 끝까지 블록 | `-a` 로 즉시 반환 |

## 설치

**macOS · Linux** — nix

```sh
nix run github:joonhoekim/nautice -- call
nix profile install github:joonhoekim/nautice
./bin/nautice doctor          # 레포에서 바로
```

**Windows** — `bin/` 을 PATH 에 있는 디렉터리로 복사하면 끝이다. 런타임이 없다.

```powershell
Copy-Item .\bin\* "$env:USERPROFILE\.local\bin\"
.\bin\nautice.ps1 doctor
```

Git Bash 에서 `nautice` 를 부르면 `nautice.ps1` 로 넘어간다 — 이름 하나로 쓴다.

## 플랫폼별 준비물

| | TTS | 재생 | 비고 |
|---|---|---|---|
| macOS | `say` (내장) | `afplay` (내장) | 받을 게 없다 |
| Windows | System.Speech (내장) | SoundPlayer (내장) | 받을 게 없다 |
| Linux | `espeak-ng` | `pw-play`·`paplay`·`aplay`·`ffplay`·`mpv` 중 하나 | nix 패키지가 espeak-ng 를 딸려 보낸다 |

`nautice doctor` 가 무엇이 없는지, 어느 백엔드를 쓰는지 알려준다.

## 보이스 품질

**macOS 가 가장 좋다.** 기본 `Yuna`·`Eddy` 는 `compact`(저용량) 또는
`eloquence`(80년대 포먼트 합성)다. 쓸 만한 건 **시스템 설정 → 손쉬운 사용 →
음성 콘텐츠 → 시스템 음성 → 음성 관리** 에서 받는 `(Premium)` / `(Enhanced)` 다.
받아두면 `nautice` 가 알아서 고른다 — 같은 품질이면 `NAUTICE_VOICE_KO` 에 적은
이름을 먼저 본다. 받은 직후에는 `nautice cache clear` 로 해석 결과를 비운다.

**Windows** 는 ko-KR 음성(Heami 등)을 자동으로 고른다. 품질 등급은 노출되지
않아서 `best` 가 `auto` 와 같다.

**Linux 는 한국어가 약하다.** `espeak-ng` 는 포먼트 합성이라 거칠고, `piper` 의
공식 보이스에는 쓸 만한 한국어가 없다. 모델을 따로 구했으면
`NAUTICE_PIPER_MODEL` 로 지정하면 그쪽을 먼저 쓴다. 그 전까지 Linux 에서는
효과음 채널(`nautice play`)이 훨씬 믿을 만하다.

## Claude Code 훅

`~/.claude/settings.json`. 에이전트를 막지 않도록 **반드시 `-a`** 를 붙인다.

```json
{
  "hooks": {
    "Notification": [
      { "matcher": "", "hooks": [{ "type": "command", "command": "nautice call -a -q" }] }
    ],
    "Stop": [
      { "matcher": "", "hooks": [{ "type": "command", "command": "nautice say -a -q '작업이 끝났습니다'" }] }
    ]
  }
}
```

Windows 에서는 `command` 를 `nautice.cmd call -a -q` 로 적는다.

## 구조

```
bin/nautice        bash   macOS · Linux (Git Bash 에서는 ps1 로 위임)
bin/nautice.ps1    ps1    Windows — UTF-8 BOM 이어야 한글이 안 깨진다
bin/nautice.cmd           cmd 용 런처
share/sounds/             세 OS 공통 효과음
tools/gen-sounds.py       그 효과음을 만드는 스크립트 (표준 라이브러리만)
docs/cli.md               동작 계약 — 단일 출처
test/conformance          두 구현이 계약을 똑같이 지키는지 본다
```

**구현이 둘이므로 한쪽만 고치면 안 된다.** `docs/cli.md` 를 먼저 고치고 양쪽을
맞춘 뒤 `./test/conformance` 를 돌린다. 소리는 비교할 수 없으므로 `--plan` 이
찍는 해석 결과를 비교한다 — OS 와 무관해야 하는 필드가 다르면 실패한다.

```sh
./test/conformance     # pwsh 가 없으면 bash 쪽만 보고 비교는 건너뛴다
nix build .#nautice    # shellcheck 까지 돈다
```

## 동작

- **캐시** — `sha1(플랫폼|보이스|배속|문장)` 으로 `$NAUTICE_CACHE/*`. 해시 도구는
  `shasum` → `sha1sum` → `md5sum` 순으로 찾는다. 최소 설치된 Linux 에는 `shasum`
  이 없다.
- **락** — 재생 구간에만 건다. 렌더는 병렬이어도 된다. `flock` 이 없으면 mkdir
  락으로 떨어지고, 30초가 지나면 포기하고 그냥 재생한다 — 겹쳐 들리는 편이
  알림을 조용히 잃는 것보다 낫다.
- **보이스 검증** — `say` 는 모르는 보이스를 받아도 exit 0 으로 기본 보이스를 써서
  조용히 읽는다. 오타가 나면 엉뚱한 목소리로 나가는데 표시가 없어서, 목록에
  있는지 먼저 확인하고 없으면 죽는다.
- **한글 감지** — 정규식이 아니라 UTF-8 바이트(EA–ED)로 본다. `LC_CTYPE` 이 `C` 면
  `[가-힣]` 이 모든 문자에 매치해서 영어 문장도 한국어로 나가고, 자모까지 묶으면
  en_US 콜레이션에서 죽는다. 판정 결과는 `--plan` 의 `lang` 으로 드러난다.
- **`afplay` 기동 비용** — 약 0.95초다 (0.43초 파일 재생에 1.38초, macOS 26 / M 계열).
  짧은 알림음에서는 이게 소리 길이보다 크다. 훅은 `-a` 로 떼어내므로 보이지 않는다.

## 환경변수

`NAUTICE_VOICE` `NAUTICE_VOICE_KO` `NAUTICE_VOICE_EN` `NAUTICE_VOL` `NAUTICE_RATE`
`NAUTICE_CACHE` `NAUTICE_SOUNDS` `NAUTICE_PIPER_MODEL`

자세한 것은 [`docs/cli.md`](docs/cli.md).
