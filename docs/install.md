# Install contract

English · [한국어](install.ko.md)

`install.sh` (macOS, Linux) and `install.ps1` (Windows) are **two implementations
of one behaviour** — the same rule as the two implementations under `bin/`:
change one alone and the two OSes install differently, which only users of the
other OS will notice. This document is the single source of truth.

Installers stay as dumb as possible: **download → verify → extract → copy →
`doctor`**, with no decisions. Every decision is a place for the two to diverge.

## One-line install

```sh
curl -fsSL https://raw.githubusercontent.com/joonhoekim/nautice/main/install.sh | bash
```

```powershell
irm https://raw.githubusercontent.com/joonhoekim/nautice/main/install.ps1 | iex
```

## Environment variables

| Name | Default | Meaning |
|---|---|---|
| `NAUTICE_PREFIX` | `~/.local` · `%LOCALAPPDATA%\Programs\nautice` | Install location |
| `NAUTICE_VERSION` | `latest` | Release tag (`v0.4.0`) or `latest` |
| `NAUTICE_ARCHIVE` | — | Use this archive instead of downloading; local path or URL |
| `NAUTICE_UNINSTALL` | — | `1` uninstalls instead |

**Installers never prompt.** Under `curl | bash` and `irm | iex` stdin is the
pipe, so there is nothing to prompt on — `read` would consume the script itself.
Every choice comes from an environment variable.

## Layout

```
$PREFIX/bin/nautice                   bash implementation
$PREFIX/bin/nautice.ps1               Windows only
$PREFIX/bin/nautice.cmd               Windows only
$PREFIX/share/nautice/sounds/*.wav
```

`bin/nautice` and `bin/nautice.ps1` look for `../share/nautice/sounds` relative
to themselves — the same layout as the nix package, so the code needs no extra
knowledge.

The Windows archive includes `bin/nautice` (bash) too: under Git Bash, `nautice`
runs it and it hands over to `nautice.ps1`.

## Release assets

Built by `tools/mkdist` and uploaded by `release.yml` when a tag is pushed.

| File | Contents |
|---|---|
| `nautice-unix.tar.gz` | `bin/nautice` + sounds + `LICENSE` |
| `nautice-windows.zip` | the above + `nautice.ps1` and `nautice.cmd` |
| `SHA256SUMS` | hashes of both archives |

Names carry no version, so `releases/latest/download/<name>` works and `latest`
needs no API call. The version is in the archive's top directory
(`nautice-0.4.0/`).

### Why an archive, not individual files

`nautice.ps1` **must be UTF-8 with a BOM and CRLF** (`AGENTS.md`). Writing files
one by one would make the installer responsible for that, and PowerShell's
`irm` decodes responses into strings, dropping the BOM. The symptom is garbled
Korean, invisible when reading the installer. The six `.wav` files must be
binary-safe for the same reason. Extracting an archive yields exact bytes and
removes the whole class of problem.

GitHub's auto-generated `archive/*.tar.gz` is not used because its checksum can
change over time; verification needs assets we built ourselves.

## What the installers do not do

- **Install runtime dependencies.** Linux's `espeak-ng`, audio player and
  `libnotify` vary by distribution and need sudo. The installer ends with
  `nautice doctor`, whose job is to say what is missing.
- **Touch agent configuration.** Hooks and instructions files are named
  differently per agent and people want different things; settings written by
  an installer go stale unnoticed. `README.md` provides a prompt for the agent,
  and a human applies it.
- **Edit shell rc files on Unix.** If `$PREFIX/bin` is not on `PATH`, the line to
  add is printed, nothing more.

## PATH

| | Does |
|---|---|
| macOS · Linux | Hint only. `~/.local/bin` is on `PATH` by default on Debian 12+, Fedora and systemd setups; not on macOS |
| Windows | Adds to the user `PATH`. It is a registry value: no file parsing, no duplicates, easy to undo. Windows has no `~/.local/bin` convention, so without it new shells would not find nautice |

The change applies **to new shells**.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Installed |
| 1 | Download failed, hash mismatch, copy failed, or the installed copy could not even print `--version` |

The final `doctor` **does not affect the exit code**: a missing backend is not a
failed install. `nautice --version` failing is — exit 1.

## Uninstall

```sh
curl -fsSL https://raw.githubusercontent.com/joonhoekim/nautice/main/install.sh | NAUTICE_UNINSTALL=1 bash
NAUTICE_UNINSTALL=1 bash install.sh    # from a checkout
```

```powershell
$env:NAUTICE_UNINSTALL = '1'; irm https://raw.githubusercontent.com/joonhoekim/nautice/main/install.ps1 | iex
```

PowerShell's `$env:` **persists for the whole session**: running the install
line again in the same window uninstalls again. Clear it with
`$env:NAUTICE_UNINSTALL = $null`.

Removes the three files in `$PREFIX/bin` and `$PREFIX/share/nautice`. `$PREFIX`
itself stays — it is shared with other software. On Windows the `PATH` entry is
removed too. The cache (`~/.cache/nautice`) is removed by `nautice cache clear`.

## Verification

```sh
python3 tools/mkdist                                    # builds dist/
NAUTICE_PREFIX=/tmp/p NAUTICE_ARCHIVE=dist/nautice-unix.tar.gz bash install.sh
/tmp/p/bin/nautice --version
```

This is why `NAUTICE_ARCHIVE` exists: without a release, CI still runs the real
install path end to end on all three OSes for every PR — the `install` job in
`ci.yml`.
