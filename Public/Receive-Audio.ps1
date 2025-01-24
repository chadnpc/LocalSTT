function Receive-Audio {
  # .SYNOPSIS
  #   Records audio
  # .DESCRIPTION
  #   Records audio from the default microphone and saves it to a file.
  # .LINK
  #   https://github.com/alainQtec/LocalSTT/blob/main/Public/Receive-Audio.ps1
  # .EXAMPLE
  #   Record-Audio
  #   Saves audio to the current directory.
  # .EXAMPLE
  #   Record-Audio -o ~/output.wav
  #   Will record audio for 3 minutes and save it to the specified path
  [CmdletBinding()][OutputType([System.IO.FileInfo])][Alias('Record-Audio')]
  param (
    [Parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true)]
    [ValidateScript({
        try {
          $chars = $_.TocharArray();
          $invalidChars = [IO.Path]::GetInvalidPathChars() + @(':', '?', '*'); $hasSome = $false
          foreach ($char in $chars) { $hasSome = $hasSome -or ($invalidChars -contains $char) }
          if ($hasSome) { throw [System.ArgumentException]::new('OutFile', "Path: $_ contains invalid characters.") }
          $root = [System.IO.Path]::GetPathRoot($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($_))
          if ([string]::IsNullOrWhiteSpace($root)) {
            throw [System.ArgumentException]::new("Invalid path root: $_", 'OutFile')
          }
          $true
        } catch {
          throw $_.Exception
        }
      })][Alias('o')]
    [string]$OutFile,

    [Parameter(Mandatory = $false, Position = 1, helpMessage = 'Duration of the recording in minutes')]
    [Alias('d')][ValidateNotNullOrEmpty()]
    [float]$Duration = .5 # 30 seconds
  )
  begin {
    $params = $PSCmdlet.MyInvocation.BoundParameters
    $_ofile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutFile)
  }
  process {
    $rec = $params.ContainsKey('OutFile') ? ([LocalSTT]::RecordAudio($_ofile, $Duration)) : ([LocalSTT]::RecordAudio($Duration))
    return $rec
  }
}
