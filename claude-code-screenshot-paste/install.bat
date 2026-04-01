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
    "$utf8NoBom = New-Object System.Text.UTF8Encoding($false); " ^
    "[System.IO.File]::WriteAllText($settingsPath, ($json | ConvertTo-Json -Depth 10), $utf8NoBom)"

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
