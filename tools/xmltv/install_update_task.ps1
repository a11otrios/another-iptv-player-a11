$ErrorActionPreference = 'Stop'

$taskName = 'Another IPTV Player - Update UK and Greek EPG'
$scriptPath = Join-Path $PSScriptRoot 'update_uk_greece_guide.py'
$pythonPath = (Get-Command python -ErrorAction Stop).Source
$action = New-ScheduledTaskAction -Execute $pythonPath -Argument ('"{0}"' -f $scriptPath)
$triggers = @(
    New-ScheduledTaskTrigger -Daily -At 6:00AM
    New-ScheduledTaskTrigger -Daily -At 6:00PM
)
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $triggers `
    -Description 'Downloads and merges the public UK and Greek XMLTV guides.' -Force | Out-Null

& $pythonPath $scriptPath
if ($LASTEXITCODE -ne 0) {
    throw 'The initial XMLTV download failed; the scheduled task remains installed and will retry.'
}
