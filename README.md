# Claude Code Screenshot Paste (Windows)

> 讓 Claude Code CLI 支援 Ctrl+V 直接貼上截圖，同時不影響其他應用程式的正常貼圖功能。

## 為什麼需要這個工具？

Claude Code 是一款強大的 CLI 工具，但在 Windows 上截圖貼上一直是個痛點：

- **原生功能不穩定**：`Alt+V` / `chat:imagePaste` 在 Windows 上長期存在相容性問題，Snipping Tool 的 BMP 格式常無法偵測，不同版本之間反覆 regression
- **工作流程中斷**：每次要分享截圖給 Claude 都需要手動存檔、輸入路徑，嚴重影響效率
- **與其他 app 衝突**：過去的解決方案會把剪貼簿中的圖片替換成檔案路徑，導致在 LINE、Word 等應用程式中無法正常貼圖

本工具完美解決了以上所有問題。

## 功能特色

- **零操作成本**：截圖後直接 Ctrl+V，不需要改變任何操作習慣
- **智慧切換**：自動偵測前景視窗，在 Claude Code 中貼上路徑、在其他 app 中貼上原始圖片
- **自動啟動**：透過 Claude Code 的 SessionStart hook，每次開啟 Claude Code 時自動在背景執行
- **自動清理**：超過 7 天的舊截圖自動清除，不佔用磁碟空間

## 運作原理

背景 PowerShell 腳本每 500ms 輪詢剪貼簿，偵測到 bitmap 圖片時自動：

1. 存成 PNG 到 `%TEMP%\claude-screenshots\`（檔名含毫秒時間戳）
2. 備份原始圖片到記憶體
3. **根據前景視窗自動切換剪貼簿內容**：
   - Claude Code 在前景 → 剪貼簿替換為檔案路徑
   - 其他應用程式在前景 → 剪貼簿還原為原始圖片

在 Claude Code 中按 Ctrl+V 即會貼上圖片路徑，Claude 自動讀取並分析圖片內容。切到其他應用程式（LINE、Word 等）時 Ctrl+V 正常貼上圖片。

## 安裝

雙擊 `claude-code-screenshot-paste/install.bat`。

安裝會自動完成以下操作：

- 建立截圖暫存目錄 `%TEMP%\claude-screenshots/`
- 在 `~/.claude/settings.json` 中新增 SessionStart hook（Claude Code 啟動時自動執行監視器）
- 立即啟動監視器

安裝過程以 JSON 合併方式寫入設定，不會覆蓋既有的 settings.json 內容。

## 使用方式

不需要改變任何操作習慣：

| 操作 | 結果 |
|------|------|
| 截圖後在 Claude Code 中 Ctrl+V | 貼上 PNG 檔案路徑，Claude 自動讀取圖片 |
| 截圖後在其他 app（LINE、Word 等）Ctrl+V | 正常貼上圖片 |
| 複製文字後 Ctrl+V | 正常貼上文字，不受影響 |

## 手動啟動與停止

- 啟動：`claude-code-screenshot-paste/start-watcher.bat`
- 停止：`claude-code-screenshot-paste/stop-watcher.bat`

## 截圖暫存清理

超過 7 天的舊截圖會在監視器啟動時自動清理。也可以雙擊 `claude-code-screenshot-paste/cleanup.bat` 手動清理，會顯示清理數量和釋放空間。

## 卸載

雙擊 `claude-code-screenshot-paste/uninstall.bat`，會停止監視器、移除 SessionStart hook，並可選擇是否清理截圖暫存目錄。

## 技術細節

- 使用 `powershell.exe`（5.1，STA 模式），不支援 `pwsh.exe`（7+，MTA 模式）
- 透過 `System.Windows.Forms.Clipboard` API 存取剪貼簿，覆蓋 CF_BITMAP、CF_DIB、CF_DIBV5 等格式
- 以 named mutex（`Global\ClaudeClipboardWatcher`）確保單一實例
- 以圖片尺寸加部分像素 hash 做去重，避免同一張圖重複存檔
- 以 sentinel 檔案（`.stop`）實現優雅停止，搭配程序強制結束作為備援
- 透過 Win32 API `GetForegroundWindow` + `GetWindowText` 偵測前景視窗
- 以 Claude Code 的 Braille spinner 字元（`⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏⠐⠂`）和視窗標題中的 "claude" 關鍵字判斷是否為 Claude Code 視窗
- 原始圖片備份在記憶體中，切換視窗時即時還原或替換剪貼簿，延遲 < 500ms
- 錯誤記錄於 `%TEMP%\claude-screenshots\watcher.log`

## 已知限制

- 僅處理剪貼簿中的 bitmap 圖片資料，不處理從檔案總管複製的圖片檔案
- 截圖暫存保留最近 7 天，更早的會在監視器啟動時自動清理
- 前景視窗偵測依賴視窗標題中的 Claude Code spinner 符號或 "claude" 關鍵字

## 系統需求

- Windows 10 / 11
- PowerShell 5.1（Windows 內建）
- Claude Code CLI

## License

MIT
