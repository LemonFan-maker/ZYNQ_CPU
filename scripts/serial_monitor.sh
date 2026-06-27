#!/usr/bin/env bash
set -euo pipefail

baud="${2:-115200}"
dev="${1:-}"
logfile="${3:-}"

if [[ -z "$dev" ]]; then
  dev="$(find /dev -maxdepth 1 \( -name 'ttyUSB*' -o -name 'ttyACM*' \) 2>/dev/null | sort | head -n 1 || true)"
fi

if [[ -z "$dev" ]]; then
  echo "No serial device found. Plug in/power the board and check /dev/ttyUSB* or /dev/ttyACM*." >&2
  exit 1
fi

if [[ -n "$logfile" ]]; then
  echo "Opening $dev at $baud baud, logging to $logfile. Press Ctrl-A then Ctrl-X to exit picocom."
  exec picocom -b "$baud" --logfile "$logfile" "$dev"
fi

echo "Opening $dev at $baud baud. Press Ctrl-A then Ctrl-X to exit picocom."
exec picocom -b "$baud" "$dev"
