#Requires -RunAsAdministrator
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$wu = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
$au = Join-Path $wu 'AU'
$guardDir = 'C:\ProgramData\Codex\WindowsUpdateStartupGuard'
$resultPath = Join-Path $guardDir 'last_enforcement.json'
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'

$result = [ordered]@{ Timestamp=(Get-Date).ToString('s'); Policies=@(); Services=@() }
New-Item -Path $au -Force | Out-Null

$values = @(
    @{Path=$au;Name='NoAutoUpdate';Type='DWord';Value=1},
    @{Path=$au;Name='AUOptions';Type='DWord';Value=1},
    @{Path=$au;Name='NoAutoRebootWithLoggedOnUsers';Type='DWord';Value=1},
    @{Path=$wu;Name='DoNotIncludeDriversWithWindowsUpdates';Type='DWord';Value=1}
)
if ($cv.ProductName -match 'Windows (10|11)' -and $cv.CurrentBuild -ge 22000 -and $cv.DisplayVersion) {
    $values += @(
        @{Path=$wu;Name='ProductVersion';Type='String';Value='Windows 11'},
        @{Path=$wu;Name='TargetReleaseVersion';Type='DWord';Value=1},
        @{Path=$wu;Name='TargetReleaseVersionInfo';Type='String';Value=$cv.DisplayVersion}
    )
}

foreach ($item in $values) {
    try {
        New-ItemProperty -Path $item.Path -Name $item.Name -PropertyType $item.Type -Value $item.Value -Force | Out-Null
        $result.Policies += [ordered]@{Name=$item.Name;Value=(Get-ItemPropertyValue $item.Path $item.Name);Success=$true}
    } catch {
        $result.Policies += [ordered]@{Name=$item.Name;Success=$false;Error=$_.Exception.Message}
    }
}

foreach ($name in 'wuauserv','UsoSvc') {
    try { Stop-Service $name -Force -ErrorAction SilentlyContinue } catch {}
    try { Set-Service $name -StartupType Disabled -ErrorAction Stop } catch { & sc.exe config $name start= disabled | Out-Null }
    $svc = Get-Service $name -ErrorAction SilentlyContinue
    $result.Services += [ordered]@{Name=$name;Status=$svc.Status.ToString();StartType=$svc.StartType.ToString();Success=($svc.Status -eq 'Stopped' -and $svc.StartType -eq 'Disabled')}
}

try { Stop-Service WaaSMedicSvc -Force -ErrorAction SilentlyContinue } catch {}
$medic = Get-Service WaaSMedicSvc -ErrorAction SilentlyContinue
$result.Services += [ordered]@{Name='WaaSMedicSvc';Status=$medic.Status.ToString();StartType=$medic.StartType.ToString();Success=($medic.Status -eq 'Stopped');ProtectedStartTypePreserved=$true}

New-Item -ItemType Directory -Path $guardDir -Force | Out-Null
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $resultPath -Encoding UTF8
if (@($result.Policies | Where-Object {-not $_.Success}).Count -or @($result.Services | Where-Object {$_.Name -in 'wuauserv','UsoSvc' -and -not $_.Success}).Count) { exit 2 }

