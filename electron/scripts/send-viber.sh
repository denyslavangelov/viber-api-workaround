#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MESSAGE="${1:?message required}"
SKIP_ENTER="${2:-0}"
INPUT_OFFSET_BOTTOM="${3:-70}"
INPUT_X_PERCENT="${4:-50}"

copy_to_clipboard() {
  local msg="$1"
  if command -v wl-copy >/dev/null 2>&1 && [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
    if printf '%s' "$msg" | wl-copy 2>/dev/null; then
      return 0
    fi
  fi
  if command -v xclip >/dev/null 2>&1; then
    if printf '%s' "$msg" | xclip -selection clipboard; then
      return 0
    fi
  fi
  if command -v xsel >/dev/null 2>&1; then
    if printf '%s' "$msg" | xsel --clipboard --input; then
      return 0
    fi
  fi
  if command -v wl-copy >/dev/null 2>&1; then
    if printf '%s' "$msg" | wl-copy; then
      return 0
    fi
  fi
  echo "Install a clipboard tool: xclip, xsel, or wl-copy." >&2
  return 1
}

"$SCRIPT_DIR/focus-viber.sh" "$INPUT_OFFSET_BOTTOM" "$INPUT_X_PERCENT"
copy_to_clipboard "$MESSAGE"
sleep 0.1
xdotool key --clearmodifiers ctrl+v

if [[ "$SKIP_ENTER" != "1" ]]; then
  sleep 0.14
  xdotool key --clearmodifiers Return
fi
