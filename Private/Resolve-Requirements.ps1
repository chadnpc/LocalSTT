function Resolve-Requirements {
  [CmdletBinding()][OutputType([bool])]
  param (
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$reqfile = [LocalSTT]::data.Server.requirementsfile,

    [Parameter(Mandatory = $false, Position = 1)]
    [PsRecord]$config = [LocalSTT]::data,

    [switch]$throwOnFail
  )
  process {
    if ($config.IsRecording) { Write-Warning "LocalSTT is already recording."; if ($null -ne [LocalSTT]::recorder) { [LocalSTT]::recorder.Stop() }; }
    $v = [ProgressUtil]::data.ShowProgress
    $res = [IO.File]::Exists($reqfile); $reqfile_short_path = Invoke-PathShortener $reqfile
    if (!$res) { throw "LocalSTT failed to resolve pip requirements. From file: '$reqfile_short_path'." }
    if (!$config.Env::req.resolved) { $config.Env::req.Resolve() }
    $v ? $(Write-Console "(LocalSTT) " -f SlateBlue -NoNewLine; Write-Console "▶︎ Found file @ / $reqfile_short_path" -f LemonChiffon) : $null
    if ($null -eq $config -and $throwOnFail) { throw [InvalidOperationException]::new("LocalSTT config found.") };
    if ($null -eq $config.Env) {
      throw [InvalidOperationException]::new("No created env was found.")
    }
    $v ? $(Write-Console "(LocalSTT) " -f SlateBlue -NoNewLine; Write-Console "▶︎ Resolve requirements: " -f LemonChiffon -Animate) : $null
    $s = {
      param([PsRecord]$cfg, [string]$reqtxt, [switch]$throw)
      $was_inactive = $cfg.Env.State -eq "inactive"
      try {
        [IO.FileInfo]$pip = "/$(Get-Variable HOME -ValueOnly)/.pyenv/shims/pip"
        if (!$pip.Exists) {
          throw [IO.FileNotFoundException]::new("pip shim not found. Install pyenv and try again.")
        }
        if ($was_inactive) { [void]$cfg.Env.Activate() }
        & $pip.FullName install --upgrade pip
        & $pip.FullName install -r $reqtxt
      } catch {
        [LocalSTT]::LogErrors($_);
        if ($throw) {
          throw $_
        } else {
          Write-Console $_.Exception.Message -f LightCoral
        }
      } finally {
        if ($was_inactive) { [void]$cfg.Env.Deactivate() }
      }
    }
    $msg = "(LocalSTT)   pip install -r $reqfile_short_path"
    [void][LocalSTT]::Run($msg, $s, ($config, $reqfile, $throwOnFail))
    $res = $res -and ([LocalSTT]::ErrorLog.count -eq 0)
  }

  end {
    return $res
  }
}