#!/usr/bin/env pwsh
using namespace System.IO
using namespace System.Net
using namespace System.Net.Sockets
using namespace System.Collections.Generic
using namespace System.Management.Automation

#Requires -Modules cliHelper.core, cliHelper.errorman, pipEnv
#Requires -Psedition Core

#region    Classes
class AudioRecorder {
  [Socket]$server
  [TcpClient]$client
  [FileInfo]$outFile
  hidden [Stream]$stream
  hidden [TcpListener]$listener

  AudioRecorder([TcpListener]$listener, [FileInfo]$outFile) {
    $this.listener = $listener
    $this.outFile = $outFile
  }
  [Stream] Start() {
    $this.listener.Start()
    $this.server = ([ref]$this.listener.Server).Value
    return $this.Start($this.listener.AcceptTcpClient())
  }
  [Stream] Start([TcpClient]$client) {
    $this.client = $client
    Write-Console "● " -f SlateBlue -NoNewLine; Write-Console "OutFile: " -f LightGoldenrodYellow -NoNewLine; Write-Console "'$([LocalSTT]::recorder.outFile)'" -f LimeGreen; Write-Console "┆" -f LimeGreen
    $this.stream = $client.GetStream()
    Write-Console "● " -f SlateBlue -NoNewLine; Write-Console "Started recording. Press Ctrl+C to stop." -f LightGoldenrodYellow
    [LocalSTT]::data.IsRecording = $true
    return $this.stream
  }
  [void] Stop() {
    $this.Stop(0)
  }
  [void] Stop([int]$ProcessId) {
    $this.Stop($this.listener, $ProcessId)
  }
  [void] Stop([TcpListener]$listener, [int]$ProcessId) {
    $this.stream.Close()
    $this.client.Close(); $listener.Stop()
    if ($ProcessId -gt 0) { Stop-Process -Id $ProcessId -Force }
    [LocalSTT]::data.IsRecording = $false
  }
}
class PyenvHelper {
  PyenvHelper() {}
  static [void] useversion([string]$ver) {
    [PyenvHelper]::useversion([version]::new($ver), [ref][LocalSTT]::data)
  }
  static [void] useversion([version]$ver, [ref]$config) {
    [version]$current_ver = [PyenvHelper]::get_python_version()
    if ($current_ver -lt $ver) {
      Write-Console "Installing Python v$ver..." -f SlateBlue
      pyenv install $ver.ToString()
    }
    pyenv local "$ver"
    $config.Value.Env.PythonVersion = $ver
    if ($current_ver -ne $ver) {
      throw [InvalidOperationException]::new("Failed to set Python version to $ver")
    }
  }
  static [version] get_python_version() {
    return [version]::new((python --version).Split(" ")[1])
  }
}

# .SYNOPSIS
#   Local Speech to text powershell module
# .DESCRIPTION
#   This script uses PyAudio, Retrieves a list of audio input devices available on the system.
#   then uses it to record audio from a selected device
# .NOTES
#   Requires the PyAudio library to be installed.
#   Ensure that audio devices are properly configured on the system for accurate results.
# .LINK
#   https://pyaudio.readthedocs.io/en/stable/
class LocalSTT : ThreadRunner {
  static [AudioRecorder] $recorder
  static [PsRecord]$data = [LocalSTT]::GetSttData()
  LocalSTT() {}

  static [IO.Fileinfo] RecordAudio() { return [LocalSTT]::RecordAudio(3) }

