# CLI contract

English · [한국어](cli.ko.md)

`bin/nautice` (bash, macOS and Linux) and `bin/nautice.ps1` (Windows) are **two
implementations of one behaviour.** Under Git Bash / MSYS the bash side hands
over to `nautice.ps1`, so one name works on all three OSes. This document is the
single source of truth; never change only one implementation —
`test/conformance` runs its cases against both and catches divergence.

## Commands

| Command | Does |
|---|---|
| `nautice say <text>` | Speaks the text; stdin if omitted |
| `nautice play <name\|path>` | Plays a sound effect |
| `nautice alert <text>` | Plays a sound, then speaks the text |
| `nautice call [text]` | Calls the human: `alert` + default text + `--repeat 2` |
| `nautice list [voices\|sounds]` | Lists sounds, or voices for every language grouped by language |
| `nautice doctor` | Checks the environment and lists the languages that have a voice; 0 when healthy |
| `nautice cache [info\|clear]` | Render cache |
| `nautice update` | Updates this installation from the latest release |

`call` speaks `Your agent is calling` by default. The
tool is not tied to any agent; to name yours, set `NAUTICE_CALL_MESSAGE`. It is
spoken twice, so keep it short.

## Options

| Option | Default | Unit / range |
|---|---|---|
| `-v, --voice NAME` | `auto` | Voice name. `auto` = chosen by the text's language, `best` = highest quality |
| `-l, --lang CODE` | `auto` | Two-letter language code (`ko`, `ja`, `de`, …). `auto` = detected from the text |
| `-V, --vol N` | `0.6` | **0.0 – 1.0**, the same unit on every OS. Up to 10 is accepted; above 1.0 backends amplify or clip |
| `-r, --rate N` | `1.0` | **Speed multiplier.** 1.0 = normal, 1.5 = 1.5× faster |
| `-t, --tone NAME` | `ask` | Sound used by `alert` / `call` |
| `-c, --channel NAME` | `sound` | `sound` / `visual` / `both`. `play` accepts only `sound` |
| `--hold` | off | Keep the banner until dismissed. Visual channel only |
| `-n, --repeat N` | `1` | **Integer** 1 – 20. `call` defaults to 2 |
| `-g, --gap SEC` | `0.4` | Pause between repetitions |
| `-a, --async` | off | Return without waiting. Required in hooks |
| `-q, --quiet` | off | No status line |
| `-h, --help` / `--version` | | |
| `--plan` | off | Print the resolved plan without sound. For `test/conformance` |

Everything after `--` is text.

### Language detection

The language picks the voice. `--plan` prints it as `lang`.

```
1. --lang, unless it is auto
2. otherwise, the language of any non-Latin script in the text
3. otherwise, the OS locale's language — en if there is no locale or it is non-Latin
```

**Step 2 needs no configuration:** the script itself tells the language.

| Script | Unicode | Language |
|---|---|---|
| Hangul syllables | U+AC00–D7A3 | `ko` |
| Kana | U+3040–30FF | `ja` |
| Han | U+4E00–9FFF | `zh` |
| Cyrillic | U+0400–04FF | `ru` |
| Greek | U+0370–03FF | `el` |
| Arabic | U+0600–06FF | `ar` |
| Hebrew | U+0590–05FF | `he` |
| Thai | U+0E00–0E7F | `th` |
| Devanagari | U+0900–097F | `hi` |

One character is enough. With several scripts, **table order wins** — kana
makes it Japanese even alongside Han. For mixed text, that language's voice
reading English is easier to follow than the reverse.

**Step 3 (Latin) cannot be decided from text:** `Der Build ist fertig` and
`The build is finished` use the same script. So the OS locale (`LANG` /
`LC_MESSAGES`, `CurrentCulture` on Windows) is the default. A non-Latin locale
(`ko`, `ja`, `zh`, `ru`, …) is not used — a Korean locale must not read English
text with a Korean voice — and without a locale (cron, systemd, containers) the
result is `en`.

`--lang` and `NAUTICE_LANG` override all of this.

### When the language has no voice

