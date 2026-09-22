#!/usr/bin/env bash
# nautice 설치 (macOS · Linux). Windows 는 install.ps1 이다.
# 동작 계약은 docs/install.md 가 단일 출처다 — 양쪽을 같이 고쳐야 한다.
#
#   curl -fsSL https://raw.githubusercontent.com/joonhoekim/nautice/main/install.sh | bash
set -euo pipefail

REPO=joonhoekim/nautice
PREFIX=${NAUTICE_PREFIX:-$HOME/.local}
VERSION=${NAUTICE_VERSION:-latest}
ARCHIVE=${NAUTICE_ARCHIVE:-}
ASSET=nautice-unix.tar.gz

say()  { printf 'nautice: %s\n' "$*"; }
die()  { printf 'nautice: %s\n' "$*" >&2; exit 1; }

# curl | bash 는 stdin 이 파이프다. 여기서 read 를 부르면 스크립트 자신의 남은
# 본문을 읽어 먹는다 — 그래서 이 스크립트는 아무것도 묻지 않고 전부
# 환경변수로 받는다 (docs/install.md).

# ── 지우기 ──────────────────────────────────────────────────────────────────
if [[ ${NAUTICE_UNINSTALL:-} == 1 ]]; then
  # $PREFIX 자체는 남긴다 — 남의 것이 같이 들어 있는 디렉터리다.
  rm -f  "$PREFIX/bin/nautice" "$PREFIX/bin/nautice.ps1" "$PREFIX/bin/nautice.cmd"
  rm -rf "$PREFIX/share/nautice"
  say "지웠다: $PREFIX"
  say "캐시는 남아 있다 — 지우려면 rm -rf \"\${XDG_CACHE_HOME:-\$HOME/.cache}/nautice\""
  exit 0
fi

# ── 받기 ────────────────────────────────────────────────────────────────────
fetch() {
  # -f 가 없으면 404 페이지의 HTML 이 그대로 파일에 담긴다. 그 뒤 tar 가
  # 엉뚱한 소리로 죽어서 무엇이 잘못됐는지 알 수 없게 된다.
  if   command -v curl >/dev/null 2>&1; then curl -fsSL -o "$2" -- "$1"
  elif command -v wget >/dev/null 2>&1; then wget -qO  "$2" -- "$1"
  else die "curl 도 wget 도 없다"
  fi
}

sha256_of() {
  if   command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  elif command -v shasum    >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  else return 1
  fi
}

command -v tar >/dev/null 2>&1 || die "tar 가 없다"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/nautice.XXXXXX") || die "임시 디렉터리를 못 만들었다"
trap 'rm -rf "$TMP"' EXIT

tarball="$TMP/$ASSET"
if [[ -n $ARCHIVE ]]; then
  # 릴리스가 없어도 실제 설치 경로를 돌려 보려는 구멍이다 (CI 가 쓴다).
  if [[ -f $ARCHIVE ]]; then cp -- "$ARCHIVE" "$tarball"
  else fetch "$ARCHIVE" "$tarball" || die "못 받았다: $ARCHIVE"
  fi
  say "아카이브: $ARCHIVE (해시 검증 건너뜀)"
else
  if [[ $VERSION == latest ]]; then base="https://github.com/$REPO/releases/latest/download"
  else                              base="https://github.com/$REPO/releases/download/$VERSION"
  fi
  say "받는 중: $base/$ASSET"
  fetch "$base/$ASSET"   "$tarball"        || die "못 받았다: $base/$ASSET"
  fetch "$base/SHA256SUMS" "$TMP/SHA256SUMS" || die "못 받았다: $base/SHA256SUMS"

  want=$(awk -v f="$ASSET" '$2 == f { print $1 }' "$TMP/SHA256SUMS")
  [[ -n $want ]] || die "SHA256SUMS 에 $ASSET 이 없다"
  if got=$(sha256_of "$tarball"); then
    [[ $got == "$want" ]] || die "해시가 다르다 (기대 $want, 실제 $got)"
    say "해시 확인됨"
  else
    # 해시 도구가 없다고 설치를 막지는 않는다. 다만 조용히 넘어가지 않는다.
    say "sha256 도구가 없어 검증을 건너뛴다 (sha256sum / shasum)"
  fi
fi

# ── 풀고 복사 ───────────────────────────────────────────────────────────────
tar xzf "$tarball" -C "$TMP" || die "아카이브를 못 풀었다 (받다 끊겼을 수 있다)"
src=$(find "$TMP" -maxdepth 1 -type d -name 'nautice-*' | head -1)
[[ -n $src && -f $src/bin/nautice ]] || die "아카이브 안에 bin/nautice 가 없다"

mkdir -p "$PREFIX/bin" "$PREFIX/share/nautice/sounds"
cp -f "$src/bin/nautice" "$PREFIX/bin/nautice"
chmod 755 "$PREFIX/bin/nautice"
cp -f "$src"/share/nautice/sounds/*.wav "$PREFIX/share/nautice/sounds/"

# 설치가 됐다는 것은 그 자리의 nautice 가 돈다는 뜻이다. doctor 는 백엔드가
# 없어도 1 을 내므로 여기서 보지 않는다 (docs/install.md 의 종료 코드).
ver=$("$PREFIX/bin/nautice" --version) || die "설치본이 --version 을 못 냈다"
say "설치됨: $PREFIX/bin/nautice ($ver)"

# ── PATH 안내 ───────────────────────────────────────────────────────────────
# 셸 rc 파일은 건드리지 않는다. 남의 설정이고, 인스톨러가 쓴 줄은 낡아도
# 아무도 고치지 않는다 (docs/install.md).
case ":${PATH:-}:" in
  *":$PREFIX/bin:"*) ;;
  *)
    say "$PREFIX/bin 이 PATH 에 없다. 셸 설정에 이 줄을 붙인다:"
    # shellcheck disable=SC2016  # $PATH 는 사용자가 붙여 넣을 글자 그대로다
    printf '\n  export PATH="%s/bin:$PATH"\n\n' "$PREFIX" ;;
esac

# ── 무엇이 없는지 ───────────────────────────────────────────────────────────
# 런타임 의존성은 깔지 않는다. doctor 가 무엇이 없는지 말하는 것이 그 일이다.
echo
"$PREFIX/bin/nautice" doctor || true
echo
say "에이전트에 물리는 법은 README 와 docs/agent-setup.md 에 있다"
