#!/usr/bin/env bash
set -euo pipefail

# Focus Viber Desktop and click the message input area (X11 / XWayland).
# Requires: xdotool  (sudo apt install xdotool)
# Optional env: VIBER_WINDOW_CLASS — window class/name substring if autodetection fails

INPUT_OFFSET_BOTTOM="${1:-70}"
INPUT_X_PERCENT="${2:-50}"

if ! command -v xdotool >/dev/null 2>&1; then
  echo "xdotool is required on Linux. Install: sudo apt install xdotool" >&2
  exit 1
fi

if [[ -n "${WAYLAND_DISPLAY:-}" && -z "${DISPLAY:-}" ]]; then
  echo "No DISPLAY: native Wayland often blocks xdotool. Use an X11 session or XWayland + DISPLAY." >&2
  exit 1
fi

find_wid() {
  local wid=""
  if [[ -n "${VIBER_WINDOW_CLASS:-}" ]]; then
    wid="$(xdotool search --limit 1 --onlyvisible --class "$VIBER_WINDOW_CLASS" 2>/dev/null || true)"
    [[ -n "$wid" ]] && echo "$wid" && return 0
  fi
  wid="$(xdotool search --limit 1 --onlyvisible --class "Viber" 2>/dev/null || true)"
  [[ -n "$wid" ]] && echo "$wid" && return 0
  wid="$(xdotool search --limit 1 --onlyvisible --name "Viber" 2>/dev/null || true)"
  [[ -n "$wid" ]] && echo "$wid" && return 0
  wid="$(xdotool search --limit 1 --onlyvisible --classname "Viber" 2>/dev/null || true)"
  [[ -n "$wid" ]] && echo "$wid" && return 0
  return 1
}

WID=""
if ! WID="$(find_wid)"; then
  echo "No visible Viber window found. Start Viber Desktop and try again." >&2
  exit 1
fi

xdotool windowactivate --sync "$WID" 2>/dev/null || xdotool windowfocus --sync "$WID"
sleep 0.25

eval "$(xdotool getwindowgeometry --shell "$WID")"

CLICK_X=$((X + WIDTH * INPUT_X_PERCENT / 100))
CLICK_Y=$((Y + HEIGHT - INPUT_OFFSET_BOTTOM))

xdotool mousemove --sync "$CLICK_X" "$CLICK_Y"
xdotool mousemove --sync "$CLICK_X" "$CLICK_Y"
xdotool click 1
sleep 0.03
xdotool click 1
sleep 0.12
