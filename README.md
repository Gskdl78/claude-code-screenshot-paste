# Claude Code 小工具集

Windows 上 Claude Code CLI 的實用工具集合。

---

## Clipboard Image Watcher

解決 Windows 上 Claude Code 無法用 Ctrl+V 貼上截圖的問題。

### 問題背景

Claude Code CLI 在 Windows 上的圖片貼上功能（`Alt+V` / `chat:imagePaste`）長期不穩定，包括 Snipping Tool 的 BMP 格式不被偵測、不同版本間反覆出現 regression 等。本工具透過背景監控剪貼簿的方式，完全繞過原生功能的限制。

### 原理

背景 PowerShell 腳本每 500ms 輪詢剪貼簿，偵測到 bitmap 圖片時自動：

1. 存成 PNG 到 `%TEMP%\claude-screenshots\`（檔名含毫秒時間戳）
2. 將剪貼簿內容替換為該檔案的絕對路徑

在 Claude Code 中按 Ctrl+V 即會貼上圖片路徑，Claude 自動讀取並分析圖片內容。剪貼簿為純文字時不做任何處理，Ctrl+V 行為完全不受影響。

### 安裝

雙擊 `clipboard-image-watcher\install.bat`。

安裝會自動完成以下操作：

- 建立截圖暫存目錄 `%TEMP%\claude-screenshots\`
- 在 `~/.claude/settings.json` 中新增 SessionStart hook（Claude Code 啟動時自動執行監視器）
- 立即啟動監視器

安裝過程以 JSON 合併方式寫入設定，不會覆蓋既有的 settings.json 內容。

### 使用方式

不需要改變任何操作習慣：

| 操作 | 結果 |
|------|------|
| 截圖（Win+Shift+S / PrtSc）後 Ctrl+V | 貼上 PNG 檔案路徑，Claude 自動讀取圖片 |
| 複製文字後 Ctrl+V | 正常貼上文字，不受影響 |

### 手動啟動與停止

- 啟動：`clipboard-image-watcher\start-watcher.bat`
- 停止：`clipboard-image-watcher\stop-watcher.bat`

### 卸載

雙擊 `clipboard-image-watcher\uninstall.bat`，會停止監視器、移除 SessionStart hook，並可選擇是否清理截圖暫存目錄。

### 技術細節

- 使用 `powershell.exe`（5.1，STA 模式），不支援 `pwsh.exe`（7+，MTA 模式）
- 透過 `System.Windows.Forms.Clipboard` API 存取剪貼簿，覆蓋 CF_BITMAP、CF_DIB、CF_DIBV5 等格式
- 以 named mutex（`Global\ClaudeClipboardWatcher`）確保單一實例
- 以圖片尺寸加部分像素 hash 做去重，避免同一張圖重複存檔
- 以 sentinel 檔案（`.stop`）實現優雅停止，搭配程序強制結束作為備援
- 錯誤記錄於 `%TEMP%\claude-screenshots\watcher.log`

### 已知限制

- 截圖存檔後剪貼簿內容變為路徑文字，無法再將該圖片貼到其他應用程式（如 LINE、Word），需重新截圖
- 僅處理剪貼簿中的 bitmap 圖片資料，不處理從檔案總管複製的圖片檔案
- 截圖暫存目錄不主動清理，依賴系統重啟或磁碟清理工具處理 `%TEMP%`

### 系統需求

- Windows 10 / 11
- PowerShell 5.1（Windows 內建）
- Claude Code CLI

---

## License

MIT
