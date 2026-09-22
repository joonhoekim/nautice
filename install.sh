#!/usr/bin/env bash
# Installs nautice (macOS, Linux). Windows: install.ps1.
# docs/install.md is the contract for both; change them together.
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

# Under curl | bash, stdin is the script itself: `read` would eat the rest of
# it. Never prompt; everything comes from environment variables.

# ── Uninstall ───────────────────────────────────────────────────────────────
if [[ ${NAUTICE_UNINSTALL:-} == 1 ]]; then
  # Leave $PREFIX itself: it is shared with other software.
  rm -f  "$PREFIX/bin/nautice" "$PREFIX/bin/nautice.ps1" "$PREFIX/bin/nautice.cmd"
  rm -rf "$PREFIX/share/nautice"
  say "지웠다: $PREFIX"
  say "캐시는 남아 있다 — 지우려면 rm -rf \"\${XDG_CACHE_HOME:-\$HOME/.cache}/nautice\""
  exit 0
fi

# ── Download ────────────────────────────────────────────────────────────────
fetch() {
  # Without -f a 404 page is saved as the archive and tar fails confusingly.
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
  # Lets CI exercise the real install path without a release.
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
    # Do not block the install on a missing tool, but say so.
    say "sha256 도구가 없어 검증을 건너뛴다 (sha256sum / shasum)"
  fi
fi

# ── Extract and copy ────────────────────────────────────────────────────────
tar xzf "$tarball" -C "$TMP" || die "아카이브를 못 풀었다 (받다 끊겼을 수 있다)"
src=$(find "$TMP" -maxdepth 1 -type d -name 'nautice-*' | head -1)
[[ -n $src && -f $src/bin/nautice ]] || die "아카이브 안에 bin/nautice 가 없다"

mkdir -p "$PREFIX/bin" "$PREFIX/share/nautice/sounds"
cp -f "$src/bin/nautice" "$PREFIX/bin/nautice"
chmod 755 "$PREFIX/bin/nautice"
cp -f "$src"/share/nautice/sounds/*.wav "$PREFIX/share/nautice/sounds/"

# Installed means the installed copy runs. doctor's exit code reflects missing
# backends, not a failed install, so it is not checked.
ver=$("$PREFIX/bin/nautice" --version) || die "설치본이 --version 을 못 냈다"
say "설치됨: $PREFIX/bin/nautice ($ver)"

# ── PATH hint ───────────────────────────────────────────────────────────────
# Never edit shell rc files: they belong to the user, and lines written by an
# installer go stale unnoticed.
case ":${PATH:-}:" in
  *":$PREFIX/bin:"*) ;;
  *)
    say "$PREFIX/bin 이 PATH 에 없다. 셸 설정에 이 줄을 붙인다:"
    # shellcheck disable=SC2016  # $PATH is literal text for the user to paste
    printf '\n  export PATH="%s/bin:$PATH"\n\n' "$PREFIX" ;;
esac

# ── What is missing ─────────────────────────────────────────────────────────
# Runtime dependencies are not installed; doctor reports what is missing.
echo
"$PREFIX/bin/nautice" doctor || true
echo
say "에이전트에 물리는 법은 README 와 docs/agent-setup.md 에 있다"
