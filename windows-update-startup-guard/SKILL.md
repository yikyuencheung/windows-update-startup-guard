---
name: windows-update-startup-guard
description: Install, audit, verify, or remove a conservative Windows 11 startup-only guard that disables automatic Windows Update at boot. Use when a user explicitly asks to stop Windows automatic updates or forced update restarts, requests a portable Windows Update blocking package, or needs to restore a guard previously installed by this skill. Do not use for ordinary update troubleshooting, one-time update pauses, Windows Server, or without explicit approval of the security and Microsoft Store side effects.
---

# Windows Update Startup Guard

Use the bundled PowerShell scripts. Do not reconstruct registry commands ad hoc.

## Safety boundary

- Support Windows 11 only.
- Require explicit user approval before installing because security fixes, Microsoft Store updates, Defender update paths, and driver delivery may be affected.
- Do not promise that updates are blocked forever. A feature upgrade, repair install, administrator, security product, or policy manager can undo the settings.
- Install only one `AtStartup` task. Never add periodic triggers, logon triggers, blank WSUS endpoints, hosts entries, firewall blocks, permission takeovers, or deletion of Windows servicing components.
- Do not disable BITS, Delivery Optimization, Microsoft Defender, or Microsoft Store services.
- Do not take ownership of `WaaSMedicSvc`; stop it opportunistically but preserve its protected start configuration.
- Preserve existing policy values and service start states in the installer manifest so removal can restore them.

Read [references/safety-and-recovery.md](references/safety-and-recovery.md) before installation or restoration.

## Workflow

1. Run the read-only audit:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\audit.ps1
   ```

2. Report the current edition, version, relevant policy values, service states, and whether the guard already exists.

3. Explain the side effects and obtain explicit approval.

4. Validate the package without changing the system:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -ValidateOnly
   ```

5. Install. The script self-elevates and Windows may show UAC:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
   ```

6. Verify after installation:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify.ps1
   ```

7. Report the exact result. A valid installation must have:

   - task `Codex-WindowsUpdateGuard-Startup`;
   - principal `SYSTEM` with highest run level;
   - exactly one boot trigger with no repetition;
   - no `Codex-WindowsUpdateGuard-Periodic` task;
   - `NoAutoUpdate=1`;
   - `wuauserv` and `UsoSvc` stopped and disabled.

## Restore

Use the bundled restorer, not manual deletion:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\restore.ps1
```

Then run `audit.ps1` and report restored policy and service states. The restorer uses the manifest captured at installation; if the manifest is missing, it removes only values owned by this skill and restores conservative Windows defaults.

## Script roles

- `scripts/audit.ps1`: read-only system and guard inventory.
- `scripts/install.ps1`: validate, back up, install, enforce once, and register the boot task.
- `scripts/enforce.ps1`: task payload copied to protected ProgramData and run at startup.
- `scripts/verify.ps1`: read-only compliance check with a machine-readable JSON result.
- `scripts/restore.ps1`: remove the task and restore captured policy and service state.

