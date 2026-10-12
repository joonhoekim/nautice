# Your own voice, offline

English · [한국어](local-voices.ko.md)

nautice's built-in engines (`say`, `espeak-ng`, SAPI) are the floor every
machine has. Any speech model you can run yourself — on a CPU, a GPU or an NPU —
can speak nautice's notifications instead, with the voice you pick, and without
a network. This page is about how to set that up in general; the exact model,
runtime and drivers depend on your machine and are left to you.

The interface is the TTS command in [`cli.md`](cli.md#tts-command) (macOS and
Linux): nautice runs a shell command with the text on stdin and plays the WAV it
writes.

## What nautice gives the command

| | |
|---|---|
| stdin | The text |
| `NAUTICE_TTS_OUT` | Where to write the WAV |
| `NAUTICE_TTS_LANG` | The language (`ko`, `ja`, `en`, …) |
| `NAUTICE_TTS_RATE` | `--rate`, a multiplier |
| `NAUTICE_TTS_VOICE` | The voice you named, or empty |

`NAUTICE_TTS_CMD` covers every language, `NAUTICE_TTS_CMD_<LANG>` one language,
so one model can speak Korean while another speaks Japanese.

## Picking a voice

nautice does not know your model's voices; it passes the name through. Name one
per call, per language, or for everything:

```sh
nautice say -v M3 "…"           # this call
export NAUTICE_VOICE_JA=voice-a # every Japanese notification
export NAUTICE_VOICE=voice-b    # everything else
```

`NAUTICE_TTS_VOICE` is empty when no voice is named (`auto`, `best`); the
command then uses its own default. The voice is part of the cache key, so
switching voices renders anew.

## Choosing a model

- **Languages.** Many models speak a few languages well and others not at all.
  Check the ones your notifications use.
- **Fixed voices or cloning.** Some models ship a set of named voices; others
  imitate a short reference recording. Cloning someone's voice needs their
  consent, and many model licences forbid it without.
- **Licences.** Code, weights and each voice can have separate terms — credit
  lines, non-commercial use, no redistribution. Read all three.
- **Speed.** A notification is short, but nautice waits at most 15 s for the
  command (see below). Models that generate the whole utterance at once
  (VITS-style, flow matching) are usually faster than ones that generate it
  token by token (LLM-based).

## Where it runs

The command is yours, so it can use whatever the machine has.

- **CPU** — the simplest, and often enough for small models.
- **GPU** — through the model's runtime (CUDA, Metal, Vulkan, ROCm, DirectML,
  …). Worth it for larger models; the first call pays for loading.
- **NPU** — through the vendor's runtime (Core ML, ONNX Runtime execution
  providers, vendor SDKs). Often the fastest and most frugal, but models usually
  need converting first, and many NPUs want fixed tensor shapes: pad the text to
  a few fixed lengths and trim the audio.

Whatever runs it, the command only has to leave a WAV at `NAUTICE_TTS_OUT` and
exit 0.

## Writing the command

Point the variable at a small script rather than a long one-liner:

```sh
#!/bin/sh
# Reads the text on stdin, writes $NAUTICE_TTS_OUT.
exec my-tts --voice "${NAUTICE_TTS_VOICE:-default}" \
  --speed "$NAUTICE_TTS_RATE" --out "$NAUTICE_TTS_OUT"
```

```sh
export NAUTICE_TTS_CMD_JA=~/.local/bin/nautice-tts-ja
nautice doctor             # lists the commands it sees
nautice say --plan "テスト" # backend_tts names the one used
```

Things to keep in mind:

- **Failure is safe.** A non-zero exit, no WAV, or no exit within 15 s makes
  nautice warn on stderr and speak with the built-in engine. An unknown voice
  name may simply fail.
- **Keep it under 15 s.** Loading a large model on every call can take longer
  than speaking. Use a smaller model, a faster device, or keep the model loaded
  in a local server the command talks to.
- **Fall back inside the command if you like.** A script can try the NPU, then
  the CPU, then another engine, and exit non-zero only when all fail.
- **Renders are cached.** The same text, language, rate and voice plays the
  cached file without running the command again.
- **Hooks must see the variables.** Set them where the agent inherits them
  (see the README).
