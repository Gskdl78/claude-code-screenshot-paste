# Clipboard Image Watcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a background PowerShell clipboard watcher that auto-saves clipboard images as PNG and replaces the clipboard with the file path, so Ctrl+V in Claude Code pastes the image path.

**Architecture:** A single PowerShell script polls the clipboard every 500ms. When a bitmap image is detected, it saves to `%TEMP%/claude-screenshots/` as PNG and replaces the clipboard with the file path. A SessionStart hook in Claude Code auto-launches the watcher. Batch scripts handle install/uninstall/start/stop.

**Tech Stack:** PowerShell 5.1 (powershell.exe, STA mode), .NET Framework (System.Windows.Forms, System.Drawing), Batch files (.bat)

---

## File Map

| File | Responsibility |
|------|---------------|
| `clipboard-image-watcher/clipboard-image-watcher.ps1` | Core loop: poll clipboard, detect image, save PNG, replace clipboard with path |
| `clipboard-image-watcher/start-watcher.bat` | Launch the PS1 script hidden in background, with mutex-based duplicate prevention |
| `clipboard-image-watcher/stop-watcher.bat` | Signal the watcher to stop via sentinel file, fallback to process kill |
| `clipboard-image-watcher/install.bat` | Create temp dir, merge SessionStart hook into `~/.claude/settings.json`, start watcher |
| `clipboard-image-watcher/uninstall.bat` | Stop watcher, remove hook from settings.json, optional cleanup |

---

### Task 1: Core Watcher Script

**Files:**
- Create: `clipboard-image-watcher/clipboard-image-watcher.ps1`

- [ ] **Step 1: Create the script with .NET assembly loading and screenshot directory setup**

```powershell
# clipboard-image-watcher.ps1
# 剪貼簿圖片監視器 - 偵測剪貼簿圖片並自動存成 PNG，將路徑寫回剪貼簿

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$screenshotDir = Join-Path $env:TEMP "claude-screenshots"
$logFile = Join-Path $screenshotDir "watcher.log"
$stopFile = Join-Path $screenshotDir ".stop"

# 確保截圖目錄存在
if (-not (Test-Path $screenshotDir)) {
    New-Item -ItemType Directory -Path $screenshotDir -Force | Out-Null
}

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logFile -Value "[$timestamp] $Message" -ErrorAction SilentlyContinue
}
```

- [ ] **Step 2: Add mutex-based single instance check**

Append to `clipboard-image-watcher.ps1`:

```powershell
# 單一實例檢查
$mutexName = "Global\ClaudeClipboardWatcher"
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
try {
    if (-not $mutex.WaitOne(0)) {
        Write-Log "另一個實例已在執行，退出"
        exit 0
    }
} catch [System.Threading.AbandonedMutexException] {
    # 上一個實例異常退出，我們接手 mutex
}

Write-Log "剪貼簿監視器啟動"
```

- [ ] **Step 3: Add image signature function for dedup**

Append to `clipboard-image-watcher.ps1`:

```powershell
$lastSignature = ""

function Get-ImageSignature {
    param([System.Drawing.Image]$Image)
    $bmp = $null
    $cropped = $null
    $ms = $null
    $md5 = $null
    try {
        $width = $Image.Width
        $height = $Image.Height
        $bmp = New-Object System.Drawing.Bitmap($Image)
        # 取左上角小區域像素作為快速簽名
        $cropW = [Math]::Min($width, 64)
        $cropH = [Math]::Min($height, 16)
        $rect = New-Object System.Drawing.Rectangle(0, 0, $cropW, $cropH)
        $cropped = $bmp.Clone($rect, $bmp.PixelFormat)
        $ms = New-Object System.IO.MemoryStream
        $cropped.Save($ms, [System.Drawing.Imaging.ImageFormat]::Bmp)
        $bytes = $ms.ToArray()
        $md5 = [System.Security.Cryptography.MD5]::Create()
        $hash = [BitConverter]::ToString($md5.ComputeHash($bytes)).Replace("-", "").Substring(0, 16)
        return "${width}x${height}_${hash}"
    } catch {
        return ""
    } finally {
        if ($md5) { $md5.Dispose() }
        if ($ms) { $ms.Dispose() }
        if ($cropped) { $cropped.Dispose() }
        if ($bmp) { $bmp.Dispose() }
    }
}
```

- [ ] **Step 4: Add the main polling loop**

Append to `clipboard-image-watcher.ps1`:

