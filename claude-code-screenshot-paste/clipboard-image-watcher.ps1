# clipboard-image-watcher.ps1
# 剪貼簿圖片監視器 - 偵測剪貼簿圖片並自動存成 PNG，將路徑寫回剪貼簿

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Win32 API：取得前景視窗 + 對應 process id
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class ForegroundHelper {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int count);
    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    public static string GetTitle() {
        var sb = new StringBuilder(512);
        GetWindowText(GetForegroundWindow(), sb, 512);
        return sb.ToString();
    }
    public static uint GetForegroundPid() {
        uint pid = 0;
        GetWindowThreadProcessId(GetForegroundWindow(), out pid);
        return pid;
    }
}
"@

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

# 前景視窗判斷：掃描前景 process 的行程樹，若後代含 claude.exe 或 command line 含 claude-code 即判定為 Claude Code。
# 2 秒快取避免每 500ms 都打 WMI。
# 這個作法不依賴視窗標題字串（CLI 升級常會改標題格式），是目前最穩定的偵測方式。
$script:fgCacheHwnd = [IntPtr]::Zero
$script:fgCacheResult = $false
$script:fgCacheTime = [DateTime]::MinValue

function Test-ProcessTreeContainsClaude {
    param([int]$RootPid)
    try {
        $all = Get-CimInstance -ClassName Win32_Process -ErrorAction Stop
        $children = @{}
        $byId = @{}
        foreach ($p in $all) {
            $byId[[int]$p.ProcessId] = $p
            $parentPid = [int]$p.ParentProcessId
            if (-not $children.ContainsKey($parentPid)) {
                $children[$parentPid] = [System.Collections.Generic.List[object]]::new()
            }
            $children[$parentPid].Add($p)
        }

        $queue = [System.Collections.Queue]::new()
        $queue.Enqueue($RootPid)
        $visited = @{}
        while ($queue.Count -gt 0) {
            $curPid = [int]$queue.Dequeue()
            if ($visited.ContainsKey($curPid)) { continue }
            $visited[$curPid] = $true

            $proc = $byId[$curPid]
            if ($proc) {
                if ($proc.Name -ieq 'claude.exe') { return $true }
                $cmd = $proc.CommandLine
                if ($cmd) {
                    # node.exe 執行 claude-code 的 cli.js，或以 claude.cmd/claude.ps1 包裝器啟動
                    if ($cmd -match '(?i)claude-code') { return $true }
                    if ($cmd -match '(?i)[\\/"]claude\.(exe|cmd|ps1)') { return $true }
                }
            }
            if ($children.ContainsKey($curPid)) {
                foreach ($c in $children[$curPid]) {
                    $queue.Enqueue([int]$c.ProcessId)
                }
            }
        }
        return $false
    } catch {
        Write-Log "Test-ProcessTreeContainsClaude 失敗: $_"
        return $false
    }
}

function Test-ClaudeCodeForeground {
    $hwnd = [ForegroundHelper]::GetForegroundWindow()
    if ($hwnd -eq [IntPtr]::Zero) { return $false }

    $now = Get-Date
    if ($hwnd -eq $script:fgCacheHwnd -and ($now - $script:fgCacheTime).TotalMilliseconds -lt 2000) {
        return $script:fgCacheResult
    }

    $fgPid = [ForegroundHelper]::GetForegroundPid()
    $result = $false
    if ($fgPid -ne 0) {
        $result = Test-ProcessTreeContainsClaude -RootPid ([int]$fgPid)
    }

    $script:fgCacheHwnd = $hwnd
    $script:fgCacheResult = $result
    $script:fgCacheTime = $now
    return $result
}

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

# 自動切換狀態
$script:originalImageBytes = $null   # 備份的原始圖片（PNG bytes）
$script:clipboardReplaced = $false   # 目前剪貼簿是否已被替換成路徑
$script:lastSavedPath = ""           # 最後存檔的路徑

