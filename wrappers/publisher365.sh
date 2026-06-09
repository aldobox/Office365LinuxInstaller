#!/usr/bin/env bash
set -euo pipefail
[[ -d "${HOME}/.wine-msoffice/wine/usr/bin" ]] && export PATH="${HOME}/.wine-msoffice/wine/usr/bin:${PATH}"
export WINEPREFIX="${HOME}/.Microsoft_Office_365"
export WINEARCH="win32"
exec wine "${WINEPREFIX}/drive_c/Program Files/Microsoft Office/root/Office16/MSPUB.EXE" "$@"
