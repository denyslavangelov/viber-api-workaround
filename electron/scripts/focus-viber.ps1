param(
  [int]$InputOffsetBottom = 70,
  [int]$InputXPercent = 50
)

$ErrorActionPreference = "Stop"

$restoreScript = Join-Path $PSScriptRoot "restore-viber-window.ps1"
if (Test-Path $restoreScript) {
  try {
    & $restoreScript | Out-Null
  } catch {
    # Tray-only / no HWND yet; continue — send-viber may still fail clearly.
  }
  Start-Sleep -Milliseconds 350
}

Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class NativeMethods {
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
  }

  [DllImport("user32.dll")]
  public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

  [DllImport("user32.dll")]
  public static extern bool SetCursorPos(int X, int Y);

  [DllImport("user32.dll")]
  public static extern bool SetForegroundWindow(IntPtr hWnd);

  [DllImport("user32.dll")]
  public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);

  [DllImport("user32.dll")]
  public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
}
"@

$process = Get-Process | Where-Object { $_.ProcessName -match "(?i)viber" -and $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $process) {
  throw "Viber process with visible window not found."
}

[NativeMethods]::ShowWindowAsync($process.MainWindowHandle, 9) | Out-Null
$focused = [NativeMethods]::SetForegroundWindow($process.MainWindowHandle)

if (-not $focused) {
  $wshell = New-Object -ComObject WScript.Shell
  [void]$wshell.AppActivate($process.Id)
}

Start-Sleep -Milliseconds 250

$rect = New-Object NativeMethods+RECT
$ok = [NativeMethods]::GetWindowRect($process.MainWindowHandle, [ref]$rect)
if (-not $ok) {
  throw "Could not read Viber window bounds."
}

$width = $rect.Right - $rect.Left
$x = [int]($rect.Left + ($width * ($InputXPercent / 100.0)))
$y = [int]($rect.Bottom - $InputOffsetBottom)
[NativeMethods]::SetCursorPos($x, $y) | Out-Null

$MOUSEEVENTF_LEFTDOWN = 0x0002
$MOUSEEVENTF_LEFTUP = 0x0004
[NativeMethods]::mouse_event($MOUSEEVENTF_LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 30
[NativeMethods]::mouse_event($MOUSEEVENTF_LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 60
[NativeMethods]::mouse_event($MOUSEEVENTF_LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 30
[NativeMethods]::mouse_event($MOUSEEVENTF_LEFTUP, 0, 0, 0, [UIntPtr]::Zero)

Start-Sleep -Milliseconds 120
