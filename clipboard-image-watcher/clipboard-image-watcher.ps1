# clipboard-image-watcher.ps1
# 剪貼簿圖片監視器 - 偵測剪貼簿圖片並自動存成 PNG，將路徑寫回剪貼簿

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# 檢查 STA 模式（powershell.exe 5.1 預設 STA，pwsh.exe 7+ 預設 MTA 會失敗）
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    Write-Host "錯誤：此腳本必須在 STA 模式下執行（使用 powershell.exe，不要用 pwsh.exe）" -ForegroundColor Red
    exit 1
}

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

# 單一實例檢查
$mutexName = "Global\ClaudeClipboardWatcher"
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
try {
    if (-not $mutex.WaitOne(0)) {
        Write-Log "另一個實例已在執行，退出"
        $mutex.Dispose()
        exit 0
    }
} catch [System.Threading.AbandonedMutexException] {
    # 上一個實例異常退出，我們接手 mutex
}

Write-Log "剪貼簿監視器啟動"

# 啟動時清理超過 7 天的舊截圖
try {
    $cutoff = (Get-Date).AddDays(-7)
    Get-ChildItem -Path $screenshotDir -Filter "clipboard_*.png" -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        ForEach-Object {
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        }
    # 清理超過 1MB 的 log 檔
    if ((Test-Path $logFile) -and (Get-Item $logFile -ErrorAction SilentlyContinue).Length -gt 1MB) {
        Remove-Item $logFile -Force -ErrorAction SilentlyContinue
    }
} catch {
    Write-Log "清理舊截圖失敗: $_"
}

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

# 清除舊的 stop sentinel
if (Test-Path $stopFile) { Remove-Item $stopFile -Force -ErrorAction SilentlyContinue }

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
                    try {
                        $sig = Get-ImageSignature -Image $image
                        if ($sig -ne "" -and $sig -ne $lastSignature) {
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
                    } finally {
                        $image.Dispose()
                    }
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
