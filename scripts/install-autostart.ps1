# Register the start script to run at logon for the current user.
# Logon, rather than a SYSTEM task at boot, so the server keeps this user's
# venv and GPU.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$start = Join-Path $PSScriptRoot "start.ps1"
$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$start`"" `
    -WorkingDirectory $Root
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
Register-ScheduledTask `
    -TaskName "GoneFishingLocalEncoder" `
    -Action $action `
    -Trigger $trigger `
    -Force | Out-Null
Write-Host "GoneFishingLocalEncoder will run at logon for $env:USERNAME"
