# AGENTS.md

이 저장소에서 코드를 고칠 때 지키는 규칙.

## 구현이 둘이다

`bin/nautice`(bash, macOS·Linux)와 `bin/nautice.ps1`(Windows)은 **같은 동작을
서로 다른 언어로 쓴 것**이다. 한쪽만 고치면 두 OS 의 동작이 갈라지고, 그걸
알아차리는 사람은 반대쪽 OS 를 쓰는 사람뿐이다.

동작을 바꿀 때는 이 순서로 한다.

1. `docs/cli.md` 를 먼저 고친다 — 계약의 단일 출처다.
2. 양쪽 구현을 그에 맞춘다.
3. `./test/conformance` 를 돌린다.

소리는 비교할 수 없으므로 적합성 테스트는 `--plan` 이 찍는 해석 결과를 본다.
새 옵션을 더했으면 `--plan` 출력과 `plan_case` 를 같이 더한다. 안 그러면 그
옵션은 검사 대상 밖이다.

OS 백엔드의 한계 때문에 정말 갈라져야 하는 것은 `docs/cli.md` 의 "플랫폼 차이"
에 적는다. 거기 적히지 않은 차이는 버그다.

## 검증

```sh
./test/conformance     # 두 구현 비교. pwsh 가 없으면 bash 쪽만 본다
nix build .#nautice    # shellcheck 까지 돈다
```

실기가 없는 OS 도 여기까지는 확인할 수 있다.

```sh
# Windows 구현을 macOS·Linux 에서 (System.Speech 는 안 되지만 나머지는 된다)
nix shell nixpkgs#powershell -c pwsh -NoProfile -File bin/nautice.ps1 doctor

# Linux 구현을 macOS 에서 (오디오 장치가 없어 재생만 실패한다)
docker run --rm -v "$PWD:/w:ro" -w /w debian:stable-slim bash -c \
  'apt-get -qq update && apt-get -qq install -y espeak-ng alsa-utils && ./bin/nautice doctor'
```

`say -v NoSuchVoice` 가 exit 0 으로 엉뚱한 보이스를 쓰는 것처럼, 이 바닥의
실패는 대개 조용하다. 무엇이 실제로 났는지 귀로 확인하지 않았으면 "된다" 고
적지 않는다.

## 손대면 깨지는 것

- **`bin/nautice.ps1` 은 UTF-8 BOM 이어야 한다.** 없으면 PowerShell 5.1 이 시스템
  코드페이지로 읽어 한글 문구가 깨진다. 편집기가 BOM 을 떼지 않는지 확인한다.
  `.gitattributes` 가 `*.ps1` 을 CRLF 로 고정하는 것도 같은 이유다.
- **`share/sounds/*.wav` 를 직접 편집하지 않는다.** `tools/gen-sounds.py` 가
  만든다. 소리를 바꾸려면 생성기의 `TONES` 를 고치고 다시 돌린다.
- **셸 정규식에 한글 범위를 여러 개 묶지 않는다.** `[가-힣ㄱ-ㅎ]` 는 en_US
  콜레이션에서 정렬 순서가 코드포인트 순서와 달라 "invalid character range" 로
  죽는다. 음절 범위 `[가-힣]` 하나만 쓴다.
- **숫자를 문화권 타는 API 로 다루지 않는다.** 소수점이 쉼표인 곳에서
  `[double]::TryParse("0.4")` 는 조용히 `4` 를, `printf '%.3f' 0.4` 는 `0,000` 을
  내놓는다. 양쪽 다 시작할 때 문화권을 떼어내고(`LC_NUMERIC=C`,
  `InvariantCulture`) 받아들일 문법은 정규식으로 못박아 뒀다. 되돌리지 않는다.
- **PowerShell 의 `1..0` 은 빈 범위가 아니라 `@(1, 0)` 이다.** 배열을 잘라낼 때
  개수가 1 이면 범위를 벗어난다.
- **`$(cmd || true)` 로 `die` 를 못 막는다.** `exit` 가 서브셸을 그 자리에서
  끝내서 `||` 에 도달하지 못한다. 치환 바깥에서 받는다.

## 커밋 메시지

**제목 1줄, 본문 3줄 이하.** 본문이 길어지면 그건 커밋이 아니라 주석이나
`docs/` 로 갈 내용이다.

```
type(scope): 무엇을 하는지 한국어 평서형으로 (~한다)

왜 필요했는지와 무엇이 바뀌는지. 세 줄을 넘기지 않는다.
```

- `type` 은 `feat` / `fix` / `refactor` / `chore` / `docs` / `test` 중 하나.
- `scope` 는 건드린 자리(`bash`, `windows`, `sounds`, `cli`, `nix`…).
- 제목은 명사구가 아니라 **동작**으로 쓴다 — "보이스 검증" 이 아니라
  "없는 보이스를 거부한다".
- 한 커밋은 한 가지 일만 한다. 양쪽 구현을 같은 이유로 고쳤으면 그건 한 가지
  일이니 한 커밋에 넣는다 — 갈라 놓으면 중간 커밋에서 계약이 깨진다.
- 생성 도구를 언급하지 않는다. 트레일러도 붙이지 않는다.

## 주석

**메커니즘과 결과는 남기고, 사건 서술은 뺀다.** 주석은 다음에 이 코드를 읽는
사람을 위한 것이지 무슨 일이 있었는지에 대한 기록이 아니다.

남겨야 하는 것:

- 이 줄이 없으면 무엇이 깨지는지, 그 증상이 어떻게 보이는지. 특히 **조용히
  실패하는** 것은 반드시 적는다.
- 왜 더 뻔한 방법을 안 썼는지.
- 상류의 사실과 그 출처.
- 값을 실측했으면 그 수치와 측정 조건 (`afplay` 기동 0.95초처럼).

빼야 하는 것: "예전에는 X 였다" 같은 지운 코드의 부고, 커밋 하나에서만 의미
있는 경위, 사건 서술.

## 문서

`README.md` 는 쓰는 사람을 위한 것이고, `docs/cli.md` 는 구현하는 사람을 위한
것이다. 옵션의 정확한 범위와 단위 환산은 `docs/cli.md` 에만 적고 README 는
그쪽을 가리킨다. 두 군데 적으면 한 군데가 낡는다.
