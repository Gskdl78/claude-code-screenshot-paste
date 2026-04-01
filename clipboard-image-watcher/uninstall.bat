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
