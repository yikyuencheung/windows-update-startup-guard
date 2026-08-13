[CmdletBinding()]
param()

$ErrorActionPreference = 'SilentlyContinue'
$wu = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
$au = Join-Path $wu 'AU'
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'

function Read-Value([string]$Path, [string]$Name) {
    if (-not (Test-Path $Path)) { return $null }
    try { return Get-ItemPropertyValue -Path $Path -Name $Name -ErrorAction Stop } catch { return $null }
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$task = if ($isAdmin) { Get-ScheduledTask -TaskName 'Codex-WindowsUpdateGuard-Startup' -ErrorAction SilentlyContinue } else { $null }
$serviceRows = @(Get-Service wuauserv,UsoSvc,WaaSMedicSvc -ErrorAction SilentlyContinue | ForEach-Object {
    [ordered]@{Name=$_.Name;Status=$_.Status.ToString();StartType=$_.StartType.ToString()}
})
$result = [ordered]@{
    Timestamp = (Get-Date).ToString('s')
    Windows = [ordered]@{
        ProductName = if ([int]$cv.CurrentBuild -ge 22000) { 'Windows 11' } else { $cv.ProductName }
        EditionID = $cv.EditionID
        DisplayVersion = $cv.DisplayVersion
        Build = "$($cv.CurrentBuild).$($cv.UBR)"
    }
    Policies = [ordered]@{
        NoAutoUpdate = Read-Value $au 'NoAutoUpdate'
        AUOptions = Read-Value $au 'AUOptions'
        NoAutoRebootWithLoggedOnUsers = Read-Value $au 'NoAutoRebootWithLoggedOnUsers'
        DoNotIncludeDriversWithWindowsUpdates = Read-Value $wu 'DoNotIncludeDriversWithWindowsUpdates'
        ProductVersion = Read-Value $wu 'ProductVersion'
        TargetReleaseVersion = Read-Value $wu 'TargetReleaseVersion'
        TargetReleaseVersionInfo = Read-Value $wu 'TargetReleaseVersionInfo'
    }
    Services = $serviceRows
    Guard = [ordered]@{
        TaskQueryAvailable = $isAdmin
        TaskExists = if ($isAdmin) { [bool]$task } else { $null }
        TaskState = if ($task) { $task.State.ToString() } else { $null }
        Principal = if ($task) { $task.Principal.UserId } else { $null }
        RunLevel = if ($task) { $task.Principal.RunLevel.ToString() } else { $null }
        InstalledPayloadExists = Test-Path 'C:\ProgramData\Codex\WindowsUpdateStartupGuard\enforce.ps1'
        PeriodicTaskExists = if ($isAdmin) { [bool](Get-ScheduledTask -TaskName 'Codex-WindowsUpdateGuard-Periodic' -ErrorAction SilentlyContinue) } else { $null }
    }
}

$result | ConvertTo-Json -Depth 7