```powershell
# 清除舊的 stop sentinel
if (Test-Path $stopFile) { Remove-Item $stopFile -Force }

try {
    while ($true) {
        # 檢查停止信號
        if (Test-Path $stopFile) {
            Write-Log "收到停止信號，退出"
            Remove-Item $stopFile -Force -ErrorAction SilentlyContinue
            break
        }

        try {
            if ([System.Windows.Forms.Clipboard]::ContainsImage()) {
                $image = [System.Windows.Forms.Clipboard]::GetImage()
                if ($null -ne $image) {
                    $sig = Get-ImageSignature -Image $image
                    if ($sig -ne "" -and $sig -ne $lastSignature) {
                        # 新圖片 - 存檔
                        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
                        $filename = "clipboard_${timestamp}.png"
                        $filepath = Join-Path $screenshotDir $filename

                        try {
                            $image.Save($filepath, [System.Drawing.Imaging.ImageFormat]::Png)
                            [System.Windows.Forms.Clipboard]::SetText($filepath)
                            $lastSignature = $sig
                        } catch {
                            Write-Log "存檔失敗: $_"
                        }
                    }
                    $image.Dispose()
                }
            }
        } catch [System.Runtime.InteropServices.ExternalException] {
            # 剪貼簿被鎖定，跳過
        } catch {
            Write-Log "輪詢錯誤: $_"
        }

        Start-Sleep -Milliseconds 500
    }
} finally {
    Write-Log "剪貼簿監視器停止"
    if ($mutex) {
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    }
}
```

- [ ] **Step 5: Verify the script runs standalone**

Run in a PowerShell window:
```
powershell.exe -ExecutionPolicy Bypass -File "D:\Users\kevin\Desktop\claude code小工具\clipboard-image-watcher\clipboard-image-watcher.ps1"
```
Then: Win+Shift+S to take a screenshot, wait 1 second, check:
1. A PNG file exists in `%TEMP%\claude-screenshots\`
2. Clipboard now contains the file path (paste into Notepad to verify)

Press Ctrl+C to stop.

- [ ] **Step 6: Commit**

```bash
git add clipboard-image-watcher/clipboard-image-watcher.ps1
git commit -m "feat: add core clipboard image watcher script"
```

---

### Task 2: Start and Stop Scripts

**Files:**
- Create: `clipboard-image-watcher/start-watcher.bat`
- Create: `clipboard-image-watcher/stop-watcher.bat`

- [ ] **Step 1: Create start-watcher.bat**

```bat
@echo off
REM 啟動剪貼簿圖片監視器（背景隱藏執行）
REM 使用 powershell.exe (5.1 STA) 而非 pwsh.exe (7+ MTA)

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%clipboard-image-watcher.ps1"
set "SCREENSHOT_DIR=%TEMP%\claude-screenshots"

REM 確保截圖目錄存在
if not exist "%SCREENSHOT_DIR%" mkdir "%SCREENSHOT_DIR%"

REM 用 PowerShell Start-Process 完全隱藏視窗啟動（避免視窗閃爍）
powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -Command ^
    "Start-Process powershell.exe -ArgumentList '-ExecutionPolicy Bypass -WindowStyle Hidden -File \"%PS_SCRIPT%\"' -WindowStyle Hidden"
```

- [ ] **Step 2: Create stop-watcher.bat**

```bat
@echo off
REM 停止剪貼簿圖片監視器

set "STOP_FILE=%TEMP%\claude-screenshots\.stop"

REM 建立停止信號檔案
echo stop > "%STOP_FILE%"
echo 已發送停止信號

REM 等待 2 秒讓腳本自行退出
timeout /t 2 /nobreak >nul

REM 如果還在執行，用 PowerShell 按 command line 過濾並強制結束
powershell.exe -ExecutionPolicy Bypass -Command ^
    "Get-WmiObject Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object { $_.CommandLine -like '*clipboard-image-watcher*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"
```

- [ ] **Step 3: Verify start and stop**

1. Double-click `start-watcher.bat` → no visible window should appear
2. Take a screenshot (Win+Shift+S) → check `%TEMP%\claude-screenshots\` for a new PNG
3. Double-click `stop-watcher.bat` → watcher process should end
4. Take another screenshot → clipboard should NOT be replaced (watcher is stopped)

- [ ] **Step 4: Commit**

```bash
git add clipboard-image-watcher/start-watcher.bat clipboard-image-watcher/stop-watcher.bat
git commit -m "feat: add start and stop scripts for clipboard watcher"
```

---

### Task 3: Install Script

**Files:**
- Create: `clipboard-image-watcher/install.bat`

- [ ] **Step 1: Create install.bat with settings.json merge logic**

```bat
@echo off
chcp 65001 >nul
REM 一鍵安裝剪貼簿圖片監視器