**No failure.** A notification in the wrong accent beats no notification — the
same call as the lock timeout. nautice falls back to an available voice and the
status line names the voice actually used. `nautice doctor` lists the languages
that have a voice.

To pin a voice per language, use `NAUTICE_VOICE_<LANG>` (`NAUTICE_VOICE_KO`,
`NAUTICE_VOICE_JA`, …).

### Channels

How a notification reaches the human. Sound is the default; the visual channel
is an OS notification banner.

| Value | Does |
|---|---|
| `sound` | Sound only. Default |
| `visual` | Banner only; the TTS backend is never called |
| `both` | Banner first, then sound |

The banner's title is `nautice` and its body is the text.

**Banners ignore `--repeat`:** shown once however many repetitions — copies
piling up in the notification center are unreadable. `--repeat` and `--gap`
apply to the sound channel only.

`play` has no text for a banner, so `play --channel visual` and
`play --channel both` exit 1.

#### `--hold`

Banners normally disappear on their own. With `--hold` they stay **until
dismissed**, so a notification that arrives while you are away is not missed.

It does not apply to sound. `--channel sound --hold` has no banner to hold and
does nothing — it does not exit 1, so the same command still works where
`NAUTICE_CHANNEL` differs between machines.

**Only Windows guarantees persistence.** Elsewhere it is as good as the backend
allows — see "Platform differences".

| | Banner backend | Needs |
|---|---|---|
| macOS | `osascript` `display notification` | nothing (built in) |
| Linux | `notify-send` | `libnotify` and a notification daemon |
| Windows | `System.Windows.Forms.NotifyIcon` balloon | nothing (built in) |

`--plan` prints the channel as `channel`, `--hold` as `hold` (`0` / `1`), and the
OS's banner backend as `backend_visual`. On Windows `--hold` changes the backend,
so `backend_visual` changes with it.

### Lead-in silence

Some outputs drop the start of a sound that follows a quiet spell: on an HDMI
display, `say "Build finished"` after 12 s of silence played only "finished",
and `play` can lose a short chime whole. So each repetition starts with
`NAUTICE_PREROLL` seconds of silence (**default 0.25**, `0` turns it off,
0 – 2) — in the same stream as the sound, since only that helped.

It goes before the first sound of a repetition only: `alert` gets it before the
chime, not between chime and speech. `--plan` prints it as `preroll`.

Measured on that display (PipeWire, 12 s idle between tries): 0.03 s and 0.08 s
still clipped, 0.15 s and more did not. Keeping PipeWire from suspending the
sink did not help. The default leaves room for slower devices.

### TTS command

The built-in engines (`say`, `espeak-ng`, SAPI) are what every machine has; a
better one can be plugged in on the bash side (macOS, Linux) as a shell command.
`NAUTICE_TTS_CMD_<LANG>` (`NAUTICE_TTS_CMD_KO`, …) speaks one language,
`NAUTICE_TTS_CMD` every language that has no command of its own. They take
precedence over `NAUTICE_PIPER_MODEL` and the built-in engine.

The command runs under `sh -c` and gets:

| | |
|---|---|
| stdin | The text |
| `NAUTICE_TTS_OUT` | Path of the WAV file to write |
| `NAUTICE_TTS_LANG` | The resolved language (`ko`, `en`, …) |
| `NAUTICE_TTS_RATE` | `--rate` as given, a multiplier; converting it is up to the command |

It must write a WAV (RIFF/WAVE) to `NAUTICE_TTS_OUT` and exit 0. nautice adds
the lead-in, applies `--vol` at playback and caches the file like any other
rendering — keyed by the command, language, rate and text, so editing the
command renders anew.

**A failing command does not fail the notification.** A non-zero exit, no WAV,
or no exit within 15 s (where `timeout` exists) prints a warning on stderr and
the built-in engine speaks instead: a cloud engine gone offline must not cost
the notification. `--voice` applies to the built-in engine only.

`--plan` prints the engine as `backend_tts`: the variable's name
(`NAUTICE_TTS_CMD_KO`) when a command applies, otherwise `say`, `piper`,
`espeak-ng` or `sapi`. `nautice doctor` lists the commands that are set.

