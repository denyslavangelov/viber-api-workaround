"""
Minimal send-only automation aligned with denyslavangelov/viber-checker agent.py:
- Windows: os.startfile(viber://chat?number=<digits>)
- pywinauto: find window by title, restore/focus, UIA Edit + Send, keyboard fallback
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time

# VIBER_EXE / path: checker uses VIBER_EXE; this repo also accepts VIBER_EXE_PATH
VIBER_EXE = (
    os.environ.get("VIBER_EXE", "").strip()
    or os.environ.get("VIBER_EXE_PATH", "").strip()
    or os.path.expandvars(r"%LOCALAPPDATA%\Viber\Viber.exe")
)

INITIAL_WAIT = float(os.environ.get("INITIAL_WAIT", "0.25"))
WINDOW_WAIT_TIMEOUT = float(os.environ.get("WINDOW_WAIT_TIMEOUT", "14"))
WINDOW_POLL_INTERVAL = float(os.environ.get("WINDOW_POLL_INTERVAL", "0.10"))
CONNECT_TIMEOUT = float(os.environ.get("CONNECT_TIMEOUT", "0.25"))
RETRY_EXTRA_WAIT = float(os.environ.get("RETRY_EXTRA_WAIT", "1.0"))
MESSAGE_INPUT_WAIT = float(os.environ.get("MESSAGE_INPUT_WAIT", "2.0"))

try:
    from pywinauto import Application
    from pywinauto import findwindows
    from pywinauto.keyboard import send_keys as _keyboard_send_keys

    HAS_PYWINAUTO = True
except ImportError:
    HAS_PYWINAUTO = False
    findwindows = None  # type: ignore
    _keyboard_send_keys = None


def force_foreground_win32(hwnd: int) -> None:
    """Raise Viber above other windows: AttachThreadInput + brief TOPMOST + BringWindowToTop."""
    if sys.platform != "win32" or not hwnd:
        return
    import ctypes
    from ctypes import wintypes

    user32 = ctypes.windll.user32
    kernel32 = ctypes.windll.kernel32
    SW_RESTORE = 9
    SW_SHOW = 5
    SWP_NOMOVE = 0x0002
    SWP_NOSIZE = 0x0001
    SWP_SHOWWINDOW = 0x0040

    h = wintypes.HWND(hwnd)
    fg = user32.GetForegroundWindow()
    cur_tid = kernel32.GetCurrentThreadId()
    pid_dummy = wintypes.DWORD()
    target_tid = user32.GetWindowThreadProcessId(h, ctypes.byref(pid_dummy))

    fg_tid_val = 0
    if fg:
        pd = wintypes.DWORD()
        fg_tid_val = user32.GetWindowThreadProcessId(fg, ctypes.byref(pd))

    if fg and fg_tid_val and fg_tid_val != target_tid:
        user32.AttachThreadInput(fg_tid_val, cur_tid, True)
    if target_tid and target_tid != cur_tid:
        user32.AttachThreadInput(cur_tid, target_tid, True)

    user32.ShowWindow(h, SW_RESTORE)
    user32.ShowWindow(h, SW_SHOW)
    user32.SetWindowPos(h, wintypes.HWND(-1), 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW)
    user32.SetWindowPos(h, wintypes.HWND(-2), 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW)
    user32.BringWindowToTop(h)
    user32.SetForegroundWindow(h)

    if target_tid and target_tid != cur_tid:
        user32.AttachThreadInput(cur_tid, target_tid, False)
    if fg and fg_tid_val and fg_tid_val != target_tid:
        user32.AttachThreadInput(fg_tid_val, cur_tid, False)


def _force_dlg_foreground(dlg) -> None:
    hwnd = getattr(dlg, "handle", None) or getattr(dlg, "handle_id", None)
    if hwnd:
        force_foreground_win32(int(hwnd))


def _window_title_hwnd(hwnd: int) -> str:
    import ctypes

    buf = ctypes.create_unicode_buffer(512)
    ctypes.windll.user32.GetWindowTextW(int(hwnd), buf, 512)
    return buf.value or ""


def _pick_viber_win32_handle(handles: list) -> int | None:
    """find_windows('.*Viber.*') also matches our Electron UI ('Viber Desktop Sender'). Skip it."""
    for h in handles:
        try:
            if "Desktop Sender" in _window_title_hwnd(int(h)):
                continue
        except Exception:
            pass
        return int(h)
    return None


def _dlg_is_rakuten_viber(dlg) -> bool:
    try:
        return "Desktop Sender" not in (dlg.window_text() or "")
    except Exception:
        return True


def _digits_only(phone_number: str) -> str:
    return "".join(c for c in phone_number if c.isdigit())


def open_viber_chat(phone_number: str) -> str | None:
    """Open viber://chat?number=<digits> via os.startfile on Windows (matches viber-checker)."""
    digits = _digits_only(phone_number)
    if not digits:
        return "No valid phone number provided"
    url = f"viber://chat?number={digits}"
    try:
        if sys.platform == "win32":
            os.startfile(url)
        else:
            import webbrowser

            webbrowser.open(url)
        return None
    except Exception as e:
        return str(e)


