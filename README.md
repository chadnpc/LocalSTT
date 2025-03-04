
 # [![Image](https://github.com/user-attachments/assets/02f75c8c-77d8-40a2-923d-28e2437091d9)](https://www.powershellgallery.com/packages/LocalSTT)

Speech to text & transcription module.

Core modules:

- [`Pyaudio`(Pa_INT16)](https://people.csail.mit.edu/hubert/pyaudio/): recording

- [`WhisperModel`(CPU_INT8)](https://github.com/openai/whisper): transcription.

PowerShell is used here to improve the cli experience (setup, environment and
updates).

## [📦 Installation](README.md)

```PowerShell
Install-Module LocalSTT
```

## [🗒 Usage](docs/Readme.md)

```PowerShell
Import-Module LocalSTT

Record-Audio -o output.wav # works fine

# Transcribe-Audio output.wav ## !? https://github.com/OpenNMT/CTranslate2/pull/1852
```


## STATUS

- Record-Audio works
- currently Works with Python <= 3.12 : [faster-whisper/issues/1238](https://github.com/SYSTRAN/faster-whisper/issues/1238)

- Transcribe-Audio with ctranslate2 is not working : [OpenNMT/CTranslate2/pull/1852](https://github.com/OpenNMT/CTranslate2/pull/1852)

## [🧾 License](LICENSE)

This project is licensed under the [WTFPL License](LICENSE).
