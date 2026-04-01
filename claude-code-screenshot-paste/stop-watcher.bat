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
