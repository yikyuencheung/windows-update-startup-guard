[CmdletBinding()]
param([switch]$NoSelfElevate)

$ErrorActionPreference = 'Continue'
$guardDir = 'C:\ProgramData\Codex\WindowsUpdateStartupGuard'
$manifestPath = Join-Path $guardDir 'install_manifest.json'
$resultPath = Join-Path $PSScriptRoot 'restore_result.json'
$taskName = 'Codex-WindowsUpdateGuard-Startup'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    if ($NoSelfElevate) { throw 'Administrator rights are required.' }
    $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$PSCommandPath+'"'),'-NoSelfElevate')
    $p = Start-Process powershell.exe -ArgumentList $args -Verb RunAs -PassThru -Wait
    exit $p.ExitCode
}

$manifest = if (Test-Path $manifestPath) { Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

$known = @(
    @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU';Name='NoAutoUpdate'},
    @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU';Name='AUOptions'},
    @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU';Name='NoAutoRebootWithLoggedOnUsers'},
    @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate';Name='DoNotIncludeDriversWithWindowsUpdates'},
    @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate';Name='ProductVersion'},
    @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate';Name='TargetReleaseVersion'},
    @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate';Name='TargetReleaseVersionInfo'}
)
foreach ($item in $known) { Remove-ItemProperty -Path $item.Path -Name $item.Name -ErrorAction SilentlyContinue }

if ($manifest) {
    foreach ($item in $manifest.Policies | Where-Object {$_.Existed}) {
        New-Item -Path $item.Path -Force | Out-Null
        New-ItemProperty -Path $item.Path -Name $item.Name -PropertyType $item.Kind -Value $item.Value -Force | Out-Null
    }
    $serviceState = $manifest.Services
} else {
    $serviceState = @(
        [pscustomobject]@{Name='wuauserv';Start=3;WasRunning=$true},
        [pscustomobject]@{Name='UsoSvc';Start=2;WasRunning=$true},
        [pscustomobject]@{Name='WaaSMedicSvc';Start=3;WasRunning=$false}
    )
}

foreach ($svc in $serviceState) {
    & reg.exe add "HKLM\SYSTEM\CurrentControlSet\Services\$($svc.Name)" /v Start /t REG_DWORD /d $svc.Start /f | Out-Null
    if ($svc.WasRunning) { Start-Service $svc.Name -ErrorAction SilentlyContinue }
}

$serviceRows = @(Get-Service wuauserv,UsoSvc,WaaSMedicSvc | ForEach-Object {
    [pscustomobject]@{Name=$_.Name;Status=$_.Status.ToString();StartType=$_.StartType.ToString()}
})
$result = [ordered]@{
    Timestamp=(Get-Date).ToString('s')
    UsedManifest=[bool]$manifest
    TaskRemoved=-not [bool](Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)
    Services=$serviceRows
}
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $resultPath -Encoding UTF8
Remove-Item -LiteralPath $guardDir -Recurse -Force -ErrorAction SilentlyContinue
$result | ConvertTo-Json -Depth 6
