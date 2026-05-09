# Force Viber UI out of tray-only state by restoring all top-level HWNDs owned by Viber.
# Exit 0 if a reasonably large visible window exists after restore; otherwise 1.
$ErrorActionPreference = "Stop"

Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public struct WinRect {
  public int Left;
  public int Top;
  public int Right;
  public int Bottom;
}

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

public static class ViberUi {
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

  [DllImport("user32.dll")]
  public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

  [DllImport("user32.dll")]
  public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);

  [DllImport("user32.dll")]
  public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

  [DllImport("user32.dll")]
  public static extern bool SetForegroundWindow(IntPtr hWnd);

  [DllImport("user32.dll")]
  public static extern bool IsWindowVisible(IntPtr hWnd);

  [DllImport("user32.dll")]
  public static extern bool GetWindowRect(IntPtr hWnd, out WinRect rc);

  public static List<IntPtr> AllHwnds(uint[] pids) {
    var want = new HashSet<uint>(pids);
    var list = new List<IntPtr>();
    EnumWindows((hwnd, _) => {
      uint pid;
      GetWindowThreadProcessId(hwnd, out pid);
      if (want.Contains(pid) && hwnd != IntPtr.Zero) {
        list.Add(hwnd);
      }
      return true;
    }, IntPtr.Zero);
    return list;
  }
}
"@

# Only Rakuten Viber (Viber.exe). Ignore Electron helper ("Viber Desktop Sender").
$procs = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -eq "Viber" })
if ($procs.Count -eq 0) {
  exit 1
}

$pids = [uint[]]($procs | ForEach-Object { [uint]$_.Id })
$hwnds = [ViberUi]::AllHwnds($pids)

foreach ($hwnd in $hwnds) {
  [void][ViberUi]::ShowWindow($hwnd, 9)
  [void][ViberUi]::ShowWindow($hwnd, 5)
}

Start-Sleep -Milliseconds 500

foreach ($hwnd in $hwnds) {
  $rc = New-Object WinRect
  if (-not [ViberUi]::GetWindowRect($hwnd, [ref]$rc)) {
    continue
  }
  $w = $rc.Right - $rc.Left
  $h = $rc.Bottom - $rc.Top
  if ($w -ge 200 -and $h -ge 200 -and [ViberUi]::IsWindowVisible($hwnd)) {
    [WindowStealer]::ForceToForeground($hwnd)
    exit 0
  }
}

foreach ($p in $procs) {
  if ($p.MainWindowHandle -ne [IntPtr]::Zero) {
    [void][ViberUi]::ShowWindow($p.MainWindowHandle, 9)
    [WindowStealer]::ForceToForeground($p.MainWindowHandle)
    exit 0
  }
}

exit 1
