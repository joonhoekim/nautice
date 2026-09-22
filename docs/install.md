# 설치 계약

`install.sh`(macOS·Linux) 와 `install.ps1`(Windows) 은 **구현이 둘이고 동작은
하나다.** `bin/` 의 두 구현과 같은 규칙이 여기에도 걸린다 — 한쪽만 고치면
두 OS 의 설치가 갈라지고, 알아차리는 사람은 반대쪽 OS 를 쓰는 사람뿐이다.
이 문서가 그 하나의 출처다.

인스톨러는 최대한 멍청해야 한다. **받기 → 검증 → 풀기 → 복사 → `doctor`** 가
전부고, 판단을 넣지 않는다. 판단이 늘수록 두 구현이 갈라진다.

## 한 줄 설치

```sh
curl -fsSL https://raw.githubusercontent.com/joonhoekim/nautice/main/install.sh | bash
```

```powershell
irm https://raw.githubusercontent.com/joonhoekim/nautice/main/install.ps1 | iex
```

## 환경변수

| 이름 | 기본 | 뜻 |
|---|---|---|
| `NAUTICE_PREFIX` | `~/.local` · `%LOCALAPPDATA%\Programs\nautice` | 설치 위치 |
| `NAUTICE_VERSION` | `latest` | 릴리스 태그 (`v0.4.0`) 또는 `latest` |
| `NAUTICE_ARCHIVE` | 없음 | 받지 않고 이 아카이브를 쓴다. 로컬 경로나 URL |
| `NAUTICE_UNINSTALL` | 없음 | `1` 이면 설치 대신 지운다 |

**인스톨러는 아무것도 묻지 않는다.** `curl | bash` 와 `irm | iex` 는 stdin 이
파이프라 프롬프트를 띄울 수 없다 — `read` 를 부르면 스크립트 본문을 먹는다.
고를 것은 전부 환경변수로 받는다.

## 배치

```
$PREFIX/bin/nautice                   bash 구현
$PREFIX/bin/nautice.ps1               Windows 만
$PREFIX/bin/nautice.cmd               Windows 만
$PREFIX/share/nautice/sounds/*.wav
```

`bin/nautice` 와 `bin/nautice.ps1` 이 자기 위치에서 `../share/nautice/sounds` 를
찾는다. nix 설치본과 같은 배치라 코드가 따로 알 것이 없다.

Windows 아카이브에는 `bin/nautice`(bash) 도 들어간다. Git Bash 에서 `nautice` 를
부르면 그쪽이 `nautice.ps1` 로 넘기기 때문이다.

## 릴리스 자산

`tools/mkdist` 가 만들고 태그가 붙으면 `release.yml` 이 올린다.

| 파일 | 내용 |
|---|---|
| `nautice-unix.tar.gz` | `bin/nautice` + 효과음 + `LICENSE` |
| `nautice-windows.zip` | 위 + `nautice.ps1` · `nautice.cmd` |
| `SHA256SUMS` | 두 아카이브의 해시 |

이름에 버전을 넣지 않는다. `releases/latest/download/<이름>` 이 그대로 서므로
`latest` 를 풀려고 API 를 부를 필요가 없다. 버전은 아카이브 안의 최상위
디렉터리 이름(`nautice-0.4.0/`)이 들고 있다.

### 왜 개별 파일이 아니라 아카이브인가

`nautice.ps1` 은 **UTF-8 BOM 과 CRLF 여야 한다**(`AGENTS.md`). 파일을 하나씩
받아 디스크에 쓰면 그걸 보존하는 책임이 인스톨러로 넘어오고, PowerShell 의
`irm` 은 응답을 문자열로 디코드하면서 BOM 을 떼어낸다. 증상은 한글 깨짐이라
인스톨러 코드만 봐서는 안 보인다. `.wav` 여섯 개도 같은 이유로 바이너리 안전
해야 한다. 아카이브를 풀면 바이트 그대로 나와서 이 부류가 통째로 없어진다.

