function Resolve-Requirements {
  [CmdletBinding()][OutputType([bool])]
  param (
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$req_txt = [LocalSTT]::data.Server.requirementsfile,

    [Parameter(Mandatory = $false, Position = 1)]
    [PsRecord]$config = [LocalSTT]::data,

    [switch]$throwOnFail
  )
  process {
    if ($config.IsRecording) { Write-Warning "LocalSTT is already recording."; if ($null -ne [LocalSTT]::recorder) { [LocalSTT]::recorder.Stop() }; }
    $v = [ProgressUtil]::data.ShowProgress
    $res = [IO.File]::Exists($req_txt); $req_txt_short_path = Invoke-PathShortener $req_txt
    if (!$res) { throw "LocalSTT failed to resolve pip requirements. From file: '$req_txt_short_path'." }
    if (!$config.Env::req.resolved) { $config.Env::req.Resolve() }
    $v ? $(Write-Console "(LocalSTT) " -f SlateBlue -NoNewLine; Write-Console "▶︎ Found file @ /$req_txt_short_path" -f LemonChiffon) : $null
    if ($null -eq $config -and $throwOnFail) { throw [InvalidOperationException]::new("LocalSTT config found.") };
    if ($null -eq $config.Env) {
      throw [InvalidOperationException]::new("No created env was found.")
    }
    $was_inactive = ($config.Env.State -eq "inactive") ? $([void]$config.Env.Activate(); $true) : $false
    $v ? $(Write-Console "(LocalSTT) " -f SlateBlue -NoNewLine; Write-Console "▶︎ Resolve requirements: " -f LemonChiffon -Animate) : $null
    [void][LocalSTT]::Run("(LocalSTT)   pip install -r $req_txt_short_path", [scriptblock]::Create("pip install -r '$req_txt'"), $throwOnFail)
    if ($was_inactive) { [void]$config.Env.Deactivate() }
    $res = $res -and ([LocalSTT]::ErrorLog.count -eq 0)
  }

  end {
    return $res
  }
}