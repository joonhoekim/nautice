# 원하는 목소리를 오프라인으로

[English](local-voices.md) · 한국어

nautice 의 내장 엔진(`say`, `espeak-ng`, SAPI)은 어느 기기에나 있는 최소한이다.
직접 돌릴 수 있는 음성 모델이라면 CPU 든 GPU 든 NPU 든 무엇이든 nautice 의 알림을
대신 읽을 수 있다. 고른 목소리로, 네트워크 없이. 이 문서는 일반적인 방법만 다룬다.
어떤 모델 · 런타임 · 드라이버를 쓸지는 기기마다 달라서 각자 정한다.

연결 지점은 [`cli.md`](cli.ko.md) 의 TTS 명령이다(macOS, Linux). nautice 는 셸
명령에 stdin 으로 텍스트를 주고, 명령이 쓴 WAV 를 재생한다.

## nautice 가 명령에 주는 것

| | |
|---|---|
| stdin | 텍스트 |
| `NAUTICE_TTS_OUT` | WAV 를 쓸 경로 |
| `NAUTICE_TTS_LANG` | 언어 (`ko`, `ja`, `en`, …) |
| `NAUTICE_TTS_RATE` | `--rate` 배속 |
| `NAUTICE_TTS_VOICE` | 지정한 보이스, 없으면 빈 값 |

`NAUTICE_TTS_CMD` 는 모든 언어를, `NAUTICE_TTS_CMD_<LANG>` 는 한 언어를 맡는다.
한국어는 한 모델이, 일본어는 다른 모델이 읽게 할 수 있다.

## 보이스 고르기

nautice 는 모델의 보이스를 모른다. 이름을 그대로 넘길 뿐이다. 호출마다, 언어마다,
또는 전체에 지정한다.

```sh
nautice say -v M3 "…"           # 이번 호출
export NAUTICE_VOICE_JA=voice-a # 일본어 알림 전부
export NAUTICE_VOICE=voice-b    # 그 밖의 전부
```

보이스를 지정하지 않으면(`auto`, `best`) `NAUTICE_TTS_VOICE` 는 빈 값이고, 명령이
자기 기본값을 쓴다. 보이스는 캐시 키에 들어가므로 바꾸면 새로 렌더한다.

## 모델 고르기

- **언어.** 몇 개 언어는 잘하고 나머지는 전혀 못 하는 모델이 많다. 알림에 쓰는
  언어를 확인한다.
- **고정 보이스인가, 클로닝인가.** 이름 붙은 보이스 세트를 주는 모델도, 짧은 참조
  녹음을 흉내 내는 모델도 있다. 남의 목소리를 클로닝하려면 본인 동의가 필요하고,
  동의 없는 클로닝을 금지하는 모델 라이선스도 많다.
- **라이선스.** 코드 · 가중치 · 보이스마다 조건이 따로일 수 있다(크레딧 표기,
  비상업, 재배포 금지). 셋 다 읽는다.
- **속도.** 알림은 짧지만 nautice 는 명령을 최대 15초 기다린다(아래). 발화 전체를
  한 번에 만드는 모델(VITS 계열, flow matching)이 토큰을 하나씩 만드는 모델(LLM
  기반)보다 대개 빠르다.

## 어디서 돌리나

명령은 사용자의 것이라 기기에 있는 무엇이든 쓸 수 있다.

- **CPU** — 가장 간단하고, 작은 모델에는 대개 충분하다.
- **GPU** — 모델의 런타임으로(CUDA, Metal, Vulkan, ROCm, DirectML, …). 큰 모델에
  값어치가 있다. 첫 호출은 로딩 비용을 치른다.
- **NPU** — 벤더 런타임으로(Core ML, ONNX Runtime 실행 공급자, 벤더 SDK). 대개 가장
  빠르고 전력도 적게 들지만 보통 모델을 먼저 변환해야 하고, 고정된 텐서 크기를
  요구하는 NPU 가 많다. 텍스트를 몇 가지 고정 길이로 채우고 오디오를 잘라 낸다.

무엇으로 돌리든 명령은 `NAUTICE_TTS_OUT` 에 WAV 를 남기고 0 으로 끝나기만 하면 된다.

## 명령 쓰기

긴 한 줄 대신 작은 스크립트를 가리킨다.

```sh
#!/bin/sh
# stdin 의 텍스트를 읽어 $NAUTICE_TTS_OUT 에 쓴다.
exec my-tts --voice "${NAUTICE_TTS_VOICE:-default}" \
  --speed "$NAUTICE_TTS_RATE" --out "$NAUTICE_TTS_OUT"
```

```sh
export NAUTICE_TTS_CMD_JA=~/.local/bin/nautice-tts-ja
nautice doctor             # 보이는 명령을 나열한다
nautice say --plan "テスト" # backend_tts 가 쓰인 명령이다
```

알아 둘 것:

- **실패해도 안전하다.** 0 이 아닌 종료, WAV 없음, 15초 안에 안 끝남이면 nautice 가
  stderr 에 경고하고 내장 엔진으로 읽는다. 모르는 보이스 이름이면 그냥 실패해도 된다.
- **15초 안에 끝낸다.** 큰 모델을 매번 로딩하면 말하는 것보다 오래 걸릴 수 있다.
  작은 모델이나 빠른 장치를 쓰거나, 모델을 띄워 둔 로컬 서버에 명령이 붙게 한다.
- **원하면 명령 안에서 대체한다.** 스크립트가 NPU, 다음에 CPU, 다음에 다른 엔진을
  시도하고 모두 실패할 때만 0 이 아닌 값으로 끝나게 할 수 있다.
- **렌더는 캐시된다.** 텍스트 · 언어 · 배속 · 보이스가 같으면 명령을 다시 돌리지 않고
  캐시된 파일을 재생한다.
- **훅도 변수를 봐야 한다.** 에이전트가 물려받는 곳에 설정한다(README 참고).