### Why these units

`--vol` and `--rate` have different native units on each OS. The contract uses
OS-neutral units; each implementation converts to its backend.

| | Contract | macOS | Linux | Windows |
|---|---|---|---|---|
| Volume | `0.0–1.0` | `afplay -v` as is | per player | SAPI `Volume` = `×100` |
| Rate | `1.0` = normal | `say -r` = `×175` wpm | `espeak-ng -s` = `×175` wpm | SAPI `Rate` = `round(10·log₃(rate))` |

Windows SAPI `Rate` is −10 – 10 and speed is roughly `3^(Rate/10)`, so the
inverse `10·log₃(rate)` is used and clamped to −10 – 10.

## Updating

`nautice update` downloads the installer from the latest release and runs it
with `NAUTICE_PREFIX` set to this installation's prefix — the install logic
lives only in the installers. `NAUTICE_VERSION` and `NAUTICE_ARCHIVE` pass
through, so `NAUTICE_VERSION=v0.4.0 nautice update` installs that version.

It only updates installs made by the installers, recognised by the layout
`<prefix>/bin` + `<prefix>/share/nautice/sounds`. A nix install (under
`/nix/store`) exits 1 pointing to `nix profile upgrade`; anything else, such as
a repository checkout, exits 1 asking to update it the way it was installed.

The notification commands never touch the network: hooks call them and they
must stay fast and work offline.

## Cache

The bash side caches rendered speech and its voice choices (the voice list and
the voice picked per language) under `$NAUTICE_CACHE/<version>/`. **A cache
belongs to one version:** choices made by an older version's logic would
otherwise keep being used after an upgrade, with no sign of it. On start,
nautice removes caches left by other versions — only files it writes itself,
since `NAUTICE_CACHE` may point at a shared directory. `nautice cache clear`
removes everything it wrote, for every version. Windows has no cache.

## Sound names

`ok` `error` `warn` `ask` `start` `notify` — each is `share/sounds/<name>.wav`.
All three OSes play **the same files**; a notification sound must not mean
different things on different machines.

Other values are tried as a path, then as an OS sound
(macOS `/System/Library/Sounds/<name>.aiff`, Windows `C:\Windows\Media\<name>.wav`).

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Bad argument, unknown voice or sound, missing backend |

`--async` detaches only after validating arguments, so bad input still exits 1
right away.

## Compatibility

Agent hooks and instructions call nautice by option name, so a renamed option
breaks them silently. **This contract is the public API:** commands, options,
their units and ranges, environment variables, sound names and exit codes.
Not part of it: `--plan` output (a test aid), the wording of status lines,
errors and `doctor`, and the cache layout.

- **Removing or renaming** an option or environment variable: the old name keeps
  working for at least one minor release and prints a deprecation warning on
  stderr, then it goes.
- **Versions:** while 0.x, a breaking change bumps the minor version and
  everything else the patch version. From 1.0, semantic versioning.
