# CLI 계약

`bin/nautice`(bash, macOS·Linux) 와 `bin/nautice.ps1`(Windows) 은 **구현이 둘이고
동작은 하나다.** Git Bash·MSYS 에서 `nautice` 를 부르면 bash 쪽이 `nautice.ps1`
로 넘긴다 — 이름 하나로 세 OS 를 쓴다. 이 문서가 그 하나의 출처다. 둘 중 하나만 고치면 안 된다 —
`test/conformance` 가 이 문서의 케이스를 양쪽에서 돌려 어긋남을 잡는다.

## 명령

| 명령 | 하는 일 |
|---|---|
| `nautice say <문구>` | 문구를 읽는다. 생략하면 stdin |
| `nautice play <이름\|경로>` | 효과음을 낸다 |
| `nautice alert <문구>` | 효과음 뒤에 문구를 읽는다 |
| `nautice call [문구]` | 사람을 부른다. `alert` + 기본문구 + `--repeat 2` |
| `nautice list [voices\|sounds]` | 목록 |
| `nautice doctor` | 환경 점검. 정상이면 0 |
| `nautice cache [info\|clear]` | 렌더 캐시 |

`call` 의 기본 문구는 `클로드가 부릅니다. 확인해주세요.` 다.

## 옵션

| 옵션 | 기본 | 단위 / 범위 |
|---|---|---|
| `-v, --voice NAME` | `auto` | 보이스 이름. `auto` = 문구 언어로 선택, `best` = 최고 품질 |
| `-V, --vol N` | `0.6` | **0.0 – 1.0.** 세 OS 공통 단위. 10 까지 받지만 1.0 초과는 백엔드마다 증폭이거나 잘린다 |
| `-r, --rate N` | `1.0` | **배속.** 1.0 = 보통, 1.5 = 1.5배 빠름 |
| `-t, --tone NAME` | `ask` | `alert` / `call` 이 쓸 효과음 |
| `-c, --channel NAME` | `sound` | `sound` / `visual` / `both`. `play` 는 `sound` 만 |
| `-n, --repeat N` | `1` | **정수** 1 – 20. `call` 만 기본 2 |
| `-g, --gap SEC` | `0.4` | 반복 사이 간격 |
| `-a, --async` | off | 기다리지 않고 반환. 훅에서 필수 |
| `-q, --quiet` | off | 상태 줄을 찍지 않는다 |
| `-h, --help` / `--version` | | |
| `--plan` | off | 소리를 내지 않고 해석 결과만 찍는다. `test/conformance` 전용 |

`--` 뒤는 전부 문구로 본다.

### 언어 판정

`--voice auto` 는 **문구에 한글 음절(U+AC00–U+D7A3)이 있으면** 한국어로, 없으면
영어로 본다. 한 글자라도 있으면 한국어다 — 섞인 문구는 한국어 보이스가 영어를
읽는 편이 그 반대보다 알아듣기 쉽다.

이 판정은 `--plan` 의 `lang` 필드(`ko` / `en`)로 드러난다. 해석된 보이스 이름은
OS 마다 달라 맞댈 수 없으므로, 두 구현의 판정이 같은지는 이 필드로 본다.

### 채널

알림이 사람에게 닿는 경로다. 소리가 기본이고, 시각 채널은 OS 알림 배너다.

| 값 | 하는 일 |
|---|---|
| `sound` | 소리만 낸다. 기본값 |
| `visual` | 배너만 띄운다. TTS 백엔드를 아예 안 부른다 |
| `both` | 배너를 먼저 띄우고 이어서 소리를 낸다 |

배너의 제목은 `nautice`, 본문은 문구다.

**배너는 `--repeat` 을 따르지 않는다.** 몇 번을 반복하든 한 번만 띄운다 — 같은
배너가 알림 센터에 쌓이면 읽을 수 없게 된다. `--repeat` 과 `--gap` 은 소리
채널에만 걸린다.

`play` 는 문구가 없어 배너에 적을 것이 없다. `play --channel visual` 과
`play --channel both` 는 1 로 죽는다.

| | 배너 백엔드 | 받을 것 |
|---|---|---|
| macOS | `osascript` 의 `display notification` | 없다 (내장) |
| Linux | `notify-send` | `libnotify` 와 알림 데몬 |
| Windows | `System.Windows.Forms.NotifyIcon` 의 벌룬 | 없다 (내장) |

`--plan` 은 고른 채널을 `channel` 로, 그 OS 의 배너 백엔드를 `backend_visual` 로
찍는다.

### 단위를 왜 이렇게 정했나

`--vol` 과 `--rate` 는 OS 마다 원래 단위가 다르다. 계약은 OS 중립 단위로 두고
각 구현이 자기 백엔드 단위로 환산한다.

| | 계약 | macOS | Linux | Windows |
|---|---|---|---|---|
| 볼륨 | `0.0–1.0` | `afplay -v` 그대로 | 재생기별 환산 | SAPI `Volume` = `×100` |
| 배속 | `1.0` 기준 | `say -r` = `×175` wpm | `espeak-ng -s` = `×175` wpm | SAPI `Rate` = `round(10·log₃(배속))` |

Windows SAPI 의 `Rate` 는 −10 – 10 이고 속도는 대략 `3^(Rate/10)` 배다. 그래서
역함수 `10·log₃(배속)` 로 환산하고 −10 – 10 으로 자른다.

