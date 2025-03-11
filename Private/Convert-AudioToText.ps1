function Convert-AudioToText {
  [CmdletBinding(DefaultParameterSetName = 'Local')]
  param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
    [string[]]$AudioFile,

    [Parameter(ParameterSetName = 'Local')]
    [Parameter(ParameterSetName = 'API')]
    [ValidateSet("transcribe", "translate")]
    [string]$Task = "transcribe",

    [Parameter(ParameterSetName = 'Local')]
    [ValidateSet("tiny", "base", "small", "medium", "large-v1", "large-v2")]
    [string]$Model = "small",

    [Parameter(ParameterSetName = 'Local')]
    [Parameter(ParameterSetName = 'API')]
    # [ValidateSet("Auto-Detect", "Afrikaans", "Albanian", "Amharic", "Arabic", "Armenian", "Assamese", "Azerbaijani", "Bashkir", "Basque", "Belarusian", "Bengali", "Bosnian", "Breton", "Bulgarian", "Burmese", "Castilian", "Catalan", "Chinese", "Croatian", "Czech", "Danish", "Dutch", "English", "Estonian", "Faroese", "Finnish", "Flemish", "French", "Galician", "Georgian", "German", "Greek", "Gujarati", "Haitian", "Haitian Creole", "Hausa", "Hawaiian", "Hebrew", "Hindi", "Hungarian", "Icelandic", "Indonesian", "Italian", "Japanese", "Javanese", "Kannada", "Kazakh", "Khmer", "Korean", "Lao", "Latin", "Latvian", "Letzeburgesch", "Lingala", "Lithuanian", "Luxembourgish", "Macedonian", "Malagasy", "Malay", "Malayalam", "Maltese", "Maori", "Marathi", "Moldavian", "Moldovan", "Mongolian", "Myanmar", "Nepali", "Norwegian", "Nynorsk", "Occitan", "Panjabi", "Pashto", "Persian", "Polish", "Portuguese", "Punjabi", "Pushto", "Romanian", "Russian", "Sanskrit", "Serbian", "Shona", "Sindhi", "Sinhala", "Sinhalese", "Slovak", "Slovenian", "Somali", "Spanish", "Sundanese", "Swahili", "Swedish", "Tagalog", "Tajik", "Tamil", "Tatar", "Telugu", "Thai", "Tibetan", "Turkish", "Turkmen", "Ukrainian", "Urdu", "Uzbek", "Valencian", "Vietnamese", "Welsh", "Yiddish", "Yoruba")]
    [string]$Language = "Auto-Detect",

    [Parameter(ParameterSetName = 'Local')]
    [Parameter(ParameterSetName = 'API')]
    [string]$Prompt,

    [Parameter(ParameterSetName = 'Local')]
    [Parameter(ParameterSetName = 'API')]
    [bool]$CoherencePreference = $true,

    [Parameter(ParameterSetName = 'API')]
    [string]$ApiKey,

    [Parameter(ParameterSetName = 'Local')]
    [Parameter(ParameterSetName = 'API')]
    [string]$OutputFormats = "txt,vtt,srt,tsv,json",

    [Parameter(ParameterSetName = 'Local')]
    [Parameter(ParameterSetName = 'API')]
    [string]$OutputDir = "audio_transcription",

    [Parameter(ParameterSetName = 'Local')]
    [Parameter(ParameterSetName = 'API')]
    [string]$DeeplApiKey,

    [Parameter(ParameterSetName = 'Local')]
    [Parameter(ParameterSetName = 'API')]
    # [ValidateSet("Bulgarian", "Chinese", "Chinese (simplified)", "Czech", "Danish", "Dutch", "English", "English (American)", "English (British)", "Estonian", "Finnish", "French", "German", "Greek", "Hungarian", "Indonesian", "Italian", "Japanese", "Korean", "Latvian", "Lithuanian", "Norwegian", "Polish", "Portuguese", "Portuguese (Brazilian)", "Portuguese (European)", "Romanian", "Russian", "Slovak", "Slovenian", "Spanish", "Swedish", "Turkish", "Ukrainian")]
    [string]$DeeplTargetLanguage,

    [Parameter(ParameterSetName = 'Local')]
    [Parameter(ParameterSetName = 'API')]
    [bool]$DeeplCoherencePreference = $true,

    [Parameter(ParameterSetName = 'Local')]
    [Parameter(ParameterSetName = 'API')]
    [ValidateSet("default", "formal", "informal")]
    [string]$DeeplFormality = "default",

    [Parameter(ParameterSetName = 'Local')]
    [switch]$SkipInstall

  )

  begin {
    # --- Setup & Dependencies ---
    Write-Host "AudioToText CLI" -ForegroundColor Green

    # Check for ffmpeg
    if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
      Write-Warning "ffmpeg is not installed.  Please install it from https://ffmpeg.org/download.html"
      return # Exit the function.  Critical error.
    }


    if (-not $SkipInstall) {
      Write-Host "Installing/Updating required Python packages..."

      # Use Invoke-Expression (iex) for complex commands, better error handling than &
      Invoke-Expression "python -m pip install --user --upgrade pip" #upgrades the user pip to avoid errors
      Invoke-Expression "python -m pip install git+https://github.com/openai/whisper.git@v20231117 openai==1.9.0 numpy scipy deepl pydub cohere ffmpeg-python torch==2.1.0 tensorflow-probability==0.23.0 typing-extensions==4.9.0"

      if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to install Python dependencies. Please check the error output above."
        return # Exit the function.
      }
    }


    # --- Helper Functions (PowerShell equivalents of Python code) ---

    function Invoke-Whisper {
      param(
        [string]$AudioPath,
        [hashtable]$WhisperOptions
      )

      $command = "whisper `"$AudioPath`""
      foreach ($key in $WhisperOptions.Keys) {
        $value = $WhisperOptions[$key]
        if ($value -is [bool]) {
          if ($value) {
            $command += " --$key"
          }
        } elseif ($value -ne $null -and $value -ne "") {
          # Check for null or empty string.
          $command += " --$key `"$value`""
        }
      }
      Write-Verbose "Executing Whisper command: $command"
      Invoke-Expression $command # Use iex to expand the command

      if ($LASTEXITCODE -ne 0) {
        Write-Error "Whisper command failed.  Check the output above for errors."
        return $null # Indicate failure.
      }

      return $true #success
    }



    function Format-Timestamp {
      param(
        [double]$Seconds
      )
      $TimeSpan = [TimeSpan]::FromSeconds($Seconds)
      return $TimeSpan.ToString("hh\:mm\:ss\.fff")
    }


    function Write-ResultToFile {
      param(
        [hashtable]$Result,
        [string]$OutputFormat,
        [string]$OutputFileName
      )

      $OutputFilePath = Join-Path -Path $OutputDir -ChildPath "$OutputFileName.$OutputFormat"

      if ($OutputFormat -eq 'txt') {
        $Result.text | Out-File -FilePath $OutputFilePath -Encoding utf8
      } elseif ($OutputFormat -eq 'vtt') {
        $content = "WEBVTT`n`n"
        foreach ($segment in $Result.segments) {
          $start = Format-Timestamp $segment.start
          $end = Format-Timestamp $segment.end
          $content += "$start --> $end`n"
          $content += "$($segment.text)`n`n"
        }
        $content | Out-File -FilePath $OutputFilePath -Encoding utf8
      } elseif ($OutputFormat -eq 'srt') {
        $count = 1
        foreach ($segment in $Result.segments) {
          $start = (Format-Timestamp $segment.start).Replace('.', ',')
          $end = (Format-Timestamp $segment.end).Replace('.', ',')
          $content += "$count`n"
          $content += "$start --> $end`n"
          $content += "$($segment.text)`n`n"
          $count++
        }
        $content | Out-File -FilePath $OutputFilePath -Encoding utf8
      } elseif ($OutputFormat -eq 'tsv') {
        $content = "start`tend`ttext`n"  # Corrected header
        foreach ($segment in $Result.segments) {
          $content += "$($segment.start)`t$($segment.end)`t$($segment.text)`n"
        }
        $content | Out-File -FilePath $OutputFilePath -Encoding utf8
      } elseif ($OutputFormat -eq 'json') {
        $Result | ConvertTo-Json | Out-File -FilePath $OutputFilePath -Encoding utf8
      } else {
        Write-Warning "Unsupported output format: $OutputFormat"
        return
      }

      Write-Host "Result saved to: $OutputFilePath" -ForegroundColor Green
    }


    # --- Prepare Whisper Options ---

    $whisperOptions = @{
      task                       = $Task
      verbose                    = $true
      condition_on_previous_text = $CoherencePreference
      initial_prompt             = $Prompt
      word_timestamps            = $false
    }
    if ($Language -ne "Auto-Detect") {
      $whisperOptions.language = $Language
    }
    # --- Python Imports (Emulated in PowerShell) ---

    # We'll use .NET's built-in capabilities where possible (like System.IO for file operations)
    # and rely on calling Python for Whisper-specific tasks.
    $pythonExecutable = "python"  # Or specify the full path if needed

    # --- Determine Device ---
    if ($PSCmdlet.ParameterSetName -eq 'API') {
      Write-Host "Using API" -ForegroundColor Cyan
      $whisperOptions.Add('fp16', $true)
    } else {
      try {
        $cudaCheck = Invoke-Expression "python -c 'import torch; print(torch.cuda.is_available())'"
        if ($cudaCheck -match "True") {
          Write-Host "Using GPU (CUDA)" -ForegroundColor Cyan
          $whisperOptions.Add('device', "cuda")
          $whisperOptions.Add('fp16', $true)

          # Check for NVIDIA GPU
          if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
            nvidia-smi -L
          }
        } else {
          Write-Warning "Using CPU. Processing may be slow."
          $whisperOptions.Add('device', "cpu")
          $whisperOptions.Add('fp16', $false)
          if ($Model -notin @('tiny', 'base', 'small')) {
            Write-Warning "Not using GPU can result in a very slow execution"
            Write-Warning "You may want to try a smaller model (tiny, base, small)"
          }
        }
      } catch {
        Write-Warning "Could not determine CUDA availability. Defaulting to CPU."
        $whisperOptions.Add('device', "cpu")
        $whisperOptions.Add('fp16', $false)
      }
      $whisperOptions.model = $Model
    }

    #Create Output Directory
    if (-not (Test-Path -Path $OutputDir -PathType Container)) {
      New-Item -ItemType Directory -Path $OutputDir | Out-Null
    }

    # --- API Handling (Simplified - requires external Python script) ---
    if ($PSCmdlet.ParameterSetName -eq 'API') {

      # Create a temporary directory for intermediate files.
      $tempDir = [System.IO.Path]::GetTempPath()
      $tempDir = Join-Path $tempDir "AudioToText_Temp"
      if (-not (Test-Path -Path $tempDir)) {
        New-Item -ItemType Directory -Path $tempDir | Out-Null
      }

      Write-Host "Using OpenAI API. Model will be large-v2." -ForegroundColor Cyan
      # Call a separate Python script to handle the API calls, as it's significantly easier than porting all of the chunking/API logic.
      #  This is a major simplification compared to the original, assuming you have a `whisper_api.py` file.
    }
  }

  process {

    foreach ($audioPath in $AudioFile) {
      if (-not (Test-Path -Path $audioPath -PathType Leaf)) {
        Write-Error "File not found: $audioPath"
        continue  # Skip to the next file
      }

      Write-Host "Processing: $audioPath" -ForegroundColor Yellow

      if ($PSCmdlet.ParameterSetName -eq 'API') {

        $scriptPath = Join-Path -Path (Split-Path -Path $MyInvocation.MyCommand.Path -Parent) -ChildPath "whisper_api.py" #Assumes script in same directory as this function.
        if (-not (Test-Path $scriptPath)) {
          Write-Error "whisper_api.py not found in the same directory as this script. API calls cannot be made."
          continue
        }
        # Construct the command for the Python script.
        $apiCommand = "$pythonExecutable `"$scriptPath`" `
                    --audio_file `"$audioPath`" `
                    --task `"$Task`" `
                    --api_key `"$ApiKey`" `
                    --output_dir `"$tempDir`"" # Use temp dir for intermediate files

        if ($Language -ne "Auto-Detect") {
          $apiCommand += " --language `"$Language`""
        }

        if ($Prompt) {
          $apiCommand += " --prompt `"$Prompt`""
        }

        $apiCommand += " --output_formats json" # Force JSON output for easier handling.


        Write-Verbose "Executing API command: $apiCommand"
        try {
          Invoke-Expression $apiCommand
        } catch {
          Write-Error "Error calling whisper_api.py: $($_.Exception.Message)"
          continue #skip to the next file
        }


        if ($LASTEXITCODE -ne 0) {
          Write-Error "whisper_api.py command failed. Check the output above for errors."
          continue
        }

        # Find the JSON output file
        $jsonFiles = Get-ChildItem -Path $tempDir -Filter "*.json"
        if ($jsonFiles.Count -eq 0) {
          Write-Error "No JSON output file found from whisper_api.py"
          continue
        }
        $jsonFile = $jsonFiles[0] #take first json found

        # Load the result from the JSON file
        try {
          $result = Get-Content -Path $jsonFile.FullName -Raw | ConvertFrom-Json
        } catch {
          Write-Error "Error reading or parsing the JSON output: $($_.Exception.Message)"
          continue
        }



        # ---  Output all requested formats ---
        $outputFormatsArray = $OutputFormats -split ","
        $outputBaseName = [System.IO.Path]::GetFileNameWithoutExtension($audioPath)

        foreach ($format in $outputFormatsArray) {
          Write-ResultToFile -Result $result -OutputFormat $format -OutputFileName $outputBaseName
        }

        # --- Clean up temp files ---
        Remove-Item -Path $jsonFile.FullName -Force

      } else {
        # --- Local Processing ---
        $result = Invoke-Whisper -AudioPath $audioPath -WhisperOptions $whisperOptions

        if (-not $result) {
          Write-Error "Failed to process audio file locally: $audioPath"
          continue
        }
        # --- Parse Whisper Output ---
        # Because we used --verbose $true, Whisper's output is on stdout.  We need to parse it.
        # This is MUCH more reliable than trying to capture stdout directly, because of timing issues.

        $outputBaseName = [System.IO.Path]::GetFileNameWithoutExtension($audioPath)
        $txtFiles = Get-ChildItem -Path $OutputDir -Filter "$outputBaseName.txt"
        if ($txtFiles.Count -eq 0) {
          Write-Error "Whisper output file not found.  Check that Whisper completed successfully and that the output directory is correct."
          continue
        }

        $transcriptText = Get-Content -Path $txtFiles[0].FullName -Raw # Read the entire file


        $segments = @()
        $logFile = "$outputBaseName.log"
        $logPath = Join-Path $OutputDir $logFile
        $whisperLog = Get-Content $logPath -ErrorAction SilentlyContinue #get whisper log if there is any
        if ($whisperLog) {
          #if the log exist
          $logLines = $whisperLog | Where-Object { $_ -match '^\[(.*?) --> (.*?)\]\s+(.*)' }
          foreach ($line in $logLines) {
            if ($matches) {
              $startStr = $matches[1]
              $endStr = $matches[2]
              $text = $matches[3].Trim()


              #Convert timestamps. Whisper's log output is in HH:MM:SS.fff format.
              $start = ([TimeSpan]::Parse($startStr)).TotalSeconds
              $end = ([TimeSpan]::Parse($endStr)).TotalSeconds

              $segments += @{
                id    = $segments.Count # Simple incrementing ID
                start = $start
                end   = $end
                text  = $text
              }
            }
          }

          # --- Build Result Object (like the Python dictionary) ---
          $result = @{
            text     = $transcriptText
            segments = $segments
            language = if ($whisperOptions.ContainsKey('language')) { $whisperOptions.language } else { "Unknown" } #placeholder
          }

        } else {
          #if log does not exists use regex

          $pattern = '\[(?<start>\d{2}:\d{2}:\d{2}\.\d{3}) --> (?<end>\d{2}:\d{2}:\d{2}\.\d{3})\]\s+(?<text>.*)'
          $matches = [regex]::Matches($transcriptText, $pattern)

          foreach ($match in $matches) {
            $startStr = $match.Groups['start'].Value
            $endStr = $match.Groups['end'].Value
            $text = $match.Groups['text'].Value.Trim()

            # Convert timestamps. Whisper's log output is in HH:MM:SS.fff format.
            $start = ([TimeSpan]::Parse($startStr)).TotalSeconds
            $end = ([TimeSpan]::Parse($endStr)).TotalSeconds

            $segments += @{
              id    = $segments.Count  # Simple incrementing ID
              start = $start
              end   = $end
              text  = $text
            }
          }

          # --- Build Result Object (like the Python dictionary) ---
          $result = @{
            text     = $transcriptText
            segments = $segments
            language = if ($whisperOptions.ContainsKey('language')) { $whisperOptions.language } else { "Unknown" }  # We don't have easy language detection in PS.
          }
        }


        # ---  Output all requested formats ---
        $outputFormatsArray = $OutputFormats -split ","
        $outputBaseName = [System.IO.Path]::GetFileNameWithoutExtension($audioPath)

        foreach ($format in $outputFormatsArray) {
          Write-ResultToFile -Result $result -OutputFormat $format -OutputFileName $outputBaseName
        }

        if ($whisperLog) {
          #deletes the log file
          Remove-Item $logPath -Force
        }

      }
      # --- DeepL Translation (Optional) ---

      if ($DeeplApiKey -and $DeeplTargetLanguage) {

        Write-Host "Translating with DeepL..." -ForegroundColor Cyan
        $deeplScriptPath = Join-Path -Path (Split-Path -Path $MyInvocation.MyCommand.Path -Parent) -ChildPath "deepl_translate.py" #Assumes in the same directory
        if (-not (Test-Path $deeplScriptPath)) {
          Write-Error "deepl_translate.py not found in the same directory as this script. DeepL translation cannot be performed."
          continue
        }

        $outputBaseName = [System.IO.Path]::GetFileNameWithoutExtension($audioPath)
        $translatedOutputBaseName = "$outputBaseName`_$DeeplTargetLanguage"


        $deeplCommand = "`"$pythonExecutable`" `"$deeplScriptPath`" `
                     --deepl_api_key `"$DeeplApiKey`" `
                     --deepl_target_language `"$DeeplTargetLanguage`" `
                     --input_file `"$($outputBaseName).txt`" `
                     --output_dir `"$OutputDir`" `
                     --output_file `"$translatedOutputBaseName`""

        if ($DeeplCoherencePreference) {
          $deeplCommand += " --deepl_coherence_preference True"
        } else {
          $deeplCommand += " --deepl_coherence_preference False"
        }

        if ($DeeplFormality -ne "default") {
          $deeplCommand += " --deepl_formality `"$DeeplFormality`""
        }
        Write-Verbose "Executing DeepL command: $deeplCommand"

        try {
          Invoke-Expression $deeplCommand
        } catch {
          Write-Error "Error during DeepL translation: $($_.Exception.Message)"
        }


        if ($LASTEXITCODE -ne 0) {
          Write-Error "deepl_translate.py command failed. Check the output above for errors."
          continue #no deepl translation if failed
        }


        # --- Read and output translated files ---

        $outputFormatsArray = $OutputFormats -split ","

        foreach ($format in $outputFormatsArray) {
          $translatedFilePath = Join-Path -Path $OutputDir -ChildPath "$translatedOutputBaseName.$format"

          if (Test-Path $translatedFilePath) {
            Write-Host "Translated result ($format) saved to: $translatedFilePath" -ForegroundColor Green
          } else {
            Write-Warning "Translated $format file not found: $translatedFilePath"
          }
        }
      }
    }
  }

  end {
    # --- Cleanup ---
    if (Test-Path -Path $tempDir -PathType Container) {
      Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host "Conversion complete." -ForegroundColor Green
  }
}