GitHub 이 자동 생성하는 `archive/*.tar.gz` 를 쓰지 않는 것은 그 체크섬이
시간이 지나면 바뀔 수 있어서다. 검증하려면 우리가 만든 자산이어야 한다.

## 하지 않는 것

- **런타임 의존성을 깔지 않는다.** Linux 의 `espeak-ng` · 재생기 · `libnotify` 는
  배포판마다 다르고 sudo 가 든다. 설치 끝에 `nautice doctor` 를 돌려서 무엇이
  없는지 말하게 한다 — 원래 그 명령의 일이다.
- **에이전트 설정을 건드리지 않는다.** 훅과 `CLAUDE.md` 는 사용자마다 원하는
  방식이 다르고, 인스톨러가 쓴 설정은 낡아도 아무도 고치지 않는다. `README.md`
  와 `docs/claude-code-config.md` 가 스니펫을 주고 붙이는 것은 사람이 한다.
- **Unix 에서 셸 rc 파일을 건드리지 않는다.** `$PREFIX/bin` 이 `PATH` 에 없으면
  붙일 줄을 찍기만 한다.

## PATH

| | 하는 일 |
|---|---|
| macOS · Linux | 안내만. `~/.local/bin` 은 Debian 12+ · Fedora · systemd 환경에서 기본으로 `PATH` 에 있고 macOS 는 없다 |
| Windows | 사용자 `PATH` 에 등록한다. 레지스트리 값이라 파일을 파싱하지 않고 중복 없이 넣고 되돌릴 수 있다. `~/.local/bin` 같은 관례가 없어 등록하지 않으면 새 셸에서 못 따라온다 |

등록은 **새 셸부터** 반영된다.

## 종료 코드

| 코드 | 뜻 |
|---|---|
| 0 | 설치됐다 |
| 1 | 못 받았거나, 해시가 다르거나, 복사에 실패했거나, 설치본이 `--version` 조차 못 냈다 |

마지막에 도는 `doctor` 의 결과는 **종료 코드에 넣지 않는다.** 백엔드가 없는 것은
설치 실패가 아니다. 대신 `nautice --version` 이 안 나오면 1 로 죽는다 — 그건
설치가 안 된 것이다.

## 지우기

```sh
curl -fsSL https://raw.githubusercontent.com/joonhoekim/nautice/main/install.sh | NAUTICE_UNINSTALL=1 bash
NAUTICE_UNINSTALL=1 bash install.sh    # 레포에서 바로
```

```powershell
$env:NAUTICE_UNINSTALL = '1'; irm https://raw.githubusercontent.com/joonhoekim/nautice/main/install.ps1 | iex
```

PowerShell 의 `$env:` 는 **그 세션 내내 남는다.** 같은 창에서 설치 한 줄을 다시
부르면 설치가 아니라 또 지운다. `$env:NAUTICE_UNINSTALL = $null` 로 치운다.

`$PREFIX/bin` 의 세 파일과 `$PREFIX/share/nautice` 를 지운다. `$PREFIX` 자체는
남긴다 — 남의 것이 같이 들어 있는 디렉터리다. Windows 는 등록했던 `PATH`
항목도 뺀다. 캐시(`~/.cache/nautice`)는 `nautice cache clear` 가 지운다.

## 검증

```sh
python3 tools/mkdist                                    # dist/ 를 만든다
NAUTICE_PREFIX=/tmp/p NAUTICE_ARCHIVE=dist/nautice-unix.tar.gz bash install.sh
/tmp/p/bin/nautice --version
```

`NAUTICE_ARCHIVE` 가 있는 이유가 이것이다. 릴리스가 없어도 CI 가 PR 마다 실제
설치 경로를 세 OS 에서 끝까지 돌린다 — `ci.yml` 의 `설치` 잡이다.