def connect_to_viber_window():
    """Wait for Viber window; win32 title match first, then UIA (same strategy as viber-checker)."""
    if not HAS_PYWINAUTO or not os.path.isfile(VIBER_EXE):
        return None, None, "pywinauto not installed or Viber executable not found at " + VIBER_EXE

    deadline = time.monotonic() + WINDOW_WAIT_TIMEOUT
    while time.monotonic() < deadline:
        try:
            if findwindows is not None:
                handles = findwindows.find_windows(title_re=".*Viber.*")
                hwnd = _pick_viber_win32_handle(handles)
                if hwnd is not None:
                    app = Application(backend="win32").connect(handle=hwnd)
                    dlg = app.window(handle=hwnd)
                    try:
                        dlg.restore()
                        dlg.set_focus()
                    except Exception:
                        pass
                    _force_dlg_foreground(dlg)
                    time.sleep(0.12)
                    rect = dlg.rectangle()
                    left = int(rect.left)
                    top = int(rect.top)
                    width = int(rect.right - rect.left)
                    height = int(rect.bottom - rect.top)
                    if width > 0 and height > 0:
                        rect_dict = {"left": left, "top": top, "width": width, "height": height}
                        return app, rect_dict, None

            app = None
            dlg = None
            try:
                app = Application(backend="uia").connect(path=VIBER_EXE, timeout=CONNECT_TIMEOUT)
                dlg = app.top_window()
            except Exception:
                pass
            if dlg is None or not _dlg_is_rakuten_viber(dlg):
                try:
                    app = Application(backend="uia").connect(title_re=".*Viber.*", timeout=CONNECT_TIMEOUT)
                    dlg = app.top_window()
                except Exception:
                    dlg = None
            if dlg is None or not _dlg_is_rakuten_viber(dlg):
                time.sleep(WINDOW_POLL_INTERVAL)
                continue
            try:
                dlg.restore()
                dlg.set_focus()
            except Exception:
                pass
            _force_dlg_foreground(dlg)
            time.sleep(0.12)
            rect = dlg.rectangle()
            left = int(rect.left)
            top = int(rect.top)
            width = int(rect.right - rect.left)
            height = int(rect.bottom - rect.top)
            if width <= 0 or height <= 0:
                time.sleep(WINDOW_POLL_INTERVAL)
                continue
            rect_dict = {"left": left, "top": top, "width": width, "height": height}
            return app, rect_dict, None
        except Exception:
            time.sleep(WINDOW_POLL_INTERVAL)

    return None, None, f"Viber window did not appear within {WINDOW_WAIT_TIMEOUT}s"


def _auto_id(ctrl) -> str:
    try:
        return getattr(getattr(ctrl, "element_info", None), "automation_id", None) or ""
    except Exception:
        return ""