set "SCRIPT_DIR=%~dp0"
set "SCREENSHOT_DIR=%TEMP%\claude-screenshots"
set "SETTINGS_FILE=%USERPROFILE%\.claude\settings.json"
set "START_SCRIPT=%SCRIPT_DIR%start-watcher.bat"

echo ======================================
echo  剪貼簿圖片監視器 - 安裝
echo ======================================
echo.

REM 1. 建立截圖目錄
if not exist "%SCREENSHOT_DIR%" (
    mkdir "%SCREENSHOT_DIR%"
    echo [OK] 已建立截圖目錄: %SCREENSHOT_DIR%
) else (
    echo [OK] 截圖目錄已存在: %SCREENSHOT_DIR%
)

REM 2. 將 hook 寫入 settings.json（JSON 合併）
echo.
echo 正在設定 Claude Code SessionStart hook...

REM 將反斜線轉為正斜線給 JSON 用
set "START_CMD=%SCRIPT_DIR%start-watcher.bat"
set "START_CMD=%START_CMD:\=/%"

powershell.exe -ExecutionPolicy Bypass -Command ^
    "$settingsPath = '%SETTINGS_FILE%'; " ^
    "$startCmd = '%START_CMD%'; " ^
    "if (Test-Path $settingsPath) { " ^
    "    $json = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json; " ^
    "} else { " ^
    "    $json = [PSCustomObject]@{}; " ^
    "}; " ^
    "$hookCommand = \"cmd /c `\"$startCmd`\"\"; " ^
    "$hookEntry = [PSCustomObject]@{ type = 'command'; command = $hookCommand; timeout = 5; async = $true }; " ^
    "$hookGroup = [PSCustomObject]@{ hooks = @($hookEntry) }; " ^
    "if (-not $json.PSObject.Properties['hooks']) { " ^
    "    $json | Add-Member -NotePropertyName 'hooks' -NotePropertyValue ([PSCustomObject]@{}); " ^
    "}; " ^
    "if (-not $json.hooks.PSObject.Properties['SessionStart']) { " ^
    "    $json.hooks | Add-Member -NotePropertyName 'SessionStart' -NotePropertyValue @(); " ^
    "}; " ^
    "$existing = $json.hooks.SessionStart | Where-Object { $_.hooks | Where-Object { $_.command -like '*clipboard*watcher*' -or $_.command -like '*start-watcher*' } }; " ^
    "if (-not $existing) { " ^
    "    $json.hooks.SessionStart = @($json.hooks.SessionStart) + @($hookGroup); " ^
    "}; " ^
    "$json | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding UTF8"

if %errorlevel% equ 0 (
    echo [OK] 已新增 SessionStart hook
) else (
    echo [FAIL] 設定 hook 失敗，請手動配置
)

REM 3. 立即啟動監視器
echo.
echo 正在啟動監視器...
call "%START_SCRIPT%"
echo [OK] 監視器已啟動

echo.
echo ======================================
echo  安裝完成！
echo  截圖後 Ctrl+V 即可在 Claude Code 貼上圖片路徑
echo ======================================
pause
```

- [ ] **Step 2: Verify install.bat**

1. Double-click `install.bat`
2. Check output shows all [OK]
3. Verify `~/.claude/settings.json` now contains the SessionStart hook (read the file)
4. Verify watcher is running: take a screenshot → check clipboard contains a file path
5. Verify existing settings (plugins, marketplaces, etc.) are preserved in settings.json

- [ ] **Step 3: Commit**

```bash
git add clipboard-image-watcher/install.bat
git commit -m "feat: add one-click install script with settings.json merge"
```

---

### Task 4: Uninstall Script

**Files:**
- Create: `clipboard-image-watcher/uninstall.bat`

- [ ] **Step 1: Create uninstall.bat**

```bat
@echo off
chcp 65001 >nul
REM 一鍵卸載剪貼簿圖片監視器

set "SCRIPT_DIR=%~dp0"
set "SCREENSHOT_DIR=%TEMP%\claude-screenshots"
set "SETTINGS_FILE=%USERPROFILE%\.claude\settings.json"

echo ======================================
echo  剪貼簿圖片監視器 - 卸載
echo ======================================
echo.

REM 1. 停止監視器
echo 正在停止監視器...
call "%SCRIPT_DIR%stop-watcher.bat"
echo [OK] 監視器已停止

REM 2. 從 settings.json 移除 hook
echo.
echo 正在移除 Claude Code SessionStart hook...

