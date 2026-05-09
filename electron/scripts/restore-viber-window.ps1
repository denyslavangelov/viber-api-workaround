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

$procs = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match "(?i)viber" })
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
    [void][ViberUi]::SetForegroundWindow($hwnd)
    exit 0
  }
}

foreach ($p in $procs) {
  if ($p.MainWindowHandle -ne [IntPtr]::Zero) {
    [void][ViberUi]::ShowWindow($p.MainWindowHandle, 9)
    [void][ViberUi]::SetForegroundWindow($p.MainWindowHandle)
    exit 0
  }
}

exit 1