  static [IO.Fileinfo] RecordAudio([float]$minutes) {
    return [LocalSTT]::RecordAudio([LocalSTT]::data.Stt.outFile, [Timespan]::new(0, 0, $minutes * 60))
  }
  static [IO.Fileinfo] RecordAudio([string]$outFile, [float]$minutes) {
    return [LocalSTT]::RecordAudio($outFile, [Timespan]::new(0, 0, $minutes * 60))
  }
  static [IO.Fileinfo] RecordAudio([string]$outFile, [Timespan]$duration) {
    [ValidateNotNullOrWhiteSpace()][string]$outFile = $outFile
    if ([LocalSTT]::IsFirstRun()) { [void][LocalSTT]::ResolveRequirements() };
    if ([LocalSTT]::data.Env.State -eq "inactive") {
      [LocalSTT]::data.Env.Activate()
    }
    $_c = [LocalSTT].config; [LocalSTT]::recorder = [AudioRecorder]::New([TcpListener]::new([IPEndpoint]::new([IPAddress]$_c.Stt.host, $_c.Stt.port)), [IO.FileInfo]::New($outFile)); $dir = $_c.Stt.workingDirectory
    [LocalSTT]::data.Process = Start-Process -FilePath "python" -ArgumentList "$($_c.Stt.Script) --host `"$($_c.Stt.host)`" --port $($_c.Stt.port) --amplify-rate $($_c.Stt.amplifyRate) --outfile `"$outFile`" --duration-in-minutes=$($duration.TotalMinutes) --working-directory `"$dir`"" -WorkingDirectory $dir -PassThru -NoNewWindow
    Write-Console "(LocalSTT) " -f SlateBlue -NoNewLine; Write-Console "▶︎ Recording server starting @ http://$([LocalSTT]::recorder.listener.LocalEndpoint) PID: $([LocalSTT]::data.Process.Id)" -f LemonChiffon;
    $OgctrInput = [Console]::TreatControlCAsInput;
    try {
      $stream = [LocalSTT]::recorder.Start(); $buffer = [byte[]]::new(1024); [LocalSTT]::data.PercentComplete = 0;
      do {
        $bytesRead = $stream.Read($buffer, 0, $buffer.Length)
        if ([LocalSTT]::data.PercentComplete -ne 100 -and $bytesRead -le 0) { Write-Console "`nNo data was received from stt.py!" -f LightCoral; break }
        $_str = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $bytesRead).Split('}{')[-1];
        if (![string]::IsNullOrWhiteSpace($_str)) {
          $json = $_str.StartsWith([char]123) ? $_str : ([char]123 + $_str)
          $_cfg = $json | ConvertFrom-Json; [LocalSTT]::data.Process = $_cfg.process; [LocalSTT]::data.PercentComplete = ($_cfg.progress -ge 100) ? 100 : $_cfg.progress; $et = [Timespan]::new(0, 0, $_cfg.elapsed_time)
          [progressUtil]::WriteProgressBar([LocalSTT]::data.PercentComplete, $true, 5, "(LocalSTT) ▶︎ $($_cfg.process) •၊၊||၊|။||||။‌‌‌‌‌၊|• $($et.Minutes):$($et.Seconds)", $false)
          [threading.Thread]::Sleep(200)
        }
      } while ([LocalSTT]::data.PercentComplete -ne 100)
    } catch {
      Write-Console "`nError receiving data: $($_.Exception.Message)" -f LightCoral
    } finally {
      [Console]::TreatControlCAsInput = $OgctrInput
      [LocalSTT]::recorder.Stop([LocalSTT]::data.Process.Id)
    }
    return [LocalSTT]::recorder.outFile
  }
  static [string] TranscribeAudio([IO.FileInfo]$InputAudio, [string]$outFile) {
    [ValidateNotNullOrEmpty()][IO.FileInfo]$InputAudio = $InputAudio;
    [string]$inputFile = $InputAudio.FullName;
    if (!$InputAudio.Exists) { throw [FileNotFoundException]::New("Could Not Find Audio File $inputFile") }
    if ([LocalSTT]::IsFirstRun()) { [void][LocalSTT]::ResolveRequirements() }
    if ([LocalSTT]::data.Env.State -eq "inactive") {
      [LocalSTT]::data.Env.Activate()
    }
    $_c = [LocalSTT].config;
    $_t = [IO.Path]::Combine(($_c.Stt.Script | Split-Path), "transcribe.py"); $dir = $_c.Stt.workingDirectory
    $Process = Start-Process -FilePath "python" -ArgumentList "$_t --inputfile `"$inputFile`" --outfile `"$outFile`" --working-directory `"$dir`"" -WorkingDirectory $dir -PassThru -NoNewWindow;
    $Process.WaitForExit()
    $process.Kill(); $Process.Dispose()
    return [IO.File]::ReadAllText($outFile)
  }
  static [bool] ResolveRequirements() {
    return [LocalSTT]::ResolveRequirements([LocalSTT]::data.Stt.requirementsfile, [LocalSTT]::data, $false)
  }
  static [bool] ResolveRequirements([string]$req_txt, [PsRecord]$config, [bool]$throwOnFail) {
    if ($config.IsRecording) { Write-Warning "LocalSTT is already recording."; if ($null -ne [LocalSTT]::recorder) { [LocalSTT]::recorder.Stop() }; }
    $v = (Get-Variable 'VerbosePreference' -ValueOnly) -eq 'Continue'
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
    if ($was_inactive) { $config.Env.Deactivate() }
    return $res -and ([LocalSTT]::ErrorLog.count -eq 0)
  }
  static [bool] IsFirstRun() {
    return $null -eq ([LocalSTT] | Get-Member -Name config -Type ScriptProperty)
  }
  static [PsRecord] GetSttData() {
    $d = $null
    try {
      $d = [LocalSTT]::GetSttData((Resolve-Path .).Path)
    } catch {
      "Failed to Load stt data" | Write-Console -f LightCoral
      $_ | Format-List * -Force | Out-String | Write-Console -f LightCoral
    }
    return $d
  }
  static [PsRecord] GetSttData([string]$current_path) {
    # .DESCRIPTION
    #   Load stt configuration from json or toml file
    $1strun = [LocalSTT]::IsFirstRun();
    $mdpath = (Get-Module LocalSTT -ListAvailable -Verbose:$false).ModuleBase
    $config = [PsRecord]@{
      Stt             = $null
      Env             = $null
      Process         = ''
      IsRecording     = $false
      PythonVersion   = [version]'3.12.9'
      HasRequirements = $false
      PercentComplete = 0
    }
    $config.Stt = [PsRecord]@{
      port             = 65432
      host             = "127.0.0.1"
      amplifyRate      = "1.0"
      workingDirectory = $current_path
      requirementsfile = [IO.Path]::Combine($mdpath, "Private", "requirements.txt")
      Script           = [IO.Path]::Combine($mdpath, "Private", "stt.py")
      outFile          = [IO.Path]::Combine($current_path, "$(Get-Date -Format 'yyyyMMddHHmmss')_output.wav")
    }
    $config.Stt.PsObject.Properties.Add([PSScriptproperty]::New("modulePath", [scriptblock]::Create("return `"$mdpath`""), {
          throw [SetValueException]::new("modulePath is read-only")
        }
      )
    )
    if ($1strun) {
      [LocalSTT].PsObject.Properties.Add([PSScriptproperty]::New("config", {
            return [LocalSTT]::GetSttData() }, {
            throw [SetValueException]::new("config can only be imported or edited")
          }
        )
      )
    }
    $config.Env = New-venv -Path $current_path -Verbose:$false
    $cfactivity = "(LocalSTT)   Set local python version to {0}" -f $config.PythonVersion
    [void][LocalSTT]::Run($cfactivity, { param($c) [PyenvHelper]::useversion($c.PythonVersion, $c) }, $cfactivity, $config)
    $config.HasRequirements = $1strun ? [LocalSTT]::ResolveRequirements($config.Stt.requirementsfile, $config, $false) : $false
    return $config
  }
}

#endregion Classes
# Types that will be available to users when they import the module.
$typestoExport = @(
  [LocalSTT], [AudioRecorder], [PyenvHelper]
)
$TypeAcceleratorsClass = [PsObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
foreach ($Type in $typestoExport) {
  if ($Type.FullName -in $TypeAcceleratorsClass::Get.Keys) {
    "TypeAcceleratorAlreadyExists - Unable to register type accelerator '$($Type.FullName)'" | Write-Debug
  }
}
# Add type accelerators for every exportable type.
foreach ($Type in $typestoExport) {
  $TypeAcceleratorsClass::Add($Type.FullName, $Type)
}
# Remove type accelerators when the module is removed.
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
  foreach ($Type in $typestoExport) {
    $TypeAcceleratorsClass::Remove($Type.FullName)
  }
}.GetNewClosure();

$scripts = @();
$Public = Get-ChildItem "$PSScriptRoot/Public" -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue
$scripts += Get-ChildItem "$PSScriptRoot/Private" -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue
$scripts += $Public

foreach ($file in $scripts) {
  Try {
    if ([string]::IsNullOrWhiteSpace($file.fullname)) { continue }
    . "$($file.fullname)"
  } Catch {
    Write-Warning "Failed to import function $($file.BaseName): $_"
    $host.UI.LogErrorsLine($_)
  }
}

$Param = @{
  Function = $Public.BaseName
  Cmdlet   = '*'
  Alias    = '*'
  Verbose  = $false
}
Export-ModuleMember @Param
