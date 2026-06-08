#!/usr/bin/env bash
set -euo pipefail
export WINEPREFIX="${HOME}/.Microsoft_Office_365"
exec wine "${WINEPREFIX}/drive_c/Program Files/Microsoft Office/root/Office16/EXCEL.EXE" "$@"
