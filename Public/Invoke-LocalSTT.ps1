function Invoke-LocalSTT {
  <#
  .SYNOPSIS
    main function
  .DESCRIPTION
    MOst of what this function does can be done by combining other functions
  .NOTES
    The function was created to behave more like a cli tool
  .LINK
    https://github.com/alainQtec/LocalSTT/blob/main/Public/Invoke-LocalSTT.ps1
  .EXAMPLE
    localstt record -d 0.5 -o out.wav -t transcript.txt
  .EXAMPLE
    localstt --help
  .EXAMPLE
    localstt -v
  #>
  begin {
    # TODO: Use argparser module
    # $schema = @{}
  }
  process {
    $cmdline = [string]::Join(' ', ([string[]]$args))
    if ($cmdline.Contains('-h') -or $cmdline.Contains('--help')) {
      [LocalStt]::banner | Write-Console -f SlateBlue
      "LocalSTT help content goes here" | Write-Border | Write-Console -f DarkKhaki
      return
    }
    return [PSCustomObject]@{
      args   = $cmdline
      parsed = $null
    }
  }
}
Set-Alias localstt Invoke-LocalSTT