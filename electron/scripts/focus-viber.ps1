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

/** Steal foreground even when another app is on top (AttachThreadInput + topmost flash). */
public static class WindowStealer {
  const int SW_RESTORE = 9;
  const int SW_SHOW = 5;
  static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
  static readonly IntPtr HWND_NOTOPMOST = new IntPtr(-2);
  const uint SWP_NOMOVE = 0x0002;
  const uint SWP_NOSIZE = 0x0001;
  const uint SWP_SHOWWINDOW = 0x0040;

  [DllImport("user32.dll")]
  public static extern IntPtr GetForegroundWindow();

  [DllImport("user32.dll")]
  public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

  [DllImport("kernel32.dll")]
  public static extern uint GetCurrentThreadId();

  [DllImport("user32.dll")]
  public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);

  [DllImport("user32.dll")]
  public static extern bool BringWindowToTop(IntPtr hWnd);

  [DllImport("user32.dll")]
  public static extern bool SetForegroundWindow(IntPtr hWnd);

  [DllImport("user32.dll")]
  public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

  [DllImport("user32.dll")]
  public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

  public static void ForceToForeground(IntPtr hwnd) {
    if (hwnd == IntPtr.Zero) {
      return;
    }
    IntPtr fg = GetForegroundWindow();
    uint pidIgnored;
    uint targetTid = GetWindowThreadProcessId(hwnd, out pidIgnored);
    uint curTid = GetCurrentThreadId();
    uint fgTid = 0;
    if (fg != IntPtr.Zero) {
      fgTid = GetWindowThreadProcessId(fg, out pidIgnored);
    }
    if (fg != IntPtr.Zero && fgTid != 0 && fgTid != targetTid) {
      AttachThreadInput(fgTid, curTid, true);
    }
    if (targetTid != 0 && targetTid != curTid) {
      AttachThreadInput(curTid, targetTid, true);
    }
    ShowWindow(hwnd, SW_RESTORE);
    ShowWindow(hwnd, SW_SHOW);
    SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
    SetWindowPos(hwnd, HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
    BringWindowToTop(hwnd);
    SetForegroundWindow(hwnd);
    if (targetTid != 0 && targetTid != curTid) {
      AttachThreadInput(curTid, targetTid, false);
    }
    if (fg != IntPtr.Zero && fgTid != 0 && fgTid != targetTid) {
      AttachThreadInput(fgTid, curTid, false);
    }
  }
}

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

# Rakuten Viber only — ProcessName is "Viber". Do not match this Electron app ("Viber Desktop Sender", etc.).
$process = Get-Process -ErrorAction SilentlyContinue |
  Where-Object { $_.ProcessName -eq "Viber" -and $_.MainWindowHandle -ne [IntPtr]::Zero } |
  Select-Object -First 1
if (-not $process) {
  throw "Viber desktop (process name Viber.exe) with visible window not found."
}

$h = $process.MainWindowHandle
[NativeMethods]::ShowWindowAsync($h, 9) | Out-Null
[WindowStealer]::ForceToForeground($h)
try {
  $wshell = New-Object -ComObject WScript.Shell
  [void]$wshell.AppActivate($process.Id)
} catch {
  # optional fallback
}

Start-Sleep -Milliseconds 250

$rect = New-Object NativeMethods+RECT
$ok = [NativeMethods]::GetWindowRect($h, [ref]$rect)
if (-not $ok) {
  throw "Could not read Viber window bounds."
}

$width = $rect.Right - $rect.Left
$x = [int]($rect.Left + ($width * ($InputXPercent / 100.0)))
$y = [int]($rect.Bottom - $InputOffsetBottom)
[NativeMethods]::SetCursorPos($x, $y) | Out-Null
[WindowStealer]::ForceToForeground($h) | Out-Null

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
