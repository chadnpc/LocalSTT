function IsFirstRun {
  return $null -eq ([LocalSTT] | Get-Member -Name config -Type ScriptProperty)
}