- **Changed defaults** (such as `call`'s text) are not breaking, but are called
  out in the release notes.

## Platform differences (intended)

Backend limits, not bugs. The conformance test allows exactly these.

- **Lead-in on sounds that are not PCM WAV** — silence is spliced into WAV
  files, which covers every bundled sound. macOS system sounds (`.aiff`) and
  8-bit WAVs, where silence is not zero bytes, play without it. Speech gets it
  from the synthesiser on macOS (`say`'s `[[slnc]]`) and Windows
  (`PromptBuilder.AppendBreak`).
- **Windows sound volume** — `System.Media.SoundPlayer` has no volume. `--vol`
  applies to TTS only; sounds play at system volume.
- **Linux TTS quality** — `espeak-ng` is formant synthesis and rough for Korean;
  `piper` has no usable official Korean voice. `NAUTICE_PIPER_MODEL` selects a
  model and takes precedence; a TTS command takes precedence over both.
- **TTS command** — bash side only. Its value is a POSIX shell command, which
  Windows has no `sh` to run; `nautice doctor` there names any that are set as
  ignored.
- **Voice `best`** — only macOS exposes quality tiers (`(Premium)` /
  `(Enhanced)`). Elsewhere `best` equals `auto`.
- **Queue (serialisation)** — only the bash side locks. Windows `Speak()` is
  synchronous, so one process is serial by nature, but several can overlap.
- **Render cache** — bash side only. `say` and `espeak-ng` take no playback
  volume, so speech is rendered to a file anyway. SAPI takes volume and rate at
  synthesis time, so Windows has no cache and `nautice cache` says so.
- **`voice` in `--plan`** — bash prints the resolved name (`Yuna (Premium)`),
  Windows leaves it empty because resolving needs `System.Speech`. Compare
  `voice_req` and `lang` instead.
- **macOS banners belong to Script Editor** — `osascript` shows them, so they
  are grouped under `Script Editor` in the notification center and in System
  Settings → Notifications. The title reads `nautice`, but allowing or muting
  them is done on Script Editor (measured on macOS 26).
- **Whether a banner appeared cannot be known** — `osascript` exits 0 without
  notification permission or under Focus, and `notify-send` does when the daemon
  drops the message. Exit 0 only means the backend was called — the same kind of
  silent failure as `say -v NoSuchVoice`.
- **Windows banner lifetime** — a `NotifyIcon` balloon shows only while the
  process holds its tray icon, so Windows alone holds it briefly (2 s) before
  cleaning up. macOS and Linux hand off to a daemon and return at once. Hooks
  detach with `-a`, so the difference is invisible there.
- **Windows banners need a desktop session** — services and headless sessions
  have no tray, so no balloon appears.
- **How well `--hold` holds differs per OS** — only Windows guarantees it.
  - Windows: balloons expire, so `--hold` switches to a WinRT toast
    (`scenario="reminder"`) that stays until dismissed and outlives the process
    (still in the notification center 10 s after the child exited, measured).
    The balloon lifetime limit and 2 s hold do not apply then.
  - Linux: `notify-send -t 0`. "Never expire" is **only a hint** and daemons may
    ignore it — GNOME Shell does.
  - macOS: **does nothing.** Banner vs. persistent alert is a per-app user
    setting in System Settings → Notifications and cannot be changed from code.
    For persistence, set Script Editor's alert style to "Alerts".
- **With `--hold`, Windows banners belong to Windows PowerShell** — a WinRT toast
  needs a registered AppUserModelID, so Windows PowerShell's is borrowed and the
  toast is grouped under it in notification settings, like Script Editor on
  macOS. Plain `NotifyIcon` balloons are not affected.
- **Which languages have voices depends on the machine** — macOS ships voices
  for about 40 languages; Linux `espeak-ng` synthesises 140 (roughly). **Windows
  is weakest** — only installed language packs have voices; otherwise see "When
  the language has no voice".

## Environment variables

| Name | Meaning |
|---|---|
| `NAUTICE_VOICE` | Default voice (`auto` / `best` / a name) |
| `NAUTICE_VOICE_<LANG>` | Voice for one language: `NAUTICE_VOICE_KO`, `NAUTICE_VOICE_JA`, … |
| `NAUTICE_LANG` | Default language; `auto` uses the detection above |
| `NAUTICE_VOL` `NAUTICE_RATE` | Default volume and rate |
| `NAUTICE_CHANNEL` | Default channel (`sound` / `visual` / `both`) |
| `NAUTICE_CALL_MESSAGE` | Default text of `call` |
| `NAUTICE_PREROLL` | Seconds of silence before each repetition; see "Lead-in silence" |
| `NAUTICE_SOUNDS` | Bundled sound directory; if empty, `../share/sounds` next to the executable |
| `NAUTICE_CACHE` | Cache location (bash side only); data goes in a per-version subdirectory |
| `NAUTICE_PIPER_MODEL` | piper `.onnx` model to use on Linux |
| `NAUTICE_TTS_CMD` `NAUTICE_TTS_CMD_<LANG>` | Shell command that renders speech (bash side only); see "TTS command" |