powershell.exe -ExecutionPolicy Bypass -Command ^
    "$settingsPath = '%SETTINGS_FILE%'; " ^
    "if (Test-Path $settingsPath) { " ^
    "    $json = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json; " ^
    "    if ($json.PSObject.Properties['hooks'] -and $json.hooks.PSObject.Properties['SessionStart']) { " ^
    "        $filtered = @($json.hooks.SessionStart | Where-Object { " ^
    "            -not ($_.hooks | Where-Object { $_.command -like '*clipboard*watcher*' -or $_.command -like '*start-watcher*' }) " ^
    "        }); " ^
    "        if ($filtered.Count -eq 0) { " ^
    "            $json.hooks.PSObject.Properties.Remove('SessionStart'); " ^
    "        } else { " ^
    "            $json.hooks.SessionStart = $filtered; " ^
    "        }; " ^
    "        $hookProps = @($json.hooks.PSObject.Properties); " ^
    "        if ($hookProps.Count -eq 0) { " ^
    "            $json.PSObject.Properties.Remove('hooks'); " ^
    "        }; " ^
    "        $json | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding UTF8; " ^
    "    }; " ^
    "}"

if %errorlevel% equ 0 (
    echo [OK] 已移除 SessionStart hook
) else (
    echo [FAIL] 移除 hook 失敗，請手動編輯 settings.json
)

REM 3. 詢問是否清理截圖
echo.
set /p "CLEAN=是否清理截圖暫存目錄？(y/N): "
if /i "%CLEAN%"=="y" (
    if exist "%SCREENSHOT_DIR%" (
        rmdir /s /q "%SCREENSHOT_DIR%"
        echo [OK] 已清理 %SCREENSHOT_DIR%
    )
) else (
    echo [OK] 保留截圖暫存目錄
)

echo.
echo ======================================
echo  卸載完成
echo ======================================
pause
```

- [ ] **Step 2: Verify uninstall.bat**

1. Make sure watcher is running first (run install.bat if needed)
2. Double-click `uninstall.bat`, answer 'N' for cleanup
3. Verify `~/.claude/settings.json` no longer has the clipboard watcher hook
4. Verify other settings (plugins etc.) are still intact
5. Take a screenshot → clipboard should NOT be replaced (watcher is stopped)

- [ ] **Step 3: Commit**

```bash
git add clipboard-image-watcher/uninstall.bat
git commit -m "feat: add one-click uninstall script"
```

---

### Task 5: End-to-End Acceptance Testing

**Files:** None (manual testing only)

- [ ] **Step 1: Fresh install test**

1. Run `uninstall.bat` first (clean slate)
2. Run `install.bat`
3. Verify all [OK] in output
4. Read `~/.claude/settings.json` to confirm hook is present

- [ ] **Step 2: Screenshot paste test**

1. Win+Shift+S → take a screenshot of anything
2. Wait 1 second
3. Open Notepad → Ctrl+V → should see a file path like `C:\Users\...\Temp\claude-screenshots\clipboard_20260401_143052_123.png`
4. Open that file path → should be the screenshot you just took

- [ ] **Step 3: Text paste test**

1. Select some text anywhere → Ctrl+C
2. Open Notepad → Ctrl+V → should see the original text, NOT a file path

- [ ] **Step 4: Consecutive screenshots test**

1. Win+Shift+S → screenshot A
2. Wait 1 second
3. Win+Shift+S → screenshot B
4. Check `%TEMP%\claude-screenshots\` → should have 2 different PNG files

- [ ] **Step 5: Duplicate detection test**

1. Take a screenshot → clipboard becomes path
2. Ctrl+V in Notepad → see the path
3. Ctrl+V again → same path (no new file created)

- [ ] **Step 6: Spaces-in-path test**

1. Verify the project path contains spaces (`claude code小工具`)
2. Run `install.bat` from this path
3. Read `~/.claude/settings.json` → confirm the hook command contains the full path with spaces, properly quoted
4. Take a screenshot → should still work correctly

- [ ] **Step 7: Claude Code restart test**

1. Ensure watcher is installed and running
2. Run `stop-watcher.bat` to stop the watcher
3. Start a new Claude Code session → SessionStart hook should auto-launch watcher
4. Take a screenshot → clipboard should contain the PNG file path

- [ ] **Step 8: Clean uninstall test**

1. Run `uninstall.bat` with 'y' for cleanup
2. Verify `~/.claude/settings.json` has no clipboard watcher hook
3. Verify `%TEMP%\claude-screenshots\` is removed
4. Take a screenshot → clipboard should still contain the image (not a path)
