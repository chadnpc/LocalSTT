﻿function Get-Config {
  #.DESCRIPTION
  # Load stt configuration from json or toml file
  [CmdletBinding()][OutputType([PsRecord])]
  param (
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$workingdir = (Resolve-Path .).Path
  )

  begin {
    $config = $null
    $1strun = IsFirstRun;
    $mdpath = (Get-Module LocalSTT -ListAvailable -Verbose:$false).ModuleBase
  }

  process {
    try {
      $config = [PsRecord]@{
        Env             = $null
        Server          = $null
        Process         = ''
        IsRecording     = $false
        PythonVersion   = [version]'3.12.9'
        HasRequirements = $false
        PercentComplete = 0
      }
      $config.Server = [PsRecord]@{
        port             = 65432
        host             = "127.0.0.1"
        amplifyRate      = "1.0"
        workingDirectory = $workingdir
        requirementsfile = [IO.Path]::Combine($mdpath, "Private", "requirements.txt")
        Script           = [IO.Path]::Combine($mdpath, "Private", "stt.py")
        outFile          = [IO.Path]::Combine($workingdir, "$(Get-Date -Format 'yyyyMMddHHmmss')_output.wav")
      }
      $config.Server.PsObject.Properties.Add([PSScriptproperty]::New("modulePath", [scriptblock]::Create("return `"$mdpath`""), {
            throw [SetValueException]::new("modulePath is read-only")
          }
        )
      )
      if ($1strun) {
        [LocalSTT].PsObject.Properties.Add([PSScriptproperty]::New("config", {
              return Get-Config }, {
              throw [SetValueException]::new("config can only be imported or edited")
            }
          )
        )
      }
      $config.Env = New-venv -Path $workingdir -Verbose:$false
      if ($verbose) { Write-Console "(LocalSTT)   Set python version to $($config.PythonVersion)" -f LemonChiffon }
      (New-Object PyenvHelper).Useversion($config.PythonVersion, $config)
      Resolve-Requirements ([ref]$config)
    } catch {
      "Failed to Load stt data" | Write-Console -f LightCoral
      $_ | Format-List * -Force | Out-String | Write-Console -f LightCoral
    }
  }

  end {
    return $config
  }
}