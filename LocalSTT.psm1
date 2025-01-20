#!/usr/bin/env pwsh
using namespace System.IO
using namespace System.Net
using namespace System.Net.Sockets
using namespace System.Management.Automation

#Requires -Modules cliHelper.core, pipEnv
#Requires -Psedition Core

#region    Classes
class AudioRecorder {
  [IO.FileInfo]$outFile
  hidden [TcpClient]$client
  hidden [TcpListener]$listener
  hidden [MemoryStream]$stream

  AudioRecorder([TcpListener]$listener, [IO.FileInfo]$outFile) {
    $this.listener = $listener
    $this.outFile = $outFile
  }
  [MemoryStream] Start() {
    return $this.Start($this.listener.AcceptTcpClient())
  }
  [MemoryStream] Start([TcpClient]$client) {
    $this.client = $client
    Write-Host "┆" -f Green
    $this.stream = $client.GetStream()
    Write-Host "STT server is recording. Press Ctrl+C to stop." -f Blue
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
    if ($ProcessId -gt 0) {
      Stop-Process -Id $ProcessId -Force
      if ($this.outFile.Exists) { Write-Host "Audio outFile: $($this.outFile)" -f Green }
    }
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
  static [AudioRecorder]$recorder
  static $config = [LocalSTT]::LoadConfig()
  LocalSTT() {}

  static [IO.Fileinfo] RecordAudio() {
    return [LocalSTT]::RecordAudio([LocalSTT]::config.outFile)
  }
  static [IO.Fileinfo] RecordAudio([string]$outFile) {
    $_host_UI = (Get-Variable -Name Host -ValueOnly).UI
    $defaults = [LocalSTT]::config
    if ($null -ne [LocalSTT]::recorder) { [LocalSTT]::recorder.Stop() }
    [LocalSTT]::recorder = [AudioRecorder]::New([TcpListener]::new([IPEndpoint]::new([IPAddress][LocalSTT]::config.host, [LocalSTT]::config.port)), [IO.FileInfo]::New($outFile))
    $pythonProcess = Start-Process -FilePath "python" -ArgumentList "$($defaults.backgroundScript) --host `"$($defaults.host)`" --port $($defaults.port) --amplify-rate $($defaults.amplifyRate) --outfile `"$outFile`" --working-directory `"$($defaults.workingDirectory)`"" -PassThru -NoNewWindow
    Write-Host "STT server starting. PID: $($pythonProcess.Id)" -f Green
    $stream = [LocalSTT]::recorder.Start(); $buffer = [byte[]]::new(1024)
    try {
      while ($true) {
        if ($_host_UI.RawUI.KeyAvailable) {
          $key = $_host_UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
          if (($key.VirtualKeyCode -eq 67) -and $key.ControlKeyState.IsCtrl) {
            Write-Host "Ctrl+C pressed." -f Yellow
            [LocalSTT]::recorder.Stop($pythonProcess.Id)
            break
          }
        }
        $bytesRead = $stream.Read($buffer, 0, $buffer.Length)
        if ($bytesRead -gt 0) {
          $_str = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $bytesRead).Split('}{')[-1]; $c = [char]123
          $json = $_str.StartsWith($c) ? $_str : ([char]123 + $_str)
          $data = $json | ConvertFrom-Json
          $prog = $data.progress; $perc = ($prog -ge 100) ? 100 : $prog # failsafe to never exceed 100 and cause an error
          Write-Progress -Activity "[pyaudio]" -Status "$($data.status) $prog%" -PercentComplete $perc
        } else {
          Write-Host "No json data received. Python script may have stopped." -f Red
          break
        }
        [threading.Thread]::Sleep(200)
      }
    } catch {
      Write-Host "Error receiving data: $($_.Exception.Message)"
    } finally {
      [LocalSTT]::recorder.Stop($pythonProcess.Id)
    }
    return $outFile
  }
  static [PsObject] LoadConfig() {
    return [LocalSTT]::LoadConfig((Resolve-Path .).Path)
  }
  static [PsObject] LoadConfig([string]$current_path) {
    $module_path = (Get-Module LocalSTT -ListAvailable -Verbose:$false).ModuleBase
    $c = @{
      port             = 65432
      host             = "127.0.0.1"
      amplifyRate      = "1.0"
      workingDirectory = $current_path
      backgroundScript = [IO.Path]::Combine($module_path, "Private", "stt.py")
      outFile          = [IO.Path]::Combine($current_path, "$(Get-Date -Format 'yyyyMMddHHmmss')_output.wav")
    } -as "PsRecord"
    $c.PsObject.Properties.Add([PSScriptproperty]::New("env", { return [LocalSTT]::config.workingDirectory | New-PipEnv }, { throw [SetValueException]::new("env is read-only") }))
    return $c
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
    $Message = @(
      "Unable to register type accelerator '$($Type.FullName)'"
      'Accelerator already exists.'
    ) -join ' - '

    [System.Management.Automation.ErrorRecord]::new(
      [System.InvalidOperationException]::new($Message),
      'TypeAcceleratorAlreadyExists',
      [System.Management.Automation.ErrorCategory]::InvalidOperation,
      $Type.FullName
    ) | Write-Warning
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
