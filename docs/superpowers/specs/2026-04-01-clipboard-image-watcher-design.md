# Clipboard Image Watcher for Claude Code (Windows)

## Problem

Windows 上 Claude Code CLI 的圖片貼上功能 (`Alt+V` / `chat:imagePaste`) 不穩定，常見問題包括：
- Snipping Tool 的 BMP 格式不被偵測
- 不同版本間反覆出現 regression
- 使用者期望 Ctrl+V 能直接貼圖，但原生不支援

## Solution

PowerShell 背景剪貼簿監視器。監控剪貼簿內容，偵測到圖片時自動存成 PNG 並將剪貼簿替換為檔案路徑文字，讓使用者用正常的 Ctrl+V 即可將截圖路徑貼入 Claude Code。

## Core Flow

```
啟動 → 每 500ms 輪詢剪貼簿
  → 嘗試存取剪貼簿（若被鎖定則跳過本次輪詢）
  → 剪貼簿有 bitmap 圖片？（使用 ContainsImage() 偵測）
    → 是：計算圖片尺寸簽名（寬x高+前 1024 bytes hash），與上次比較
      → 新圖片：存 PNG 到 %TEMP%/claude-screenshots/clipboard_YYYYMMDD_HHmmss_fff.png
      → 將剪貼簿替換為該檔案的絕對路徑文字
      → 更新簽名記錄
    → 否：不做任何事（保留原始文字內容）
```

### Key Details

- **去重機制**：用圖片尺寸 + 前 1024 bytes 的 hash 作為簽名。bitmap 替換為路徑文字後，下次輪詢看到的是文字（非 bitmap），自然不會重複處理。簽名主要防止使用者連續複製同一張圖時重複存檔。
- **格式偵測**：使用 `[System.Windows.Forms.Clipboard]::ContainsImage()` 偵測。此方法覆蓋 `CF_BITMAP`、`CF_DIB`、`CF_DIBV5` 等標準格式，能處理 Snipping Tool、Print Screen、第三方截圖工具的圖片。
- **輪詢間隔**：500ms，CPU 佔用極低（目標 < 0.1% CPU、< 20MB RAM）
- **文字貼上不受影響**：僅在 `ContainsImage()` 為 true 時介入，純文字內容完全不處理
- **檔名精度**：時間戳精確到毫秒（`_fff`），避免同秒內多次截圖導致檔名衝突

## File Structure

```
clipboard-image-watcher/
├── clipboard-image-watcher.ps1   # 核心監視腳本
├── start-watcher.bat             # 啟動（隱藏視窗）
├── stop-watcher.bat              # 停止
├── install.bat                   # 一鍵安裝
└── uninstall.bat                 # 一鍵卸載
```

## Startup & Lifecycle

### install.bat (One-click Setup)

1. 建立 `%TEMP%/claude-screenshots/` 目錄
2. 使用 PowerShell 讀取 `~/.claude/settings.json`，以 JSON 合併方式（`ConvertFrom-Json` → 修改 → `ConvertTo-Json`）新增 SessionStart hook，保留既有設定不被覆蓋
3. 用 `%~dp0` 取得腳本所在目錄的絕對路徑
4. 立即啟動監視器

### Claude Code Hook (SessionStart)

在 `~/.claude/settings.json` 中配置：
```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "powershell.exe -ExecutionPolicy Bypass -File \"C:/absolute/path/to/start-watcher.ps1\"",
            "timeout": 5,
            "async": true
          }
        ]
      }
    ]
  }
}
```

**重點**：
- `async: true`：非阻塞，不會拖慢 Claude Code 啟動
- `timeout: 5`：啟動腳本本身只是 spawn 背景程序，5 秒足夠
- 路徑由 `install.bat` 自動填入絕對路徑

### start-watcher.bat / start-watcher.ps1

