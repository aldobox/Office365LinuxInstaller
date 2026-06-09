#!/usr/bin/env bash
set -euo pipefail
[[ -d "${HOME}/.wine-msoffice/wine/usr/bin" ]] && export PATH="${HOME}/.wine-msoffice/wine/usr/bin:${PATH}"
export WINEPREFIX="${HOME}/.Microsoft_Office_365"
export WINEARCH="win32"
# Note: Teams in Office 365 is frequently updated; this launcher points to the classic path.
# If your installation uses a different path, edit this file accordingly.
exec wine "${WINEPREFIX}/drive_c/Program Files/Microsoft Office/root/Office16/Teams.exe" "$@" || \
    exec wine "${WINEPREFIX}/drive_c/Program Files (x86)/Microsoft/Teams/current/Teams.exe" "$@" || \
    { echo "Teams binary not found in expected Wine prefix location."; exit 1; }
