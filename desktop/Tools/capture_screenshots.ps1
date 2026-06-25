# Haven (Windows) — Microsoft Store screenshots.
#
# The Tauri/WebView2 GUI only runs on Windows, so these MUST be captured on a Windows VM or a CI
# Windows runner — NOT on macOS. This script launches the installed app, waits, and captures the
# Haven window to PNGs sized for the Store (min 1366x768).
#
# PII-free content: point the app at the style gallery (ui/_preview.html) — it mirrors the real app
# markup with synthetic demo data and needs no identity/network. Either open _preview.html in the
# running WebView, or build a dev bundle whose window loads _preview.html.
#
# Usage (on Windows):  pwsh desktop\Tools\capture_screenshots.ps1 -Exe "C:\Path\to\Haven.exe" -Out .\out
param(
  [string]$Exe = "Haven.exe",
  [string]$Out = "$PSScriptRoot\..\screenshots\windows",
  [int]$Width = 1366,
  [int]$Height = 768
)

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
New-Item -ItemType Directory -Force -Path $Out | Out-Null

$proc = Start-Process -FilePath $Exe -PassThru
Start-Sleep -Seconds 6   # let the WebView2 content render

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int hh, bool repaint);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
"@

$h = $proc.MainWindowHandle
[Win]::MoveWindow($h, 0, 0, $Width, $Height, $true) | Out-Null
[Win]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 800

$r = New-Object Win+RECT
[Win]::GetWindowRect($h, [ref]$r) | Out-Null
$bmp = New-Object System.Drawing.Bitmap (($r.Right - $r.Left), ($r.Bottom - $r.Top))
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.Left, $r.Top, 0, 0, $bmp.Size)
$path = Join-Path $Out "01-feed.png"
$bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host "saved $path"

# Navigate to additional views (Stories / Messages / Connect / You) and re-capture by repeating the
# capture block after clicking each nav item, or drive the WebView to load each demo scene.
$proc.CloseMainWindow() | Out-Null