- 用 `powershell.exe`（5.1，STA 模式）執行，**不是** `pwsh.exe`（7+，MTA 模式會導致 Clipboard API 失敗）
- 用 `Start-Process -WindowStyle Hidden` 啟動背景 PowerShell 腳本
- 啟動前用 named mutex (`Global\ClaudeClipboardWatcher`) 檢查是否已有實例執行，避免重複啟動
- 視窗隱藏，背景執行

### stop-watcher.bat

- 建立 sentinel 檔案 `%TEMP%/claude-screenshots/.stop`，監視腳本每次輪詢時檢查此檔案並自行優雅退出
- 備用：用 `Get-Process` + command line 過濾找到對應程序並結束

### uninstall.bat

1. 停止監視器
2. 從 `~/.claude/settings.json` 移除 SessionStart hook（JSON 合併方式）
3. 可選清理 `%TEMP%/claude-screenshots/`

## Error Handling

- **剪貼簿被鎖定**（其他應用佔用）：`try/catch` 捕獲 `ExternalException`，跳過本次輪詢，下次重試
- **PNG 存檔失敗**（磁碟滿或權限問題）：`try/catch` 捕獲，記錄錯誤到 log，不修改剪貼簿
- **腳本崩潰**：下次啟動 Claude Code 時 SessionStart hook 會重新啟動監視器，自動恢復
- **日誌**：錯誤寫入 `%TEMP%/claude-screenshots/watcher.log`，僅記錄錯誤和啟動/停止事件，正常運行不產生日誌

## Edge Cases & Limitations

### Handled

- 使用者複製圖片 → 存 PNG、剪貼簿變路徑 → Ctrl+V 貼路徑
- 使用者再複製文字 → 腳本不介入 → Ctrl+V 正常貼文字
- 使用者再截新圖 → 簽名不同 → 存新 PNG、更新剪貼簿
- 剪貼簿被其他應用鎖定 → 跳過本次，下次重試
- 腳本崩潰 → 下次開 Claude Code 自動恢復

### Known Limitations (Explicitly Not Handled)

- **剪貼簿圖片被替換**：圖片存檔後剪貼簿變成路徑文字，無法再貼到其他應用（如 LINE、Word）。需重新截圖。這是方案 B 的固有取捨。
- **檔案複製不處理**：從檔案總管複製的 .png 檔不會被處理，僅處理 bitmap 圖片資料。
- **暫存不主動清理**：`%TEMP%/claude-screenshots/` 不主動清理，依賴系統重啟或磁碟清理工具。
- **同時含圖片和文字的剪貼簿**：某些應用（如瀏覽器複製圖片元素）會同時放入 bitmap 和文字。腳本以 bitmap 優先處理，因為主要使用場景是截圖。

## Technical Notes

- **PowerShell 版本**：必須使用 `powershell.exe`（Windows 內建 5.1，預設 STA 模式）。`pwsh.exe`（PowerShell 7+）預設 MTA 模式，`System.Windows.Forms.Clipboard` 會失敗。
- 使用 `[System.Windows.Forms.Clipboard]::ContainsImage()` 和 `GetImage()` 存取剪貼簿
- 使用 `System.Drawing` 將 bitmap 存為 PNG 格式
- 使用圖片尺寸 + 部分像素 hash 做去重（比 MD5 全圖 hash 快）
- 不需要額外安裝任何依賴（全部使用 Windows 內建 .NET Framework）

## Acceptance Tests

1. **截圖貼上**：Win+Shift+S 截圖 → Ctrl+V 到 Claude Code → 看到 PNG 檔案路徑
2. **文字貼上**：複製一段文字 → Ctrl+V → 正常貼上文字
3. **連續截圖**：截圖兩次 → 各自存成不同 PNG
4. **不重複處理**：截圖一次 → 路徑貼上後再按 Ctrl+V → 貼上同一路徑文字（不會再存新檔）
5. **Claude Code 重啟**：關閉再開啟 Claude Code → 監視器自動啟動
