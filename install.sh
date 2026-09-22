#!/usr/bin/env bash
# Installs nautice (macOS, Linux). Windows: install.ps1.
# docs/install.md is the contract for both; change them together.
#
#   curl -fsSL https://github.com/joonhoekim/nautice/releases/latest/download/install.sh | bash
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
  say "removed from $PREFIX"
  say "the cache remains; to remove it: rm -rf \"\${XDG_CACHE_HOME:-\$HOME/.cache}/nautice\""
  exit 0
fi

# ── Download ────────────────────────────────────────────────────────────────
fetch() {
  # Without -f a 404 page is saved as the archive and tar fails confusingly.
  if   command -v curl >/dev/null 2>&1; then curl -fsSL -o "$2" -- "$1"
  elif command -v wget >/dev/null 2>&1; then wget -qO  "$2" -- "$1"
  else die "neither curl nor wget found"
  fi
}

sha256_of() {
  if   command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  elif command -v shasum    >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  else return 1
  fi
}

command -v tar >/dev/null 2>&1 || die "tar not found"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/nautice.XXXXXX") || die "cannot create a temporary directory"
trap 'rm -rf "$TMP"' EXIT

tarball="$TMP/$ASSET"
if [[ -n $ARCHIVE ]]; then
  # Lets CI exercise the real install path without a release.
  if [[ -f $ARCHIVE ]]; then cp -- "$ARCHIVE" "$tarball"
  else fetch "$ARCHIVE" "$tarball" || die "download failed: $ARCHIVE"
  fi
  say "archive: $ARCHIVE (hash check skipped)"
else
  if [[ $VERSION == latest ]]; then base="https://github.com/$REPO/releases/latest/download"
  else                              base="https://github.com/$REPO/releases/download/$VERSION"
  fi
  say "downloading $base/$ASSET"
  fetch "$base/$ASSET"   "$tarball"        || die "download failed: $base/$ASSET"
  fetch "$base/SHA256SUMS" "$TMP/SHA256SUMS" || die "download failed: $base/SHA256SUMS"

  want=$(awk -v f="$ASSET" '$2 == f { print $1 }' "$TMP/SHA256SUMS")
  [[ -n $want ]] || die "$ASSET is not listed in SHA256SUMS"
  if got=$(sha256_of "$tarball"); then
    [[ $got == "$want" ]] || die "hash mismatch (expected $want, got $got)"
    say "hash verified"
  else
    # Do not block the install on a missing tool, but say so.
    say "no sha256 tool, skipping verification (sha256sum or shasum)"
  fi
fi

# ── Extract and copy ────────────────────────────────────────────────────────
tar xzf "$tarball" -C "$TMP" || die "cannot extract the archive (download may be truncated)"
src=$(find "$TMP" -maxdepth 1 -type d -name 'nautice-*' | head -1)
[[ -n $src && -f $src/bin/nautice ]] || die "the archive has no bin/nautice"

mkdir -p "$PREFIX/bin" "$PREFIX/share/nautice/sounds"
cp -f "$src/bin/nautice" "$PREFIX/bin/nautice"
chmod 755 "$PREFIX/bin/nautice"
cp -f "$src"/share/nautice/sounds/*.wav "$PREFIX/share/nautice/sounds/"

# Installed means the installed copy runs. doctor's exit code reflects missing
# backends, not a failed install, so it is not checked.
ver=$("$PREFIX/bin/nautice" --version) || die "the installed copy failed to run --version"
say "installed $PREFIX/bin/nautice ($ver)"

# ── PATH hint ───────────────────────────────────────────────────────────────
# Never edit shell rc files: they belong to the user, and lines written by an
# installer go stale unnoticed.
case ":${PATH:-}:" in
  *":$PREFIX/bin:"*) ;;
  *)
    say "$PREFIX/bin is not on PATH; add this line to your shell config:"
    # shellcheck disable=SC2016  # $PATH is literal text for the user to paste
    printf '\n  export PATH="%s/bin:$PATH"\n\n' "$PREFIX" ;;
esac

# ── What is missing ─────────────────────────────────────────────────────────
# Runtime dependencies are not installed; doctor reports what is missing.
echo
"$PREFIX/bin/nautice" doctor || true
echo
say "to wire it to an agent, see README and docs/agent-setup.md"
