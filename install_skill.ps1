[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$DestinationRoot,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$source = Join-Path $PSScriptRoot 'windows-update-startup-guard'
if (-not (Test-Path -LiteralPath (Join-Path $source 'SKILL.md'))) {
    throw "Skill source is incomplete: $source"
}

if (-not $DestinationRoot) {
    $base = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
    $DestinationRoot = Join-Path $base 'skills'
}
$DestinationRoot = [IO.Path]::GetFullPath($DestinationRoot)
$destination = Join-Path $DestinationRoot 'windows-update-startup-guard'

if (Test-Path -LiteralPath $destination) {
    if (-not $Force) {
        throw "Skill already exists at $destination. Re-run with -Force only if replacement is intended."
    }
    $backup = "$destination.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    if ($PSCmdlet.ShouldProcess($destination, "Move existing skill to $backup")) {
        Move-Item -LiteralPath $destination -Destination $backup
    }
}

if ($PSCmdlet.ShouldProcess($destination, 'Install windows-update-startup-guard skill')) {
    New-Item -ItemType Directory -Path $DestinationRoot -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Recurse
}

[ordered]@{
    Installed = Test-Path -LiteralPath (Join-Path $destination 'SKILL.md')
    Destination = $destination
    SystemSettingsChanged = $false
    NextStep = 'Start a new AI session and invoke $windows-update-startup-guard.'
} | ConvertTo-Json
