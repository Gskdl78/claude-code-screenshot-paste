@echo off
chcp 65001 >nul
REM 清理超過 7 天的舊截圖

set "SCREENSHOT_DIR=%TEMP%\claude-screenshots"

echo ======================================
echo  截圖暫存清理
echo ======================================
echo.

if not exist "%SCREENSHOT_DIR%" (
    echo 截圖目錄不存在，無需清理
    pause
    exit /b 0
)

REM 統計清理前的檔案數量和大小
powershell.exe -ExecutionPolicy Bypass -Command ^
    "$dir = '%SCREENSHOT_DIR%'; " ^
    "$cutoff = (Get-Date).AddDays(-7); " ^
    "$all = Get-ChildItem -Path $dir -Filter 'clipboard_*.png' -ErrorAction SilentlyContinue; " ^
    "$old = $all | Where-Object { $_.LastWriteTime -lt $cutoff }; " ^
    "$totalCount = @($all).Count; " ^
    "$oldCount = @($old).Count; " ^
    "$oldSize = ($old | Measure-Object -Property Length -Sum).Sum; " ^
    "if ($oldSize -eq $null) { $oldSize = 0 }; " ^
    "$sizeMB = [math]::Round($oldSize / 1MB, 2); " ^
    "Write-Host \"截圖總數: $totalCount\"; " ^
    "Write-Host \"超過 7 天: $oldCount ($sizeMB MB)\"; " ^
    "if ($oldCount -gt 0) { " ^
    "    $old | ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }; " ^
    "    Write-Host ''; " ^
    "    Write-Host \"[OK] 已清理 $oldCount 個舊截圖\"; " ^
    "} else { " ^
    "    Write-Host ''; " ^
    "    Write-Host '[OK] 沒有需要清理的舊截圖'; " ^
    "}; " ^
    "$logFile = Join-Path $dir 'watcher.log'; " ^
    "if ((Test-Path $logFile) -and (Get-Item $logFile -ErrorAction SilentlyContinue).Length -gt 1MB) { " ^
    "    Remove-Item $logFile -Force -ErrorAction SilentlyContinue; " ^
    "    Write-Host '[OK] 已清理過大的 log 檔'; " ^
    "}"

echo.
echo ======================================
pause
