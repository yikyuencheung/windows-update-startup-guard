# Safety and recovery

## What the guard changes

The installer writes these policy values under `HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate` and its `AU` child:

- `NoAutoUpdate=1`
- `AUOptions=1`
- `NoAutoRebootWithLoggedOnUsers=1`
- `DoNotIncludeDriversWithWindowsUpdates=1`
- `ProductVersion=Windows 11`
- `TargetReleaseVersion=1`
- `TargetReleaseVersionInfo=<current DisplayVersion>`

It stops and disables `wuauserv` and `UsoSvc`. It attempts to stop `WaaSMedicSvc` but does not change ownership, ACLs, or its protected start type.

It installs one task named `Codex-WindowsUpdateGuard-Startup`, running as `SYSTEM` at highest privilege with an `AtStartup` trigger. The task reapplies the settings once per boot.

## Expected side effects

- Windows security and quality updates do not download automatically.
- Microsoft Store automatic updates and some Defender update paths can be affected.
- Driver delivery through Windows Update is disabled.
- The Settings Windows Update page can show policy-managed status or errors.
- Manual checking can remain unavailable until restoration.

## Non-goals

Do not add a five-minute watchdog. Do not configure an invalid WSUS server. Do not block Microsoft endpoints in hosts or a firewall. Do not delete `SoftwareDistribution`, servicing stack files, scheduled tasks owned by Windows, or update executables. Do not disable Defender.

## Recovery

The installer writes `install_manifest.json` in `C:\ProgramData\Codex\WindowsUpdateStartupGuard`. It records whether each managed policy existed, its value and registry kind, plus original service start values and running states.

`restore.ps1` deletes the skill-owned task, removes the managed values, restores captured values, restores service start values, restarts services that were running, writes a restoration result beside the script, then removes the installed payload directory.

If the manifest is unavailable, restoration removes only the known skill-owned values and uses conservative defaults: `wuauserv=Manual`, `UsoSvc=Automatic`, `WaaSMedicSvc=Manual`.

## Evidence boundary

The guard reduces automatic update and restart risk but is not absolute. A Windows feature upgrade, repair install, domain or MDM policy, administrator action, or security remediation can reset the task, services, or policies. Verify again after major system servicing.

Official references:

- Microsoft Learn, Windows Update policy registry settings: https://learn.microsoft.com/windows/deployment/update/waas-wu-settings
- Microsoft Learn, manage device restarts after updates: https://learn.microsoft.com/windows/deployment/update/waas-restart

