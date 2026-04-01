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