## 효과음 이름표

`ok` `error` `warn` `ask` `start` `notify` — `share/sounds/<이름>.wav` 를 가리킨다.
세 OS 가 **같은 파일**을 쓴다. 알림 소리의 의미가 기계마다 달라지면 안 된다.

이름표가 아닌 값은 먼저 경로로, 그다음 OS 기본 사운드로 해석한다
(macOS `/System/Library/Sounds/<이름>.aiff`, Windows `C:\Windows\Media\<이름>.wav`).

## 종료 코드

| 코드 | 뜻 |
|---|---|
| 0 | 정상 |
| 1 | 잘못된 인자, 없는 보이스·사운드, 백엔드 없음 |

`--async` 는 인자를 검사한 뒤 떼어내므로, 인자가 틀렸으면 그 자리에서 1 로 죽는다.

## 플랫폼 차이 (의도된 것)

이건 버그가 아니라 백엔드의 한계다. 적합성 테스트도 이만큼은 봐준다.

- **Windows 효과음 볼륨** — `System.Media.SoundPlayer` 에 볼륨이 없다. `--vol` 은
  TTS 에만 걸리고 효과음은 시스템 볼륨으로 난다.
- **Linux TTS 품질** — `espeak-ng` 는 포먼트 합성이라 한국어가 많이 거칠다.
  `piper` 공식 보이스에는 쓸 만한 한국어가 없다. `NAUTICE_PIPER_MODEL` 로
  모델을 직접 지정하면 그쪽을 먼저 쓴다.
- **보이스 `best`** — macOS 만 품질 등급(`(Premium)`/`(Enhanced)`)을 노출한다.
  다른 OS 에서 `best` 는 `auto` 와 같다.
- **큐(직렬화)** — bash 쪽만 락을 건다. Windows 는 `Speak()` 가 동기라 한 프로세스
  안에서는 자연히 직렬이지만, 프로세스가 여럿이면 겹칠 수 있다.
- **렌더 캐시** — bash 쪽만 쓴다. `say` 와 `espeak-ng` 에 재생 볼륨 옵션이 없어
  어차피 파일로 렌더해야 하기 때문이다. SAPI 는 볼륨·속도를 합성 시점에 직접
  받으므로 Windows 는 캐시가 없고 `nautice cache` 가 그렇다고 알린다.
- **`--plan` 의 `voice`** — bash 는 해석된 이름(`Yuna (Premium)`)을 찍고 Windows 는
  비운다. 해석에 `System.Speech` 가 필요해서다. 비교 대상은 `voice_req` 와 `lang` 이다.
- **macOS 배너의 주인은 스크립트 편집기다** — `osascript` 가 띄우므로 알림
  센터에 `Script Editor` 로 묶이고, 시스템 설정 → 알림에서도 그 앱 아래에 있다.
  배너의 제목은 `nautice` 로 나오지만 알림을 끄거나 허용하려면 스크립트 편집기를
  찾아야 한다 (macOS 26 에서 실측).
- **배너가 실제로 떴는지는 알 수 없다** — macOS 의 `osascript` 는 알림 권한이
  없거나 집중 모드에 눌려도 0 을 낸다. `notify-send` 도 데몬이 메시지를 버리면
  그렇다. 종료코드 0 은 "백엔드를 불렀다" 까지만 뜻한다. 소리 쪽의 `say -v
  NoSuchVoice` 와 같은 종류의 조용한 실패다.
- **Windows 배너의 수명** — `NotifyIcon` 의 벌룬은 프로세스가 트레이 아이콘을
  잡고 있는 동안만 뜬다. 그래서 Windows 만 배너를 띄운 뒤 잠깐(2초) 붙잡고
  있다가 정리한다. macOS·Linux 는 알림 데몬에 넘기고 바로 끝난다. 훅에서는
  `-a` 로 떼어내므로 이 차이가 보이지 않는다.
- **Windows 배너는 데스크톱 세션이 필요하다** — 서비스나 헤드리스 세션에서는
  트레이가 없어 벌룬이 뜨지 않는다.
- **이(Yi)·바이(Vai) 문자의 언어 판정** — bash 는 UTF-8 첫 바이트(EA–ED)로 한글을
  가린다. 그 범위에 U+A000–U+ABFF 도 들어가서 이·바이 문자를 한국어로 친다.
  Windows 는 음절 범위를 정확히 본다. 알림 문구에 섞일 일이 없다고 보고 받아들인
  차이다 — 바이트로 보는 이유는 `bin/nautice` 의 `has_hangul` 주석에 있다.

## 환경변수

| 이름 | 뜻 |
|---|---|
| `NAUTICE_VOICE` `NAUTICE_VOICE_KO` `NAUTICE_VOICE_EN` | 기본 보이스 |
| `NAUTICE_VOL` `NAUTICE_RATE` | 기본 볼륨·배속 |
| `NAUTICE_CHANNEL` | 기본 채널 (`sound` / `visual` / `both`) |
| `NAUTICE_SOUNDS` | 번들 효과음 디렉터리. 비면 실행 파일 옆의 `../share/sounds` 를 찾는다 |
| `NAUTICE_CACHE` | 렌더 캐시 위치 (bash 쪽만 쓴다) |
| `NAUTICE_PIPER_MODEL` | Linux 에서 쓸 piper `.onnx` 경로 |
