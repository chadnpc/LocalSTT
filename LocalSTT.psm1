#!/usr/bin/env pwsh
using namespace System.IO
using namespace System.Net
using namespace System.Net.Sockets
using namespace System.Collections.Generic
using namespace System.Management.Automation

#Requires -Modules pipEnv, cliHelper.core
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
  PyenvHelper() {
    $this.PsObject.Properties.Add([psscriptproperty]::new('pyversion', { $v = (&"/$(Get-Variable HOME -ValueOnly)/.pyenv/shims/python" --version).Split(" ")[1]; return [version]::new($v) }, { throw 'pyversion is read-only' }))
  }
  [void] Useversion([string]$ver) {
    $this.Useversion([version]::new($ver), [ref][LocalSTT]::data)
  }
  [void] Useversion([version]$ver, [ref]$config) {
    if ($this.pyversion -lt $ver) {
      Write-Console "Installing Python v$ver..." -f SlateBlue
      pyenv install $ver.ToString()
    }
    pyenv local "$ver"
    $config.Value.Env.PythonVersion = $ver
    if ($this.pyversion -ne $ver) {
      throw [InvalidOperationException]::new("Failed to set Python version to $ver")
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
class LocalSTT : ThreadRunner {
  static [PsRecord]$data = (Get-Config)
  static [cliart]$banner = "H4sIAAAAAAAAA+2YS4/aMBRGf1AWWcydyaoLaloeF8lIRerAbiIF53qmOAaSVv31lXEYHMchLCoBEoujQHL9iMT5bAOaDeDBf4WVKARvQYKjVBxFwVHmHPOCY26ugdoHPoMtqcmwSbIghU8WiEk9p/b6VvOStts8cBig99tVoPkaNE9B8z1o/gM024Dmr6BHc9B8bD+z79d27I78p5KjrCKU7yXK9wjFPsJ8G2GeRyg/LLm5J7Ib8Oxe/C+G1vFZQmqV2gx4XpN6eyK1MldDTGo5uwHP7sb/36B5DJrtLdw4/9NeR5WFV6DZt2s7dif+046j0Nx6XnVQ2AwQeYZ5Ht47PHD930pLEvezfCW1XN+Aa7fuP4LF+N/HaGy5vmu37n/prP89mP2A4bOt4ijNWaE+J5w7UxzrDueKQJ0UTs25OnM+Cd0v+ufSNS+/vY/pz33XEE3/p5LUMiW1rc67n8ak9JjUxPHfzQ0/F5Q5U/zt7u94ntCmLmk/X8WkJuNmn8mwbhvIoEZO9WSUOeu49X77Vu6t+zOyvf7/AT0ya/sKNEtAs9hhDZrNQKOpy5rt3Nzwc+GSTDFteOR8n4NmX0GzSdsvXu9RPtl4z71+uzzl7pzjerwL3yk0VtD/T35lKHYlUu3ewUdl/wMQHyUKOnnvZkdjj+D6d0GmCBEhldnp3r7uY990WO46+ipOc2rtV0LuVuUpyw7jZ2ffyc26RtY03sFd/42fMCT1srAcnEi7Mb4ea2FBaun5nwT8m25IzQLPp8aXuZNBG1LbQN5MzNg9bh6z4FJ3zXwO43vZckmmhbLmtP5/+Qcw8c7nABQAAA=="
  static [ValidateNotNull()][AudioRecorder]$recorder
  LocalSTT() {}

  static [IO.Fileinfo] RecordAudio() { return [LocalSTT]::RecordAudio(3) }

  static [IO.Fileinfo] RecordAudio([float]$minutes) {
    return [LocalSTT]::RecordAudio([LocalSTT]::data.Server.outFile, [Timespan]::new(0, 0, $minutes * 60))
  }
  static [IO.Fileinfo] RecordAudio([string]$outFile, [float]$minutes) {
    return [LocalSTT]::RecordAudio($outFile, [Timespan]::new(0, 0, $minutes * 60))
  }
  static [IO.Fileinfo] RecordAudio([string]$outFile, [Timespan]$duration) {
    [ValidateNotNullOrWhiteSpace()][string]$outFile = $outFile
    Resolve-Requirements ([ref][LocalSTT]::data) -ea stop -Verbose:$false
    $py = [IO.FileInfo][IO.Path]::Combine((Get-Variable HOME -Scope Global -ValueOnly), ".pyenv", "shims", "python")
    $_c = [LocalSTT].config; [LocalSTT]::recorder = [AudioRecorder]::New([TcpListener]::new([IPEndpoint]::new([IPAddress]$_c.Server.host, $_c.Server.port)), [IO.FileInfo]::New($outFile)); $dir = $_c.Server.workingDirectory
    [LocalSTT]::data.Process = Start-Process -FilePath "$py" -ArgumentList "$($_c.Server.Script) --host `"$($_c.Server.host)`" --port $($_c.Server.port) --amplify-rate $($_c.Server.amplifyRate) --outfile `"$outFile`" --duration-in-minutes=$($duration.TotalMinutes) --working-directory `"$dir`"" -WorkingDirectory $dir -PassThru -NoNewWindow
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
    Resolve-Requirements ([ref][LocalSTT]::data) -ea stop -Verbose:$false
    $_c = [LocalSTT].config; $py = [IO.FileInfo][IO.Path]::Combine((Get-Variable HOME -Scope Global -ValueOnly), ".pyenv", "shims", "python")
    $_t = [IO.Path]::Combine(($_c.Server.Script | Split-Path), "transcribe.py"); $dir = $_c.Server.workingDirectory
    $Process = Start-Process -FilePath "$py" -ArgumentList "$_t --inputfile `"$inputFile`" --outfile `"$outFile`" --working-directory `"$dir`"" -WorkingDirectory $dir -PassThru -NoNewWindow;
    $Process.WaitForExit()
    $process.Kill(); $Process.Dispose()
    return [IO.File]::ReadAllText($outFile)
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
