function Resolve-Requirements {
  [CmdletBinding(SupportsShouldProcess = $true)]
  param (
    [Parameter(Mandatory = $false, Position = 1)]
    [ValidateNotNullOrEmpty()]
    [ref]$config
  )
  begin {
    if ($config.value.IsRecording) {
      Write-Warning "LocalSTT is already recording.";
      if ($null -ne [LocalSTT]::recorder) { [LocalSTT]::recorder.Stop() };
    }
    $reqfile = $config.value.Server.requirementsfile
    $AreResolved = $config.value.HasRequirements
    $description = "(LocalSTT)   pip install -r $reqfile_short_path"
    $argmentlist = @($config.value, $reqfile, [bool]($errorAction -eq "stop"))
    $install_script = {
      param([PsRecord]$cfg, [string]$reqtxt, [bool]$throwOnFail)
      $was_inactive = $cfg.Env.State -eq "inactive"
      try {
        [IO.FileInfo]$pip = [IO.Path]::Combine((Get-Variable HOME -Scope Global -ValueOnly), ".pyenv", "shims", "pip")
        if (!$pip.Exists) {
          throw [IO.FileNotFoundException]::new("pip shim not found. Install pyenv and try again.")
        }
        [void]$cfg.Env.Activate()
        & $pip.FullName install --upgrade pip
        & $pip.FullName install -r $reqtxt
      } catch {
        [LocalSTT]::LogErrors($_);
        if ($throwOnFail) {
          throw $_
        } else {
          Write-Console $_.Exception.Message -f LightCoral
        }
      } finally {
        if ($was_inactive) { [void]$cfg.Env.Deactivate() }
      }
    }
  }
  process {
    if ($AreResolved -and !$Force) {
      $reqfile_short_path = Invoke-PathShortener $reqfile
      if (![IO.File]::Exists($reqfile)) { throw "LocalSTT failed to resolve pip requirements. From file: '$reqfile_short_path'." }
      if (!$config.value.Env::req.resolved) { $config.value.Env::req.Resolve() }
      if ($null -eq $config.value -and $errorAction -eq "stop") { throw [InvalidOperationException]::new("LocalSTT config found.") };
      if ($null -eq $config.value.Env -and $errorAction -eq "stop") {
        throw [InvalidOperationException]::new("No created env was found.")
      }
      $verbose ? $(Write-Console "(LocalSTT) " -f SlateBlue -NoNewLine; Write-Console "▶︎ Resolve requirements: " -f LemonChiffon -Animate) : $null
      if ($PSCmdlet.ShouldProcess("current host", $description)) {
        [void][LocalSTT]::Run($description, $install_script, $argmentlist)
      }
      $AreResolved = $AreResolved -and ([LocalSTT]::ErrorLog.count -eq 0)
    }
  }

  end {
    $config.value.HasRequirements = $AreResolved
  }
}