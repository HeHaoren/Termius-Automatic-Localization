# Registers (or refreshes) the scheduled task that runs the auto-updater.
# Triggers: at user logon + once a day at 20:30 (a missed daily run starts
# as soon as possible afterwards). Run as administrator for the highest
# run level. Change the StartBoundary time below to reschedule the daily check.
$TaskName   = 'Termius-Localize-AutoUpdate'
$ScriptPath = Join-Path $PSScriptRoot 'update-termius-localize.ps1'
$VbsPath    = Join-Path $PSScriptRoot 'run-hidden.vbs'
$Sid        = ([System.Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
$Tomorrow   = (Get-Date).AddDays(1).ToString('yyyy-MM-dd')

$Xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Auto-apply Termius zh-CN localization when Termius updates (daily check + at logon)</Description>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <UserId>$Sid</UserId>
      <Delay>PT3M</Delay>
    </LogonTrigger>
    <CalendarTrigger>
      <StartBoundary>${Tomorrow}T12:00:00</StartBoundary>
      <Enabled>true</Enabled>
      <ScheduleByDay>
        <DaysInterval>1</DaysInterval>
      </ScheduleByDay>
    </CalendarTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$Sid</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <StartWhenAvailable>true</StartWhenAvailable>
    <ExecutionTimeLimit>PT20M</ExecutionTimeLimit>
    <Enabled>true</Enabled>
    <AllowHardTerminate>true</AllowHardTerminate>
    <Hidden>true</Hidden>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>wscript.exe</Command>
      <Arguments>"$VbsPath"</Arguments>
    </Exec>
  </Actions>
</Task>
"@

$XmlFile = Join-Path $PSScriptRoot 'task.xml'
# schtasks requires the task XML to be UTF-16
[System.IO.File]::WriteAllText($XmlFile, $Xml, [System.Text.Encoding]::Unicode)

schtasks /Create /F /TN $TaskName /XML $XmlFile
if ($LASTEXITCODE -eq 0) {
    Write-Host "Task registered OK: $TaskName"
} else {
    Write-Host "ERROR: schtasks exited with code $LASTEXITCODE"
}
