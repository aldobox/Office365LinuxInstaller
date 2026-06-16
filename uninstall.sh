#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Office365LinuxInstaller Uninstaller
# Safely removes all artifacts created by install.sh
# Version: 2.1.3
# =============================================================================

info()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }

# ---- Kill Wine / Office processes -------------------------------------------
info "Stopping any running Wine and Office processes..."
pkill -x wineserver          2>/dev/null || true
pkill -x wine                2>/dev/null || true
pkill -x EXCEL.EXE           2>/dev/null || true
pkill -x WINWORD.EXE         2>/dev/null || true
pkill -x POWERPNT.EXE        2>/dev/null || true
pkill -x OUTLOOK.EXE         2>/dev/null || true
pkill -x MSACCESS.EXE        2>/dev/null || true
pkill -x MSPUB.EXE           2>/dev/null || true
pkill -x ONENOTE.EXE         2>/dev/null || true
pkill -x Teams.exe           2>/dev/null || true
pkill -x OFFICEC2RCLIENT.EXE 2>/dev/null || true
pkill -x OfficeClickToRun.exe 2>/dev/null || true

# Wait briefly for processes to die
sleep 2

_safe_rm() {
    local target="$1"
    case "$target" in
        ""|"/"|"."|"..")
            warn "Refusing to remove potentially dangerous path: $target"
            return 1
            ;;
    esac
    rm -rf "$target"
}

# ---- Remove extracted Office binaries ---------------------------------------
OFFICE_EXTRACTED="${HOME}/.office365-extracted"
if [ -d "$OFFICE_EXTRACTED" ]; then
    info "Removing extracted Office binaries: $OFFICE_EXTRACTED"
    _safe_rm "$OFFICE_EXTRACTED"
else
    warn "No extracted binaries found at $OFFICE_EXTRACTED"
fi

# ---- Remove VM extractor artifacts -------------------------------------------
VM_DIR="${HOME}/.office365-extractor-vm"
if [ -d "$VM_DIR" ]; then
    info "Removing VM extractor artifacts: $VM_DIR"
    _safe_rm "$VM_DIR"
else
    warn "No VM artifacts found at $VM_DIR"
fi

# ---- Remove direct download cache --------------------------------------------
IMG_CACHE="${HOME}/.office365-img-cache"
if [ -d "$IMG_CACHE" ]; then
    info "Removing direct download cache: $IMG_CACHE"
    _safe_rm "$IMG_CACHE"
else
    warn "No direct download cache found at $IMG_CACHE"
fi

# ---- Remove isolated Wine ----------------------------------------------------
ISOLATED_WINE="${HOME}/.wine-msoffice/wine"
if [ -d "$ISOLATED_WINE" ]; then
    info "Removing isolated Wine: $ISOLATED_WINE"
    _safe_rm "$ISOLATED_WINE"
else
    warn "No isolated Wine found at $ISOLATED_WINE"
fi

# ---- Clean up any remaining Wine-msoffice directory ------------------------
WINE_MSOFFICE="${HOME}/.wine-msoffice"
if [ -d "$WINE_MSOFFICE" ]; then
    info "Removing Wine-msoffice directory: $WINE_MSOFFICE"
    _safe_rm "$WINE_MSOFFICE"
fi

# ---- Remove Wine prefix ------------------------------------------------------
WINE_PREFIX="${HOME}/.Microsoft_Office_365"
if [ -d "$WINE_PREFIX" ]; then
    info "Removing Wine prefix: $WINE_PREFIX"
    _safe_rm "$WINE_PREFIX"
else
    warn "No Wine prefix found at $WINE_PREFIX"
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
xdg-mime default libreoffice-writer.desktop application/msword 2>/dev/null || true
xdg-mime default libreoffice-writer.desktop application/vnd.openxmlformats-officedocument.wordprocessingml.document 2>/dev/null || true
xdg-mime default libreoffice-calc.desktop application/vnd.ms-excel 2>/dev/null || true
xdg-mime default libreoffice-calc.desktop application/vnd.openxmlformats-officedocument.spreadsheetml.sheet 2>/dev/null || true
xdg-mime default libreoffice-impress.desktop application/vnd.ms-powerpoint 2>/dev/null || true
xdg-mime default libreoffice-impress.desktop application/vnd.openxmlformats-officedocument.presentationml.presentation 2>/dev/null || true

# ---- Update desktop database ------------------------------------------------
sudo update-desktop-database || true

info "Uninstallation complete."
