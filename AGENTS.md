# AGENTS.md

English · [한국어](AGENTS.ko.md)

Rules for changing code in this repository.

## Two implementations (two pairs)

`bin/nautice` (bash, macOS and Linux) and `bin/nautice.ps1` (Windows) are **the
same behaviour written in two languages.** Change one alone and the OSes
diverge — noticed only by whoever uses the other OS.

To change behaviour:

1. Update `docs/cli.md` first — it is the single source of truth.
2. Bring both implementations in line.
3. Run `./test/conformance`.

Sound cannot be compared, so the conformance test compares what `--plan`
prints. A new option needs both a `--plan` field and a `plan_case`; otherwise it
is outside the test.

Differences that backends truly force go under "Platform differences" in
`docs/cli.md`. Any difference not listed there is a bug.

**The installers are the second pair.** `install.sh` and `install.ps1` implement
`docs/install.md`. The one defence against divergence there is **keeping the
installers dumb**: download → verify → extract → copy → `doctor`, no decisions.
The `install` job in `ci.yml` runs them end to end on all three OSes.

## Verification

```sh
./test/conformance            # compares both; without pwsh only bash runs
/bin/bash ./test/conformance  # again under macOS's bash 3.2
nix build .#nautice           # includes shellcheck

python3 tools/mkdist          # builds release assets in dist/
NAUTICE_PREFIX=/tmp/p NAUTICE_ARCHIVE=dist/nautice-unix.tar.gz bash install.sh
```

`.github/workflows/ci.yml` runs these on all three OS runners. It is the only
place `System.Speech` actually runs on real Windows.

Without the other OS at hand you can still get this far:

```sh
# The Windows implementation on macOS/Linux (all but System.Speech works)
nix shell nixpkgs#powershell -c pwsh -NoProfile -File bin/nautice.ps1 doctor

# The Linux implementation on macOS (only playback fails: no audio device)
docker run --rm -v "$PWD:/w:ro" -w /w debian:stable-slim bash -c \
  'apt-get -qq update && apt-get -qq install -y espeak-ng alsa-utils && ./bin/nautice doctor'
```

Failures here are usually silent — `say -v NoSuchVoice` exits 0 with the wrong
voice. Do not write "works" unless you heard what actually played.

## Things that break when touched

- **Installers cannot prompt.** Under `curl | bash` and `irm | iex` stdin is the
  pipe; `read` consumes the rest of the script. Take every choice from
  environment variables.
- **Install from an archive, never loose files.** Writing files one by one makes
  the installer responsible for the BOM and CRLF below, and PowerShell's `irm`
  decodes responses to strings, dropping the BOM. The `.wav` files get damaged too.
- **`bin/nautice.ps1` must be UTF-8 with a BOM.** Without it PowerShell 5.1 reads
  the file in the system code page, so any non-ASCII character is garbled.
  Check your editor keeps the BOM. `.gitattributes` pins `*.ps1` to CRLF.
- **`install.ps1` must be ASCII without a BOM** — the opposite rule. It is
  fetched with `irm` from a release asset served as `application/octet-stream`,
  with no charset to decode by; plain ASCII reads the same under any decoding.
  The conformance test checks it.
- **Do not edit `share/sounds/*.wav` by hand.** `tools/gen-sounds.py` generates
  them; change its `TONES` and rerun it.
- **Do not match scripts with regex ranges in shell.** With `LC_CTYPE=C`,
  `[가-힣]` **matches every character**, so English text gets a Korean voice —
  silently, wherever there is no locale (cron, systemd, containers). Combining
  ranges (`[가-힣ㄱ-ㅎ]`) even dies with "invalid character range" under en_US
  collation. Read UTF-8 bytes, as `detect_lang` does.
- **Do not handle numbers with culture-sensitive APIs.** Where the decimal mark
  is a comma, `[double]::TryParse("0.4")` quietly returns `4` and
  `printf '%.3f' 0.4` prints `0,000`. Both sides strip the culture at startup
  (`LC_NUMERIC=C`, `InvariantCulture`) and pin the accepted syntax with a regex.
  Do not undo that.
- **PowerShell's `1..0` is not an empty range but `@(1, 0)`.** Slicing an array
  of one element with it goes out of range.
- **macOS's `/bin/bash` is 3.2.** A `case` inside `$( )` dies there with "syntax
  error near unexpected token `;;`", and there are no associative arrays
  (`declare -A`). With a 5.x bash from nix or Homebrew it works locally, so run
  the tests under `/bin/bash` too.
- **`$(cmd || true)` does not catch `die`.** `exit` ends the subshell before `||`
  is reached; handle it outside the substitution.

## Commit messages

**One subject line, a body of at most three lines.** A longer body belongs in a
comment or in `docs/`.

Commit messages are written in English, subject in the imperative mood:

```
type(scope): what the change does, in the imperative

Why it was needed and what changes. No more than three lines.
```

- `type` is one of `feat` / `fix` / `refactor` / `chore` / `docs` / `test`.
- `scope` is the area touched (`bash`, `windows`, `sounds`, `cli`, `nix`, …).
- The subject describes an **action**, not a noun phrase — "reject unknown
  voices", not "voice validation". Lowercase, no trailing period.
- One commit, one change. Fixing both implementations for the same reason is
  one change and one commit — splitting it leaves a commit that breaks the
  contract.
- Never mention generation tools, and add no trailers.

## Comments

**Keep mechanism and consequence; drop narrative.** Comments are for the next
reader of the code, not a record of what happened.

Keep:

- What breaks without this line, and what the symptom looks like. Always
  document failures that are **silent**.
- Why the more obvious approach was not used.
- Upstream facts and where they come from.
- Measured values with their conditions (e.g. `afplay` startup of 0.95 s).

Drop: obituaries of removed code ("this used to be X"), history that matters to
a single commit, storytelling.

Comments and documentation are written in English.

## Documentation

`README.md` is for users; `docs/cli.md` is for implementers. Exact option ranges
and unit conversions live only in `docs/cli.md`, and the README points there —
written twice, one copy goes stale.

The English documents are authoritative. The `*.ko.md` files are Korean
translations; update them in the same change when you can. Where they disagree,
the English document is right.
