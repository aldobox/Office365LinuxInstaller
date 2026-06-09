#!/usr/bin/env bash
set -uo pipefail

# =============================================================================
# Office365LinuxInstaller Uninstaller
# Safely removes all artifacts created by install.sh
# Version: 2.0.0
# =============================================================================

info()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }

# ---- Kill Wine / Office processes -------------------------------------------
info "Stopping any running Wine and Office processes..."
pkill -9 -f wineserver          2>/dev/null || true
pkill -9 -f wine                2>/dev/null || true
pkill -9 -f EXCEL.EXE           2>/dev/null || true
pkill -9 -f WINWORD.EXE         2>/dev/null || true
pkill -9 -f POWERPNT.EXE        2>/dev/null || true
pkill -9 -f OUTLOOK.EXE         2>/dev/null || true
pkill -9 -f MSACCESS.EXE        2>/dev/null || true
pkill -9 -f MSPUB.EXE           2>/dev/null || true
pkill -9 -f ONENOTE.EXE         2>/dev/null || true
pkill -9 -f Teams.exe           2>/dev/null || true
pkill -9 -f OFFICEC2RCLIENT.EXE 2>/dev/null || true
pkill -9 -f OfficeClickToRun.exe 2>/dev/null || true

# Wait briefly for processes to die
sleep 2

# ---- Remove extracted Office binaries ---------------------------------------
if [ -d "${HOME}/.office365-extracted" ]; then
    info "Removing extracted Office binaries: ${HOME}/.office365-extracted"
    rm -rf "${HOME}/.office365-extracted"
else
    warn "No extracted binaries found at ${HOME}/.office365-extracted"
fi

# ---- Remove VM extractor artifacts -------------------------------------------
if [ -d "${HOME}/.office365-extractor-vm" ]; then
    info "Removing VM extractor artifacts: ${HOME}/.office365-extractor-vm"
    rm -rf "${HOME}/.office365-extractor-vm"
else
    warn "No VM artifacts found at ${HOME}/.office365-extractor-vm"
fi

# ---- Remove isolated Wine ----------------------------------------------------
if [ -d "${HOME}/.wine-msoffice/wine" ]; then
    info "Removing isolated Wine: ${HOME}/.wine-msoffice/wine"
    rm -rf "${HOME}/.wine-msoffice/wine"
else
    warn "No isolated Wine found at ${HOME}/.wine-msoffice/wine"
fi

# ---- Clean up any remaining Wine-msoffice directory ------------------------
if [ -d "${HOME}/.wine-msoffice" ]; then
    info "Removing Wine-msoffice directory: ${HOME}/.wine-msoffice"
    rm -rf "${HOME}/.wine-msoffice"
fi

# ---- Remove Wine prefix ------------------------------------------------------
if [ -d "${HOME}/.Microsoft_Office_365" ]; then
    info "Removing Wine prefix: ${HOME}/.Microsoft_Office_365"
    rm -rf "${HOME}/.Microsoft_Office_365"
else
    warn "No Wine prefix found at ${HOME}/.Microsoft_Office_365"
fi

# ---- Remove launcher wrappers ------------------------------------------------
if ls /opt/launchers/*365.sh 1>/dev/null 2>&1; then
    info "Removing launcher wrappers from /opt/launchers/"
    sudo rm -f /opt/launchers/*365.sh
else
    warn "No launcher wrappers found in /opt/launchers/"
fi

# ---- Remove .desktop files -------------------------------------------------
if ls /usr/share/applications/*365.desktop 1>/dev/null 2>&1; then
    info "Removing .desktop files from /usr/share/applications/"
    sudo rm -f /usr/share/applications/*365.desktop
else
    warn "No .desktop files found in /usr/share/applications/"
fi

# ---- Remove icons ------------------------------------------------------------
if ls /usr/share/icons/hicolor/256x256/apps/*365.svg 1>/dev/null 2>&1; then
    info "Removing icons from /usr/share/icons/hicolor/256x256/apps/"
    sudo rm -f /usr/share/icons/hicolor/256x256/apps/*365.svg
    sudo gtk-update-icon-cache /usr/share/icons/hicolor/ || true
else
    warn "No icons found in /usr/share/icons/hicolor/256x256/apps/"
fi

# ---- Remove bundled fonts ----------------------------------------------------
if [ -d "/usr/share/fonts/Windows" ]; then
    info "Removing bundled Office fonts..."
    sudo rm -rf /usr/share/fonts/Windows
    sudo fc-cache -fv || true
else
    warn "No bundled font directory found."
fi

# ---- Reset MIME defaults -----------------------------------------------------
info "Resetting MIME defaults to system defaults..."
xdg-mime default libreoffice--writer.desktop application/msword 2>/dev/null || true
xdg-mime default libreoffice--writer.desktop application/vnd.openxmlformats-officedocument.wordprocessingml.document 2>/dev/null || true
xdg-mime default libreoffice--calc.desktop application/vnd.ms-excel 2>/dev/null || true
xdg-mime default libreoffice--calc.desktop application/vnd.openxmlformats-officedocument.spreadsheetml.sheet 2>/dev/null || true
xdg-mime default libreoffice--impress.desktop application/vnd.ms-powerpoint 2>/dev/null || true
xdg-mime default libreoffice--impress.desktop application/vnd.openxmlformats-officedocument.presentationml.presentation 2>/dev/null || true

# ---- Update desktop database ------------------------------------------------
sudo update-desktop-database || true

info "Uninstallation complete."
