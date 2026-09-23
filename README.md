# nautice

[![ci](https://github.com/joonhoekim/nautice/actions/workflows/ci.yml/badge.svg)](https://github.com/joonhoekim/nautice/actions/workflows/ci.yml)

English · [한국어](README.ko.md)

A notification CLI that lets an agent get a human's attention. **Windows · Linux · macOS.**

```
nautice call                          # chime + the default message, twice
nautice say "Build finished"
nautice say "빌드가 끝났습니다"          # Korean text gets a Korean voice
nautice play ok
nautice alert -t warn -n 3 "Disk is full"
```

```
nautice call -c both                  # sound + OS notification banner
nautice say -c visual "Build done"    # banner only
```

Sound and visual (OS notification banner) share one contract: same text, same
options, one `--channel` to choose.

## Why not just call the OS tools

| | `say`/`afplay`, `espeak-ng`, SAPI directly | `nautice` |
|---|---|---|
| Volume | `say` and `espeak-ng` have no option | `-V 0.4`, same unit on every OS |
| Speed | wpm / −10…10 / wpm | `-r 1.5` multiplier, converted per backend |
| Concurrent calls | overlap into mush | serialised with a lock (bash side) |
| Repeated phrases | re-synthesised every time | hash-keyed cache (bash side) |
| Voice | you must know names | picked from the text's script (ko, ja, zh, ru, ar…) |
| Sound effects | different set and names per OS | one bundled set — a tone means the same everywhere |
| Called from a hook | blocks until playback ends | `-a` returns immediately |
| Visual alerts | osascript / notify-send / toasts | `-c both`, one option on all three |

## Install

**macOS · Linux**

```sh
curl -fsSL https://github.com/joonhoekim/nautice/releases/latest/download/install.sh | bash
```

**Windows**

```powershell
irm https://github.com/joonhoekim/nautice/releases/latest/download/install.ps1 | iex
```

Installs into `~/.local` (`%LOCALAPPDATA%\Programs\nautice` on Windows) and
**ends by running `nautice doctor` to show what is missing.** It installs no
runtime dependencies and does not touch agent configuration. Location, version
and uninstalling: [`docs/install.md`](docs/install.md).

In Git Bash, `nautice` hands over to `nautice.ps1`, so one name works everywhere.

### Update

```sh
nautice update
```

Downloads the latest release's installer and re-runs it for this installation;
running the install line again does the same. Nix installs update with
`nix profile upgrade nautice`.

### Uninstall

Run the same script with `NAUTICE_UNINSTALL=1`.

```sh
curl -fsSL https://github.com/joonhoekim/nautice/releases/latest/download/install.sh | NAUTICE_UNINSTALL=1 bash
```

```powershell
$env:NAUTICE_UNINSTALL = '1'; irm https://github.com/joonhoekim/nautice/releases/latest/download/install.ps1 | iex
```

This removes the installed files and `share/nautice`; on Windows it also removes
the `PATH` entry. If you installed with `NAUTICE_PREFIX`, pass it again.

Offline works too — the install is just files:

```sh
rm -rf ~/.local/bin/nautice ~/.local/share/nautice
```

```powershell
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\Programs\nautice"
```

The cache stays behind: empty it first with `nautice cache clear`, or delete
`~/.cache/nautice`. Windows uses no cache.

<details>
<summary>nix</summary>

```sh
nix run github:joonhoekim/nautice -- call
nix run github:joonhoekim/nautice/v0.4.0 -- call   # pinned to a tag
nix profile install github:joonhoekim/nautice
./bin/nautice doctor                               # straight from a checkout

nix profile remove nautice                         # uninstall
```

</details>

## Requirements per platform

| | TTS | Playback | Banner | Notes |
|---|---|---|---|---|
| macOS | `say` (built in) | `afplay` (built in) | `osascript` (built in) | nothing to install |
| Windows | System.Speech (built in) | SoundPlayer (built in) | NotifyIcon (built in) | nothing to install |
| Linux | `espeak-ng` | one of `pw-play`, `paplay`, `aplay`, `ffplay`, `mpv` | `notify-send` | the nix package brings espeak-ng and libnotify |

`nautice doctor` shows what is missing and which backends are in use.

## Voice quality

**macOS is best.** The default voices are `compact` (small) or `eloquence`
(1980s formant synthesis). The good ones are the `(Premium)` / `(Enhanced)`
voices from **System Settings → Accessibility → Spoken Content → System Voice →
Manage Voices**. Once downloaded, `nautice` picks them automatically; run
`nautice cache clear` afterwards.

**Windows** only sees voices from installed language packs; a missing language
falls back to another voice. No quality tiers are exposed, so `best` equals
`auto`. `nautice doctor` lists the languages that have a voice.

**Linux's built-in voice is rough**, Korean especially: `espeak-ng` is formant
synthesis. A better engine can be plugged in per language — see below.

### Better engines (macOS, Linux)

`NAUTICE_TTS_CMD_<LANG>` sets a shell command for one language and
`NAUTICE_TTS_CMD` one for every other language. The command reads the text on
stdin and writes a WAV to `$NAUTICE_TTS_OUT`; `$NAUTICE_TTS_RATE` holds `--rate`.
If it fails — offline, say — the built-in engine speaks instead. Renders are
cached, so a repeated message does not run the command again. Nothing below is
bundled or required; copy what you want.

**[edge-tts](https://github.com/rany2/edge-tts)** — Microsoft's neural voices,
the best Korean here. Online, through an unofficial endpoint that may change.
Needs `edge-tts` and `ffmpeg` (it returns MP3). `edge-tts --list-voices` lists
voices (`ko-KR-SunHiNeural`, `ko-KR-InJoonNeural`, `en-US-AvaNeural`, …).

```sh
export NAUTICE_TTS_CMD_KO='edge-tts -v ko-KR-SunHiNeural -f /dev/stdin --write-media /dev/stdout \
  --rate "$(awk "BEGIN { printf \"%+d%%\", ($NAUTICE_TTS_RATE - 1) * 100 }")" \
  | ffmpeg -loglevel error -i pipe: -y "$NAUTICE_TTS_OUT"'
```

**[piper](https://github.com/OHF-Voice/piper1-gpl)** — local and fast on a CPU,
good English, no usable Korean voice. Download a voice (`.onnx` and
`.onnx.json`) from `rhasspy/piper-voices` on Hugging Face.

```sh
export NAUTICE_TTS_CMD_EN='piper -m ~/.local/share/piper/en_US-lessac-high.onnx \
  --length-scale "$(awk "BEGIN { print 1 / $NAUTICE_TTS_RATE }")" -f "$NAUTICE_TTS_OUT"'
```

**Hooks must see the variables too.** Set them where the agent inherits them —
your shell profile, or on NixOS `environment.sessionVariables` or home-manager's
`home.sessionVariables` (Nix strings only interpolate `${`, so the commands go in
unchanged), with `python3Packages.edge-tts`, `ffmpeg` or `piper-tts` installed.
`nautice doctor` lists the commands it sees, and `nautice say --plan "…"` prints
the one used as `backend_tts`. Details in [`docs/cli.md`](docs/cli.md) under
"TTS command".

## Wiring it to an agent

`nautice` is **not tied to any agent.** It only makes sounds and banners; when
to call it is up to the agent's configuration, whose file names and hook events
differ from agent to agent.

**The installer does not touch that configuration.** Instead, **ask your agent
to do it.** Paste the prompt below: the agent checks what `nautice` is, then
asks you how and where to wire it **by its own conventions**.

````markdown
Wire the notification CLI `nautice` into this environment.

## What it is

A notification tool that lets an agent get a human's attention: sound effects,
text-to-speech and OS notification banners behind one set of options. Behaves
the same on Windows, macOS and Linux. It is not tied to any agent — anything
that can run a shell command can use it, you included.

## Check first

- `nautice doctor` — whether it is installed and which backends work here
- `nautice --help` — commands and options; more accurate than this prompt

If `nautice` is missing, do not configure anything — tell me, so I can run the
one-line install from https://github.com/joonhoekim/nautice first.

## Two ways to wire it — they behave differently, so ask me which

**(1) Hooks / events — always fires.** Good moments are when you wait for me
and when you finish a turn. Never missed, but can be noisy.

**(2) You decide when to call it.** No hooks; just mention the tool in your
instructions file. **State that it does not fire automatically**, or it will
be called at random moments.

## Where — follow your own conventions

You know where your agent keeps its settings and what its hook events are
called. Use hooks if your agent has them; otherwise write to your instructions
file (`AGENTS.md` or similar). **Ask me whether it should be global or only for
this project.**

## Rules for hooks

- **Without `-a` the agent blocks until the sound ends.** Always use it in hooks.
- `-q` suppresses the status line — use it in hooks too.
- On Windows, call `nautice.cmd` instead of `nautice`.

## Things to consider

- If I am often away, `-c both` also shows a banner; adding `--hold` keeps the
  banner until I dismiss it.
- If sound is annoying, `-c visual` shows only the banner.
- Change the spoken text with `nautice say "..."`; the voice follows the
  text's language.
- `NAUTICE_CALL_MESSAGE` changes the default text of `nautice call`.

## Finally

Merge with existing settings instead of overwriting them. When done, trigger it
once so I can hear that it works.
````

<details>
<summary>Configuring it by hand</summary>

Hook settings look different in every agent. Below is a Claude Code example;
for other agents, adapt the names to their conventions. More in
[`docs/agent-setup.md`](docs/agent-setup.md).

```json
{
  "hooks": {
    "Notification": [
      { "matcher": "", "hooks": [{ "type": "command", "command": "nautice call -a -q" }] }
    ],
    "Stop": [
      { "matcher": "", "hooks": [{ "type": "command", "command": "nautice say -a -q 'Task finished'" }] }
    ]
  }
}
```

**Always pass `-a`** so the agent is not blocked. On Windows write
`nautice.cmd call -a -q`. If you are often away, add `-c both --hold` so the
banner stays until dismissed.

To let the agent decide instead of using hooks, add this to its instructions
file (`AGENTS.md`, `CLAUDE.md`, …):

```markdown
## Available tools

- `nautice` — a notification CLI that calls the human with sound. Run
  `nautice call -a -q`. It does not fire automatically — use it only when a long
  task finishes or a human decision is needed. `-c both` adds a banner,
  `--hold` keeps it until dismissed.
```

Stating that it "does not fire automatically" keeps the agent from calling it at
random moments.

</details>

## Layout

```
bin/nautice        bash   macOS · Linux (hands over to ps1 under Git Bash)
bin/nautice.ps1    ps1    Windows — must stay UTF-8 with BOM
bin/nautice.cmd           launcher for cmd
share/sounds/             sound effects shared by all three OSes
tools/gen-sounds.py       generates those sounds (standard library only)
install.sh                macOS · Linux installer
install.ps1               Windows installer
tools/mkdist              builds release assets (standard library only)
docs/cli.md               behaviour contract — the single source of truth
docs/install.md           install contract — the single source of truth
docs/agent-setup.md       wiring nautice to an agent
test/conformance          checks both implementations keep the contract
```

**There are two implementations, so never change just one.** Update
`docs/cli.md` first, then both sides, then run `./test/conformance`. Sound
cannot be compared, so the test compares what `--plan` prints — any field that
must not depend on the OS has to match. Contributor rules are in
[`AGENTS.md`](AGENTS.md).

```sh
./test/conformance     # without pwsh only the bash side runs, comparisons are skipped
nix build .#nautice    # includes shellcheck
```

## Behaviour

- **Cache** — `$NAUTICE_CACHE/<version>/`, keyed by
  `sha1(platform|voice|rate|text)`; an upgrade starts a fresh cache. The hash
  tool is `sha1sum`, then `shasum`, then `md5sum`; macOS has only `shasum`,
  a perl script that is slower and warns under a missing locale.
- **Lock** — held only during playback; rendering may run in parallel. Without
  `flock` it falls back to a mkdir lock and gives up after 30 s and plays anyway —
  overlapping sound beats silently losing a notification.
- **Voice check** — `say` accepts an unknown voice with exit 0 and quietly uses
  the default one, so a typo would go unnoticed. `nautice` checks the name
  first and fails if it does not exist.
- **Language detection** — the script of the text decides the language: Hangul,
  kana, Han, Cyrillic, Greek, Arabic, Hebrew, Thai and Devanagari are recognised.
  Latin text cannot tell its language, so the OS locale decides, falling back to
  `en` without a locale or with a non-Latin one. `--lang` overrides it. The bash
  side reads UTF-8 bytes rather than regex ranges — with `LC_CTYPE=C` a range
  like `[가-힣]` matches everything.
- **Banner** — enabled with `--channel`. Shown once regardless of `--repeat`;
  copies piling up in the notification center are noise. Exit 0 does not prove
  a banner appeared: without notification permission or under Focus it is
  silently suppressed. On macOS `osascript` shows it, so look for **Script
  Editor** in the notification settings.
- **`afplay` startup** — about 0.95 s (1.38 s to play a 0.43 s file, macOS 26 /
  Apple silicon), longer than a short chime. Hooks detach with `-a`, so it is
  not felt there.

## Environment variables

`NAUTICE_VOICE` `NAUTICE_VOICE_<LANG>` `NAUTICE_LANG` `NAUTICE_VOL` `NAUTICE_RATE`
`NAUTICE_CHANNEL` `NAUTICE_CALL_MESSAGE` `NAUTICE_CACHE` `NAUTICE_SOUNDS`
`NAUTICE_PIPER_MODEL` `NAUTICE_TTS_CMD` `NAUTICE_TTS_CMD_<LANG>`

Details in [`docs/cli.md`](docs/cli.md), including which parts are a stable
interface ("Compatibility").
