#!/usr/bin/env pwsh
using namespace System.IO
using namespace System.Net
using namespace System.Net.Sockets
using namespace System.Management.Automation

#Requires -Modules cliHelper.core, pipEnv
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
class LocalSTT {
  static [AudioRecorder] $recorder
  static [PsRecord]$data = [LocalSTT]::GetSttConfig()
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
    [void][LocalSTT]::ResolveRequirements(); $_c = [LocalSTT].config; [LocalSTT]::recorder = [AudioRecorder]::New([TcpListener]::new([IPEndpoint]::new([IPAddress]$_c.host, $_c.port)), [IO.FileInfo]::New($outFile)); $dir = $_c.workingDirectory
    $pythonProcess = Start-Process -FilePath "python" -ArgumentList "$($_c.Script) --host `"$($_c.host)`" --port $($_c.port) --amplify-rate $($_c.amplifyRate) --outfile `"$outFile`" --duration-in-minutes=$($duration.TotalMinutes) --working-directory `"$dir`"" -WorkingDirectory $dir -PassThru -NoNewWindow
    Write-Console "(LocalSTT) " -f SlateBlue -NoNewLine; Write-Console "▶︎ Recording server starting @ http://$([LocalSTT]::recorder.listener.LocalEndpoint) PID: $($pythonProcess.Id)" -f LemonChiffon;
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
      [LocalSTT]::recorder.Stop($pythonProcess.Id)
    }
    return [LocalSTT]::recorder.outFile
  }
  static [string] TranscribeAudio([IO.FileInfo]$InputAudio, [string]$outFile) {
    [ValidateNotNullOrEmpty()][IO.FileInfo]$InputAudio = $InputAudio;
    [string]$inputFile = $InputAudio.FullName;
    if (!$InputAudio.Exists) { throw [FileNotFoundException]::New("Could Not Find Audio File $inputFile") }
    [void][LocalSTT]::ResolveRequirements(); $_c = [LocalSTT].config;
    $_t = [IO.Path]::Combine(($_c.Script | Split-Path), "transcribe.py"); $dir = $_c.workingDirectory
    $Process = Start-Process -FilePath "python" -ArgumentList "$_t --inputfile `"$inputFile`" --outfile `"$outFile`" --working-directory `"$dir`"" -WorkingDirectory $dir -PassThru -NoNewWindow;
    $Process.WaitForExit()
    $process.Kill(); $Process.Dispose()
    return [IO.File]::ReadAllText($outFile)
  }
  static [bool] ResolveRequirements() {
    return [LocalSTT]::ResolveRequirements([switch]$false)
  }
  static [bool] ResolveRequirements([switch]$throwOnFail) {
    if ([LocalSTT]::data.IsRecording) { Write-Warning "LocalSTT is already recording."; if ($null -ne [LocalSTT]::recorder) { [LocalSTT]::recorder.Stop() }; }
    if ($null -eq [venv]::data) { [venv]::set_data() }; [void][venv]::req.Resolve(); $v = (Get-Variable 'VerbosePreference' -ValueOnly) -eq 'Continue'
    $req = [LocalSTT]::data.Stt.requirementsfile; $res = [IO.File]::Exists($req);
    $_rp = Invoke-PathShortener $req
    if (!$res) { throw "LocalSTT failed to resolve pip requirements. From file: '$_rp'." }
    $v ? $(Write-Console "(LocalSTT) " -f SlateBlue -NoNewLine; Write-Console "▶︎ Found file @ /$_rp" -f LemonChiffon) : $null
    if (![LocalSTT]::data.HasConfig -and $throwOnFail.IsPresent) { throw [InvalidOperationException]::new("LocalSTT config found.") };
    if ($null -eq [LocalSTT]::data.CurrentEnv) {
      throw [InvalidOperationException]::new("No created env was found.")
    }
    if ([LocalSTT]::data.CurrentEnv.State -eq "Inactive") { [LocalSTT]::data.CurrentEnv.Activate() }
    $v ? $(Write-Console "(LocalSTT) " -f SlateBlue -NoNewLine; Write-Console "▶︎ Resolve requirements: " -f LemonChiffon -Animate) : $null
    [LocalSTT]::data.CurrentEnv.Activate()
    $s = [scriptblock]::Create("pip install -r '$req'")
    $j = [progressUtil]::WaitJob("(LocalSTT)   pip install -r $_rp", $s)
    $r = $j | Receive-Job
    if ($v) { $r | Out-String | Write-Console -f DarkSlateGray }
    return $res
  }
  static [PsRecord] GetSttConfig() {
    return [LocalSTT]::GetSttConfig((Resolve-Path .).Path)
  }
  static [PsRecord] GetSttConfig([string]$current_path) {
    # .DESCRIPTION
    #   Load stt configuration from json or toml file
    $mdpath = (Get-Module LocalSTT -ListAvailable -Verbose:$false).ModuleBase
    $config = [PsRecord]@{
      Stt             = $null
      Process         = ''
      HasConfig       = $false
      CurrentEnv      = $null
      IsRecording     = $false
      PercentComplete = 0
    }
    $config.PsObject.Properties.Add([PSScriptproperty]::New("HasRequirements", {
          if ([LocalSTT]::data) { return [LocalSTT]::ResolveRequirements() }; return $false
        }, {
          throw [SetValueException]::new("HasRequirements is read-only")
        }
      )
    )
    # Set default config values
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
    if ($null -eq ([LocalSTT] | Get-Member -Name config -Type ScriptProperty)) {
      [LocalSTT].PsObject.Properties.Add([PSScriptproperty]::New("config", {
            return [LocalSTT]::GetSttConfig() }, {
            throw [SetValueException]::new("config can only be imported or edited")
          }
        )
      )
    }
    $config.CurrentEnv = New-venv -Path $current_path -Verbose:$false
    $config.HasConfig = $null -ne $config
    return $config
  }
}

#endregion Classes
# Types that will be available to users when they import the module.
$typestoExport = @(
  [LocalSTT]
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
    $host.UI.WriteErrorLine($_)
  }
}

$Param = @{
  Function = $Public.BaseName
  Cmdlet   = '*'
  Alias    = '*'
  Verbose  = $false
}
Export-ModuleMember @Param
