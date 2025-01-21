function Get-Transcript {
  # .SYNOPSIS
  #   Gets the transcript of an audio file
  # .DESCRIPTION
  #   Gets the transcript of an audio file using whisper python module
  # .NOTES
  #   Author   : Alain Herve
  #   License  : MIT
  # .LINK
  #   https://github.com/alainQtec/LocalSTT/blob/main/Public/Get-Transcript.ps1
  # .EXAMPLE
  #   $txt = Get-Transcript ~/audio.wav
  [CmdletBinding()][OutputType([string])]
  param (
    [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
    [ValidateNotNullOrEmpty()]
    [IO.FileInfo]$Path,

    [Parameter(Mandatory = $false, Position = 1)]
    [ValidateNotNullOrWhiteSpace()]
    [string]$OutFile
  )
  begin {
    $p = $PSCmdlet.MyInvocation.BoundParameters; $t = [string]::Empty
    $o = $p.ContainsKey('OutFile') ? $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutFile) : ([IO.Path]::GetTempFileName())
  }
  process {
    $t = [LocalSTT]::TranscribeAudio($Path.FullName, $o)
    if (!$p.ContainsKey('OutFile')) {
      Remove-Item $o -Verbose:$false
    }
  }

  end {
    return $t
  }
}