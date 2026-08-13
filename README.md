# Disable Windows Automatic Updates

一個用來停用 Windows 11 自動更新及更新後自動重新啟動的可攜式 Skill，適用於 Codex 和其他能讀取本機檔案、執行 PowerShell 的 AI 工具。

取得使用者明確同意後，它會停用 Windows Update 的自動更新服務與相關原則，並建立一個只在開機時執行一次的 `SYSTEM` 排程工作，讓設定在每次開機時重新生效。

本專案的目標是直接停用自動更新，同時保留可審計、可驗證及可完整還原的安全邊界。它不會建立每 5 分鐘執行的守護工作，不會設定無效 WSUS、修改 hosts 或防火牆，也不會刪除 Windows 更新元件。

## 重要限制

- 僅支援 Windows 11。
- 停用自動更新會降低安全性，並可能影響 Microsoft Store、自動驅動程式交付，以及部分 Microsoft Defender 更新來源。
- 本工具不能保證「永久」阻止所有更新。功能更新、修復安裝、網域或 MDM 原則、系統管理員及安全軟體都可能重設相關設定。
- 安裝系統守護前必須取得使用者明確同意，並接受 UAC 提權。

## 專案結構

```text
.
├── AI_INSTRUCTIONS.txt
├── install_skill.ps1
└── windows-update-startup-guard
    ├── SKILL.md
    ├── agents
    │   └── openai.yaml
    ├── references
    │   └── safety-and-recovery.md
    └── scripts
        ├── audit.ps1
        ├── enforce.ps1
        ├── install.ps1
        ├── restore.ps1
        └── verify.ps1
```

## 安裝 Skill

在專案根目錄開啟 PowerShell，執行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install_skill.ps1
```

這個步驟只會把 Skill 複製到 `%USERPROFILE%\.codex\skills\windows-update-startup-guard`，不會修改 Windows Update。

如需覆蓋既有 Skill：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install_skill.ps1 -Force
```

原有版本會先移至帶時間戳記的備份目錄。

## 讓 AI 工具操作

將整個專案交給可讀取本機檔案並執行 PowerShell 的 AI 工具，要求它先完整讀取：

```text
AI_INSTRUCTIONS.txt
windows-update-startup-guard\SKILL.md
```

AI 必須先執行唯讀審計、說明副作用並取得明確同意，才可進行系統安裝。完整流程已寫在 `AI_INSTRUCTIONS.txt`。

## 手動操作

以下命令請在 `windows-update-startup-guard` 目錄執行。

### 1. 唯讀審計

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\audit.ps1
```

輸出 Windows 版本、相關原則、服務狀態及既有守護工作資訊，不修改系統。

### 2. 無變更驗證

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -ValidateOnly
```

檢查 Windows 版本及必要檔案是否齊全，不建立工作、不修改登錄或服務。

### 3. 安裝開機守護

確認接受副作用後執行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

安裝程式會要求 UAC，備份目前的相關原則與服務狀態，然後建立唯一的 `Codex-WindowsUpdateGuard-Startup` 開機工作。該工作以 `SYSTEM` 最高權限執行，且沒有週期性觸發。

### 4. 驗證安裝

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify.ps1
```

成功時輸出的 JSON 中 `Valid` 應為 `true`；失敗時程序結束碼為 `2`。

### 5. 完整還原

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\restore.ps1
```

還原程式會移除 Skill 建立的排程工作，並優先依安裝時儲存的 manifest 還原原則及服務狀態。完成後再執行 `audit.ps1` 核對結果。

## 會修改的內容

- Windows Update 原則：`NoAutoUpdate`、`AUOptions`、`NoAutoRebootWithLoggedOnUsers`、驅動程式更新及目前 Windows 11 目標版本設定。
- 服務：停止並停用 `wuauserv`、`UsoSvc`。
- `WaaSMedicSvc`：只嘗試停止，不變更其受保護的啟動類型、擁有者或 ACL。
- 排程工作：只建立 `Codex-WindowsUpdateGuard-Startup`，並且只在開機時觸發一次。

詳細的安全邊界及復原機制請參閱 [`windows-update-startup-guard/references/safety-and-recovery.md`](windows-update-startup-guard/references/safety-and-recovery.md)。

## 移除 Skill 檔案

先執行 `restore.ps1` 還原系統，再刪除：

```text
%USERPROFILE%\.codex\skills\windows-update-startup-guard
```

只刪除 Skill 目錄不會自動還原已修改的 Windows 設定。

## 責任聲明

本專案會變更系統更新行為。使用者應自行安排定期手動更新與安全維護，並在重大 Windows 維護後重新執行審計及驗證。
