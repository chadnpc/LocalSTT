docs

## Overview

LocalSTT goals is to provide functions for recording audio and transcribing it
to text using locally available resources.

Current version uses

- Whisper for speech recognition and transcription
- pyaudio for recording audio.

## Features

- Record audio from the default microphone.
- Transcribe audio files to text.
- Specify output file for recordings and transcriptions.
- Control recording duration.

## Installation

1. Ensure you have PowerShell 7 or later installed.
2. Clone the LocalSTT repository:

   ```powershell
   git clone https://github.com/alainQtec/LocalSTT.git
   ```
3. Navigate to the cloned directory:

   ```powershell
   cd LocalSTT
   ```

The mdule will take care of installing the required Python dependencies and
managing the virtual environments.

pip requirements are stored in Private/requirements.txt

4. Import the module:

   ```powershell
   Import-Module LocalSTT
   ```

## Usage

### `Get-Transcript`

Gets the transcript of an audio file.

**Syntax:**

```powershell
Get-Transcript [-Path] <FileInfo> [[-OutFile] <string>] [<CommonParameters>]
```

**Parameters:**

- `-Path <FileInfo>`: The path to the audio file. (Required)
- `-OutFile <string>`: The path to save the transcript. If not specified, a
  temporary file will be used and deleted afterward. (Optional)

**Example:**

```powershell
$transcript = Get-Transcript -Path "audio.wav"
Write-Host $transcript
```

### `Receive-Audio` (Alias: `Record-Audio`)

Records audio from the default microphone and saves it to a file.

**Syntax:**

```powershell
Receive-Audio [[-OutFile] <string>] [[-Duration] <float>] [<CommonParameters>]
```

**Parameters:**

- `-OutFile <string>`: The path to save the recorded audio. If not specified,
  the audio will be saved to the current directory. (Optional)
- `-Duration <float>`: The duration of the recording in minutes. Default is 0.5
  (30 seconds). (Optional)

**Examples:**

```powershell
# Record audio for 30 seconds and save it to the current directory
Record-Audio

# Record audio for 30 seconds and save it to "my_recording.wav"
Record-Audio -o "my_recording.wav" -d .5
```

---
