#!/usr/bin/env bash
set -euo pipefail
# Use isolated Wine 9.7 if available, otherwise system wine
[[ -d "${HOME}/.wine-msoffice/wine/usr/bin" ]] && export PATH="${HOME}/.wine-msoffice/wine/usr/bin:${PATH}"
export WINEPREFIX="${HOME}/.Microsoft_Office_365"
export WINEARCH="win32"
exec wine "${WINEPREFIX}/drive_c/Program Files/Microsoft Office/root/Office16/WINWORD.EXE" "$@"
