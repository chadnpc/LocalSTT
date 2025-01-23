# [LocalStt ၊▹](https://www.powershellgallery.com/packages/LocalSTT)

A module for speech to text & transcription stuff without leaving your terminal.

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

Record-Audio -o output.wav

Transcribe-Audio output.wav
```

## [🧾 License](LICENSE)

This project is licensed under the [WTFPL License](LICENSE).
