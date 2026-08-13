[CmdletBinding()]
param([string]$OutputPath)

$ErrorActionPreference = 'SilentlyContinue'
$taskName = 'Codex-WindowsUpdateGuard-Startup'
$task = Get-ScheduledTask -TaskName $taskName
$triggers = @($task.Triggers)
$actions = @($task.Actions)
$wu = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
$au = Join-Path $wu 'AU'
$services = @(Get-Service wuauserv,UsoSvc,WaaSMedicSvc | ForEach-Object {
    [pscustomobject]@{Name=$_.Name;Status=$_.Status.ToString();StartType=$_.StartType.ToString()}
})

$checks = [ordered]@{
    TaskExists = [bool]$task
    PrincipalIsSystem = ($task.Principal.UserId -eq 'SYSTEM')
    HighestRunLevel = ($task.Principal.RunLevel.ToString() -eq 'Highest')
    ExactlyOneTrigger = ($triggers.Count -eq 1)
    BootTriggerOnly = ($triggers.Count -eq 1 -and $triggers[0].CimClass.CimClassName -eq 'MSFT_TaskBootTrigger')
    NoTriggerRepetition = ($triggers.Count -eq 1 -and -not $triggers[0].Repetition.Interval)
    ExpectedAction = ($actions.Count -eq 1 -and $actions[0].Execute -eq 'powershell.exe' -and $actions[0].Arguments -match 'WindowsUpdateStartupGuard\\enforce\.ps1')
    NoPeriodicTask = -not [bool](Get-ScheduledTask -TaskName 'Codex-WindowsUpdateGuard-Periodic')
    NoAutoUpdate = ((Get-ItemPropertyValue $au NoAutoUpdate) -eq 1)
    WuauservBlocked = [bool]($services | Where-Object {$_.Name -eq 'wuauserv' -and $_.Status -eq 'Stopped' -and $_.StartType -eq 'Disabled'})
    UsoSvcBlocked = [bool]($services | Where-Object {$_.Name -eq 'UsoSvc' -and $_.Status -eq 'Stopped' -and $_.StartType -eq 'Disabled'})
}
$valid = -not (@($checks.GetEnumerator() | Where-Object {-not $_.Value}).Count)
$result = [ordered]@{Timestamp=(Get-Date).ToString('s');Valid=$valid;Checks=$checks;Services=$services;TaskName=$taskName}
$json = $result | ConvertTo-Json -Depth 7
if ($OutputPath) { $json | Set-Content -LiteralPath $OutputPath -Encoding UTF8 }
$json
if (-not $valid) { exit 2 }
