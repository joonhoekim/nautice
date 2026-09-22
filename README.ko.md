# nautice

[![ci](https://github.com/joonhoekim/nautice/actions/workflows/ci.yml/badge.svg)](https://github.com/joonhoekim/nautice/actions/workflows/ci.yml)

[English](README.md) · 한국어

> 번역본이다. 영어판과 어긋나면 영어판이 맞다.

에이전트가 사람의 주의를 끄는 알림 CLI. **Windows · Linux · macOS.**

```
nautice call                          # 차임 + "Your agent is calling", 2회
nautice say "빌드가 끝났습니다"
nautice play ok
nautice alert -t warn -n 3 "디스크가 찼습니다"
```

```
nautice call -c both                  # 소리 + OS 알림 배너
nautice say -c visual "빌드 끝"       # 배너만
```

소리와 시각(OS 알림 배너)이 같은 계약 위에 있다. 문구도 옵션도 그대로고
`--channel` 하나로 고른다.

## 왜 OS 도구를 그냥 안 쓰나

| | `say`·`afplay` / `espeak-ng` / SAPI 직접 | `nautice` |
|---|---|---|
| 볼륨 | `say`·`espeak-ng` 에 옵션 없음 | `-V 0.4`, 세 OS 같은 단위 |
| 속도 | wpm / −10–10 / wpm 제각각 | `-r 1.5` 배속, 구현이 환산 |
| 동시 호출 | 섞여서 뭉개짐 | 락으로 직렬화 (bash 쪽) |
| 반복 문장 | 매번 재합성 | 해시 캐시 (bash 쪽) |
| 보이스 | 이름을 직접 알아야 함 | 문구의 문자로 언어를 가려 고른다 (ko·ja·zh·ru·ar…) |
| 효과음 | OS 마다 목록도 이름도 다름 | 같은 파일을 번들로 — 알림의 뜻이 안 흔들린다 |
| 훅에서 호출 | 재생 끝까지 블록 | `-a` 로 즉시 반환 |
| 시각 알림 | osascript / notify-send / 토스트 제각각 | `-c both`, 세 OS 한 옵션 |

## 설치

**macOS · Linux**

```sh
curl -fsSL https://raw.githubusercontent.com/joonhoekim/nautice/main/install.sh | bash
```

**Windows**

```powershell
irm https://raw.githubusercontent.com/joonhoekim/nautice/main/install.ps1 | iex
```

`~/.local` (Windows 는 `%LOCALAPPDATA%\Programs\nautice`) 에 넣고 **무엇이
없는지 `nautice doctor` 로 알려준 뒤 끝난다.** 런타임 의존성을 깔지 않고,
에이전트 설정도 건드리지 않는다. 설치 위치·버전·지우기는
[`docs/install.ko.md`](docs/install.ko.md).

Git Bash 에서 `nautice` 를 부르면 `nautice.ps1` 로 넘어간다 — 이름 하나로 쓴다.

### 지우기

같은 스크립트에 `NAUTICE_UNINSTALL=1` 을 준다.

```sh
curl -fsSL https://raw.githubusercontent.com/joonhoekim/nautice/main/install.sh | NAUTICE_UNINSTALL=1 bash
```

```powershell
$env:NAUTICE_UNINSTALL = '1'; irm https://raw.githubusercontent.com/joonhoekim/nautice/main/install.ps1 | iex
```

설치했던 파일과 `share/nautice` 를 지운다. Windows 는 등록했던 `PATH` 항목도
뺀다. 설치 위치를 바꿨으면 지울 때도 `NAUTICE_PREFIX` 를 같이 준다.

네트워크 없이 지워도 된다 — 받은 것이 파일뿐이다.

```sh
rm -rf ~/.local/bin/nautice ~/.local/share/nautice
```

```powershell
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\Programs\nautice"
```

캐시는 따로 남는다. `nautice cache clear` 로 비우거나(지우기 전에) 디렉터리를
직접 지운다 — `~/.cache/nautice`. Windows 는 캐시를 쓰지 않는다.

<details>
<summary>nix</summary>

```sh
nix run github:joonhoekim/nautice -- call
nix run github:joonhoekim/nautice/v0.4.0 -- call   # 태그를 박아서
nix profile install github:joonhoekim/nautice
./bin/nautice doctor                               # 레포에서 바로

nix profile remove nautice                         # 지우기
```

</details>

## 플랫폼별 준비물

| | TTS | 재생 | 배너 | 비고 |
|---|---|---|---|---|
| macOS | `say` (내장) | `afplay` (내장) | `osascript` (내장) | 받을 게 없다 |
| Windows | System.Speech (내장) | SoundPlayer (내장) | NotifyIcon (내장) | 받을 게 없다 |
| Linux | `espeak-ng` | `pw-play`·`paplay`·`aplay`·`ffplay`·`mpv` 중 하나 | `notify-send` | nix 패키지가 espeak-ng 와 libnotify 를 딸려 보낸다 |

`nautice doctor` 가 무엇이 없는지, 어느 백엔드를 쓰는지 알려준다.

## 보이스 품질

**macOS 가 가장 좋다.** 기본 `Yuna`·`Eddy` 는 `compact`(저용량) 또는
`eloquence`(80년대 포먼트 합성)다. 쓸 만한 건 **시스템 설정 → 손쉬운 사용 →
음성 콘텐츠 → 시스템 음성 → 음성 관리** 에서 받는 `(Premium)` / `(Enhanced)` 다.
받아두면 `nautice` 가 알아서 고른다 — 같은 품질이면 `NAUTICE_VOICE_KO` 에 적은
이름을 먼저 본다. 받은 직후에는 `nautice cache clear` 로 해석 결과를 비운다.

**Windows** 는 설치된 언어팩의 음성만 보인다 — 그 언어가 없으면 다른 음성으로
떨어진다. 품질 등급은 노출되지 않아서 `best` 가 `auto` 와 같다.
`nautice doctor` 의 `languages` 줄이 무엇이 있는지 알려준다.

**Linux 는 한국어가 약하다.** `espeak-ng` 는 포먼트 합성이라 거칠고, `piper` 의
공식 보이스에는 쓸 만한 한국어가 없다. 모델을 따로 구했으면
`NAUTICE_PIPER_MODEL` 로 지정하면 그쪽을 먼저 쓴다. 그 전까지 Linux 에서는
효과음 채널(`nautice play`)이 훨씬 믿을 만하다.

## 에이전트에 물리기

`nautice` 는 **특정 에이전트에 묶이지 않는다.** 하는 일은 소리와 배너를 내는
것뿐이고, 언제 부를지는 에이전트 쪽 설정이 정한다. 설정 파일의 이름도 훅
이벤트의 이름도 에이전트마다 다르다.

**인스톨러는 그 설정을 건드리지 않는다.** 대신 **에이전트에게 시킨다.** 아래를
그대로 붙여 넣으면, 에이전트가 `nautice` 가 무엇인지 스스로 확인하고 **자기
규약대로** 어디에 넣을지 당신에게 물어본 뒤 설정한다.

````markdown
nautice 라는 알림 CLI 를 이 환경에 물려줘.

## 이게 뭔가

에이전트가 사람의 주의를 끄는 알림 도구다. 효과음 · TTS · OS 알림 배너를 한
옵션으로 낸다. Windows · macOS · Linux 에서 같게 동작한다. 특정 에이전트에
묶이지 않는다 — 너를 포함해 셸에서 명령을 부를 수 있으면 다 쓴다.

## 먼저 확인할 것

- `nautice doctor` — 설치됐는지, 이 기계에서 어느 백엔드가 되는지
- `nautice --help` — 명령과 옵션. 아래 설명보다 이쪽이 정확하다

`nautice` 가 없으면 설정하지 말고 나에게 알려줘 —
https://github.com/joonhoekim/nautice 의 설치 한 줄을 내가 먼저 돌려야 한다.

## 어떻게 물릴지 — 성격이 다른 두 가지다. 나에게 물어봐라

**(1) 훅 · 이벤트 — 무조건 울린다.** 사람을 기다릴 때와 한 턴을 마쳤을 때가
쓸 만한 자리다. 빠뜨리지 않는 대신 성가실 수 있다.

**(2) 네가 판단해서 부른다.** 훅을 걸지 않고 지침 파일에 도구의 존재만 적는다.
**"자동으로 울리지 않는다" 를 명시**해야 아무 때나 소리를 내지 않는다.

## 어디에 넣을지 — 네 규약을 따라라

네가 도는 에이전트의 설정 위치와 훅 이벤트 이름은 네가 안다. 훅 같은 기능이
있으면 그 설정 파일에, 없으면 지침 파일(`AGENTS.md` 등)에 적어라.
**전역인지 이 프로젝트만인지도 나에게 물어봐라.**

## 훅에 넣을 때 반드시 지킬 것

- **`-a` 가 없으면 소리가 끝날 때까지 에이전트가 멈춘다.** 훅에서는 필수다.
- `-q` 는 상태 줄을 안 찍는다 — 훅에서는 같이 쓴다.
- Windows 에서는 `nautice` 대신 `nautice.cmd` 로 적는다.

## 고를 때 참고할 것

- 자리를 자주 비우면 `-c both` 로 배너도 같이 띄운다. `--hold` 를 더하면
  사람이 지울 때까지 배너가 남는다.
- 소리가 성가시면 `-c visual` 로 배너만 낼 수 있다.
- 부를 문구는 `nautice say "..."` 로 바꾼다. 한글이면 한국어 보이스로 나간다.
- 부르는 쪽 이름을 넣고 싶으면 `NAUTICE_CALL_MESSAGE` 로 기본 문구를 바꾼다.

## 마무리

기존 설정이 있으면 덮어쓰지 말고 합쳐라. 다 하고 나면 실제로 한 번 울려서
내가 듣고 확인할 수 있게 해줘.
````

<details>
<summary>직접 고치기</summary>

훅 설정은 에이전트마다 모양이 다르다. 아래는 Claude Code 예시다 — 다른
에이전트면 이름만 그쪽 규약으로 바꾼다. 자세한 것은
[`docs/agent-setup.ko.md`](docs/agent-setup.ko.md).

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

에이전트를 막지 않도록 **반드시 `-a`** 를 붙인다. Windows 에서는 `command` 를
`nautice.cmd call -a -q` 로 적는다. 자리를 비울 때가 많으면 `-c both --hold` 를
붙인다 — 배너가 지울 때까지 남는다.

훅 대신 에이전트가 판단해서 부르게 하려면 지침 파일(`AGENTS.md` · `CLAUDE.md`
등)에 적는다.

```markdown
## 사용 가능한 도구

- `nautice` — 사람을 소리로 부르는 알림 CLI. `nautice call -a -q` 로 부른다.
  자동으로 울리지는 않는다 — 오래 걸리는 작업이 끝났거나 사람의 판단이
  필요할 때만 쓴다. 배너까지 띄우려면 `-c both`, 지울 때까지 남기려면 `--hold`.
```

"자동으로 울리지 않는다" 를 적어야 아무 때나 소리를 내지 않는다.

</details>

## 구조

```
bin/nautice        bash   macOS · Linux (Git Bash 에서는 ps1 로 위임)
bin/nautice.ps1    ps1    Windows — UTF-8 BOM 이어야 한글이 안 깨진다
bin/nautice.cmd           cmd 용 런처
share/sounds/             세 OS 공통 효과음
tools/gen-sounds.py       그 효과음을 만드는 스크립트 (표준 라이브러리만)
install.sh                macOS · Linux 인스톨러
install.ps1               Windows 인스톨러
tools/mkdist              릴리스 자산을 만든다 (표준 라이브러리만)
docs/cli.md               동작 계약 — 단일 출처
docs/install.md           설치 계약 — 단일 출처
docs/agent-setup.md       에이전트에 물리는 법
test/conformance          두 구현이 계약을 똑같이 지키는지 본다
```

**구현이 둘이므로 한쪽만 고치면 안 된다.** `docs/cli.md` 를 먼저 고치고 양쪽을
맞춘 뒤 `./test/conformance` 를 돌린다. 소리는 비교할 수 없으므로 `--plan` 이
찍는 해석 결과를 비교한다 — OS 와 무관해야 하는 필드가 다르면 실패한다.
기여 규칙은 [`AGENTS.ko.md`](AGENTS.ko.md).

```sh
./test/conformance     # pwsh 가 없으면 bash 쪽만 보고 비교는 건너뛴다
nix build .#nautice    # shellcheck 까지 돈다
```

## 동작

- **캐시** — `sha1(플랫폼|보이스|배속|문장)` 으로 `$NAUTICE_CACHE/<버전>/`.
  업그레이드하면 새 캐시로 시작한다. 해시 도구는
  `shasum` → `sha1sum` → `md5sum` 순으로 찾는다. 최소 설치된 Linux 에는 `shasum`
  이 없다.
- **락** — 재생 구간에만 건다. 렌더는 병렬이어도 된다. `flock` 이 없으면 mkdir
  락으로 떨어지고, 30초가 지나면 포기하고 그냥 재생한다 — 겹쳐 들리는 편이
  알림을 조용히 잃는 것보다 낫다.
- **보이스 검증** — `say` 는 모르는 보이스를 받아도 exit 0 으로 기본 보이스를 써서
  조용히 읽는다. 오타가 나면 엉뚱한 목소리로 나가는데 표시가 없어서, 목록에
  있는지 먼저 확인하고 없으면 죽는다.
- **언어 판정** — 문구의 문자 계열이 언어다. 한글·가나·한자·키릴·그리스·아랍·
  히브리·태국·데바나가리를 가린다. 라틴 문자는 글에서 언어를 알 수 없으므로 OS
  로캘을 쓰고, 로캘이 없거나 비라틴권이면 `en` 이다. `--lang` 으로 못박는다.
  bash 쪽은 정규식이 아니라 UTF-8 바이트로 본다 — `LC_CTYPE` 이 `C` 면 `[가-힣]`
  이 모든 문자에 매치해서 영어 문장도 한국어로 나간다.
- **배너** — `--channel` 로 켠다. `--repeat` 을 따르지 않고 한 번만 뜬다 — 같은
  배너가 알림 센터에 쌓이면 읽을 수 없다. 백엔드가 0 을 냈다고 배너가 떴다는
  뜻은 아니다: 알림 권한이 없거나 집중 모드면 조용히 눌린다. macOS 에서는
  `osascript` 가 띄우므로 알림 설정에서 **스크립트 편집기**를 찾아야 한다.
- **`afplay` 기동 비용** — 약 0.95초다 (0.43초 파일 재생에 1.38초, macOS 26 / M 계열).
  짧은 알림음에서는 이게 소리 길이보다 크다. 훅은 `-a` 로 떼어내므로 보이지 않는다.

## 환경변수

`NAUTICE_VOICE` `NAUTICE_VOICE_<언어>` `NAUTICE_LANG` `NAUTICE_VOL` `NAUTICE_RATE`
`NAUTICE_CHANNEL` `NAUTICE_CALL_MESSAGE` `NAUTICE_CACHE` `NAUTICE_SOUNDS`
`NAUTICE_PIPER_MODEL`

자세한 것은 [`docs/cli.ko.md`](docs/cli.ko.md).
