function Receive-Audio {
  [CmdletBinding()][Alias('Record-Audio')]
  param (
    [Parameter(Mandatory = $false, Position = 0)]
    [ValidateScript({
        if (Test-Path -Path $_ -PathType Leaf -ea Ignore) {
          return $true
        } else {
          throw [System.ArgumentException]::new('OutFile', "Path: $_ is not a valid file.")
        }
      })][Alias('OutFile')]
    [string]$OutFile
  )
  end {
    $rec = $PSCmdlet.MyInvocation.BoundParameters.containsKey('OutFile') ? ([LocalSTT]::RecordAudio($OutFile)) : ([LocalSTT]::RecordAudio())
    return $rec
  }
}