def _send_message_via_uia(hwnd: int, message: str) -> str | None:
    """UIA: QQuickTextEdit Edit + SendToolbarButton (from viber-checker)."""
    try:
        force_foreground_win32(hwnd)
        time.sleep(1.5)
        app_uia = Application(backend="uia").connect(handle=hwnd)
        dlg = app_uia.window(handle=hwnd)

        edit = None
        for c in dlg.descendants(control_type="Edit"):
            if "QQuickTextEdit" in _auto_id(c):
                edit = c
                break
        if edit is None:
            edits = dlg.descendants(control_type="Edit")
            if not edits:
                return "No Edit control found"
            edit = edits[-1]
        edit.set_focus()
        edit.set_edit_text(message)
        time.sleep(0.2)

        send_btn = None
        for b in dlg.descendants(control_type="Button"):
            if "SendToolbarButton" in _auto_id(b):
                send_btn = b
                break
        if send_btn is None:
            for b in dlg.descendants(control_type="Button"):
                try:
                    if (b.window_text() or "").strip() in (
                        "Send",
                        "Изпрати",
                        "Senden",
                        "Envoyer",
                        "Enviar",
                    ):
                        send_btn = b
                        break
                except Exception:
                    continue
        if send_btn is None:
            return "Send button not found"
        try:
            send_btn.invoke()
        except Exception:
            try:
                send_btn.click()
            except Exception as click_err:
                return "Send button invoke/click failed: %s" % click_err
        return None
    except Exception as e:
        return str(e)


def do_viber_send_message(phone_number: str, message: str) -> str | None:
    """Returns None on success, else error string."""
    if not HAS_PYWINAUTO:
        return "pywinauto not installed (pip install -r electron/scripts/requirements-viber-agent.txt)"
    if not message or not message.strip():
        return "Message is empty"
    msg = message.strip()

    err = open_viber_chat(phone_number)
    if err:
        return err

    time.sleep(INITIAL_WAIT)
    viber_app, _, err = connect_to_viber_window()
    if err or viber_app is None:
        return err or "Could not find Viber window"

    dlg = viber_app.top_window()
    try:
        dlg.restore()
        dlg.set_focus()
    except Exception:
        pass
    _force_dlg_foreground(dlg)
    time.sleep(MESSAGE_INPUT_WAIT)

    hwnd = getattr(dlg, "handle", None) or getattr(dlg, "handle_id", None)
    if hwnd:
        force_foreground_win32(int(hwnd))
    sent = False
    uia_error = None

    if hwnd:
        err_uia = _send_message_via_uia(hwnd, msg)
        if err_uia is None:
            sent = True
        else:
            uia_error = err_uia

    if not sent and _keyboard_send_keys is not None:
        if hwnd:
            force_foreground_win32(int(hwnd))
            time.sleep(0.2)
        safe = msg.replace("{", "{{").replace("}", "}}")
        for attempt in range(2):
            try:
                _keyboard_send_keys(safe + "{ENTER}", with_spaces=True)
                sent = True
                break
            except Exception as e:
                err_msg = str(e).strip()
                if "inserted only 0" in err_msg.lower() or "0 out of" in err_msg:
                    err_msg = (
                        "UIA failed (%s). Keyboard fallback failed (foreground/RDP). "
                        "Keep session unlocked or fix UIA tree."
                    ) % (uia_error or "unknown")
                if attempt == 0 and hwnd:
                    force_foreground_win32(int(hwnd))
                    time.sleep(0.5)
                    continue
                return "Failed to type/send: %s" % err_msg
    elif not sent:
        return "Could not send via UIA and keyboard not available"

    if os.environ.get("VIBER_AGENT_CLOSE_AFTER_SEND", "").strip().lower() in ("1", "true", "yes"):
        time.sleep(0.5)
        try:
            dlg = viber_app.top_window()
            dlg.close()
        except Exception:
            pass

    return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--probe", action="store_true", help="Exit 0 if pywinauto imports")
    parser.add_argument("--phone", help="Phone number (any format; digits used in viber://)")
    parser.add_argument("--message", help="Message text")
    args = parser.parse_args()

    if args.probe:
        if not HAS_PYWINAUTO:
            print(json.dumps({"ok": False, "error": "pywinauto not installed"}))
            return 1
        print(json.dumps({"ok": True, "viber_exe": VIBER_EXE, "viber_exe_exists": os.path.isfile(VIBER_EXE)}))
        return 0

    if not args.phone or args.message is None:
        print(json.dumps({"ok": False, "error": "Missing --phone or --message"}))
        return 2

    err = do_viber_send_message(args.phone, args.message)
    if err:
        print(json.dumps({"ok": False, "error": err}))
        return 3

    print(json.dumps({"ok": True, "detail": "sent via pywinauto (viber-checker style)"}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
