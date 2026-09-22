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
- **이(Yi)·바이(Vai) 문자의 언어 판정** — bash 는 UTF-8 첫 바이트(EA–ED)로 한글을
  가린다. 그 범위에 U+A000–U+ABFF 도 들어가서 이·바이 문자를 한국어로 친다.
  Windows 는 음절 범위를 정확히 본다. 알림 문구에 섞일 일이 없다고 보고 받아들인
  차이다 — 바이트로 보는 이유는 `bin/nautice` 의 `has_hangul` 주석에 있다.

## 환경변수

| 이름 | 뜻 |
|---|---|
| `NAUTICE_VOICE` `NAUTICE_VOICE_KO` `NAUTICE_VOICE_EN` | 기본 보이스 |
| `NAUTICE_VOL` `NAUTICE_RATE` | 기본 볼륨·배속 |
| `NAUTICE_SOUNDS` | 번들 효과음 디렉터리. 비면 실행 파일 옆의 `../share/sounds` 를 찾는다 |
| `NAUTICE_CACHE` | 렌더 캐시 위치 (bash 쪽만 쓴다) |
| `NAUTICE_PIPER_MODEL` | Linux 에서 쓸 piper `.onnx` 경로 |
