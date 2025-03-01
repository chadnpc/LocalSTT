function Get-Transcript {
  # .SYNOPSIS
  #   Gets the transcript of an audio file
  # .DESCRIPTION
  #   Gets the transcript of an audio file using whisper python module
  # .NOTES
  #   Author   : Alain Herve
  #   License  : MIT
  # .LINK
  #   Record-Audio
  # .LINK
  #   https://github.com/chadnpc/LocalSTT/blob/main/Public/Get-Transcript.ps1
  # .EXAMPLE
  #   Record-Audio -o output.wav
  #   $txt = Get-Transcript output.wav
  [CmdletBinding()][OutputType([string])][Alias('Transcribe-Audio')]
  param (
    [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
    [ValidateNotNullOrEmpty()]
    [IO.FileInfo]$Path,

    [Parameter(Mandatory = $false, Position = 1)]
    [ValidateScript({
        if (![IO.File]::Exists($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($_))) {
          throw [System.IO.FileNotFoundException]::new("Please path to existing file", $_)
        } else {
          $true
        }
      }
    )]
    [string]$OutFile
  )
  begin {
    $p = $PSCmdlet.MyInvocation.BoundParameters; $t = [string]::Empty
    $o = $p.ContainsKey('OutFile') ? $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutFile) : ([IO.Path]::GetTempFileName())
  }
  process {
    $t = [LocalSTT]::TranscribeAudio($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path), $o)
    if (!$p.ContainsKey('OutFile')) {
      Remove-Item $o -Verbose:$false
    }
  }

  end {
    return $t
  }
}