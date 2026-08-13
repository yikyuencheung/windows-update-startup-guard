[CmdletBinding()]
param(
    [switch]$ValidateOnly,
    [switch]$NoSelfElevate
)

$ErrorActionPreference = 'Stop'
$skillRoot = Split-Path $PSScriptRoot -Parent
$enforceSource = Join-Path $PSScriptRoot 'enforce.ps1'
$verifySource = Join-Path $PSScriptRoot 'verify.ps1'
$guardDir = 'C:\ProgramData\Codex\WindowsUpdateStartupGuard'
$enforceTarget = Join-Path $guardDir 'enforce.ps1'
$manifestPath = Join-Path $guardDir 'install_manifest.json'
$taskName = 'Codex-WindowsUpdateGuard-Startup'

foreach ($required in $enforceSource,$verifySource) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Missing required skill resource: $required" }
}
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
if ([int]$cv.CurrentBuild -lt 22000) { throw 'This skill supports Windows 11 only.' }
if ($ValidateOnly) {
    [ordered]@{Valid=$true;WindowsBuild=$cv.CurrentBuild;DisplayVersion=$cv.DisplayVersion;SkillRoot=$skillRoot;RequiredFilesPresent=$true} | ConvertTo-Json
    exit 0
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    if ($NoSelfElevate) { throw 'Administrator rights are required.' }
    $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$PSCommandPath+'"'),'-NoSelfElevate')
    $p = Start-Process powershell.exe -ArgumentList $args -Verb RunAs -PassThru -Wait
    exit $p.ExitCode
}

$managed = @(
    @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU';Name='NoAutoUpdate'},
    @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU';Name='AUOptions'},
    @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU';Name='NoAutoRebootWithLoggedOnUsers'},
    @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate';Name='DoNotIncludeDriversWithWindowsUpdates'},
    @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate';Name='ProductVersion'},
    @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate';Name='TargetReleaseVersion'},
    @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate';Name='TargetReleaseVersionInfo'}
)
$policyBackup = foreach ($item in $managed) {
    $exists = $false; $value = $null; $kind = $null
    if (Test-Path $item.Path) {
        $key = Get-Item $item.Path
        if ($key.GetValueNames() -contains $item.Name) { $exists=$true; $value=$key.GetValue($item.Name,$null,'DoNotExpandEnvironmentNames'); $kind=$key.GetValueKind($item.Name).ToString() }
    }
    [ordered]@{Path=$item.Path;Name=$item.Name;Existed=$exists;Value=$value;Kind=$kind}
}
$serviceBackup = foreach ($name in 'wuauserv','UsoSvc','WaaSMedicSvc') {
    $svc = Get-Service $name
    [ordered]@{Name=$name;Start=(Get-ItemPropertyValue "HKLM:\SYSTEM\CurrentControlSet\Services\$name" Start);WasRunning=($svc.Status -eq 'Running')}
}
$manifest = [ordered]@{InstalledAt=(Get-Date).ToString('s');SkillName='windows-update-startup-guard';Policies=$policyBackup;Services=$serviceBackup}

New-Item -ItemType Directory -Path $guardDir -Force | Out-Null
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
Copy-Item -LiteralPath $enforceSource -Destination $enforceTarget -Force
& icacls.exe $guardDir /inheritance:r /grant:r 'SYSTEM:(OI)(CI)F' 'Administrators:(OI)(CI)F' 'Users:(OI)(CI)RX' | Out-Null

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $enforceTarget
if ($LASTEXITCODE -notin 0,2) { throw "Initial enforcement failed with exit code $LASTEXITCODE" }

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$enforceTarget`""
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $verifySource -OutputPath (Join-Path $PSScriptRoot 'install_verification.json')
exit $LASTEXITCODE