# Claude Code CLI 貼上偵測需要 bracketed paste 事件，或單一 key event 長度 > 800 (cli.js sb8 常數)
# 用空白前綴把總長拉到 > 800，強制觸發 CLI 的「長貼上」fallback
# CLI 的 split 會把路徑分離，空白 token 被 .trim() 過濾掉，不會污染輸入框
$clipboardPadding = ' ' * 900

function Set-ClipboardPathPadded {
    param([string]$Path)
    [System.Windows.Forms.Clipboard]::SetText($clipboardPadding + $Path)
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
            $isClaudeCode = Test-ClaudeCodeForeground

            if ([System.Windows.Forms.Clipboard]::ContainsImage()) {
                $image = [System.Windows.Forms.Clipboard]::GetImage()
                if ($null -ne $image) {
                    try {
                        $sig = Get-ImageSignature -Image $image
                        if ($sig -ne "" -and $sig -ne $lastSignature) {
                            # 偵測到新截圖 → 存檔 + 備份原圖
                            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
                            $filename = "clipboard_${timestamp}.png"
                            $filepath = Join-Path $screenshotDir $filename
                            try {
                                $image.Save($filepath, [System.Drawing.Imaging.ImageFormat]::Png)
                                $script:lastSavedPath = $filepath
                                $lastSignature = $sig

                                # 備份原始圖片到記憶體
                                $backupMs = New-Object System.IO.MemoryStream
                                $image.Save($backupMs, [System.Drawing.Imaging.ImageFormat]::Png)
                                $script:originalImageBytes = $backupMs.ToArray()
                                $backupMs.Dispose()

                                Write-Log "新截圖: $filename"

                                if ($isClaudeCode) {
                                    # Claude Code 在前景 → 替換剪貼簿為路徑（加空白前綴觸發 CLI 長貼上偵測）
                                    Set-ClipboardPathPadded -Path $filepath
                                    $script:clipboardReplaced = $true
                                    Write-Log "已替換剪貼簿為路徑（Claude Code 前景）"
                                } else {
                                    $script:clipboardReplaced = $false
                                }
                            } catch {
                                Write-Log "存檔失敗: $_"
                            }
                        } elseif ($sig -eq $lastSignature -and $isClaudeCode -and -not $script:clipboardReplaced -and $script:lastSavedPath) {
                            # 同一張圖，切回 Claude Code → 替換為路徑（同樣加空白前綴）
                            Set-ClipboardPathPadded -Path $script:lastSavedPath
                            $script:clipboardReplaced = $true
                            Write-Log "切回 Claude Code，替換剪貼簿為路徑"
                        }
                    } finally {
                        $image.Dispose()
                    }
                }
            } elseif ($script:clipboardReplaced -and -not $isClaudeCode -and $script:originalImageBytes) {
                # 離開 Claude Code + 剪貼簿目前是路徑 → 還原為原始圖片
                try {
                    $restoreMs = New-Object System.IO.MemoryStream(,$script:originalImageBytes)
                    $restoreImg = [System.Drawing.Image]::FromStream($restoreMs)
                    [System.Windows.Forms.Clipboard]::SetImage($restoreImg)
                    $restoreImg.Dispose()
                    $restoreMs.Dispose()
                    $script:clipboardReplaced = $false
                    Write-Log "離開 Claude Code，還原剪貼簿為圖片"
                } catch {
                    Write-Log "還原圖片失敗: $_"
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
    # 退出前還原剪貼簿
    if ($script:clipboardReplaced -and $script:originalImageBytes) {
        try {
            $restoreMs = New-Object System.IO.MemoryStream(,$script:originalImageBytes)
            $restoreImg = [System.Drawing.Image]::FromStream($restoreMs)
            [System.Windows.Forms.Clipboard]::SetImage($restoreImg)
            $restoreImg.Dispose()
            $restoreMs.Dispose()
        } catch {}
    }
    Write-Log "剪貼簿監視器停止"
    if ($mutex) {
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    }
}
