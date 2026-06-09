#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Office365LinuxInstaller
# Clean, legal Microsoft Office 365 (Desktop) installation via Wine on Ubuntu/Debian
# Version: 1.0.000
# =============================================================================

# ---- Configuration ----------------------------------------------------------
WINE_PREFIX="${HOME}/.Microsoft_Office_365"
DOWNLOADS="${HOME}/Downloads"
ICON_SIZE="256x256"
ICON_HICOLOR="/usr/share/icons/hicolor/${ICON_SIZE}/apps"
APP_DIR="/usr/share/applications"
FONT_DIR="/usr/share/fonts/Windows"
LAUNCHER_DIR="/opt/launchers"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- Helpers ----------------------------------------------------------------
info()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }
die()   { error "$*"; exit 1; }

wait_for_enter() {
    echo
    read -rp "Press Enter to continue..."
}

# ---- Lock Wait Helper -------------------------------------------------------
wait_for_dpkg_lock() {
    local max_wait=12
    local waited=0
    local lock="/var/lib/dpkg/lock-frontend"

    while [ ${waited} -lt ${max_wait} ]; do
        if ! fuser "${lock}" >/dev/null 2>&1; then
            return 0
        fi

        local blocker
        blocker=$(fuser "${lock}" 2>/dev/null | xargs ps -o comm= -p 2>/dev/null | head -1 || echo "unknown")
        warn "Package manager lock held by '${blocker}'. Waiting... (${waited}s/${max_wait}s)"
        sleep 4
        waited=$((waited + 4))
    done

    # Final check after wait
    if ! fuser "${lock}" >/dev/null 2>&1; then
        return 0
    fi

    # Prompt user to resolve manually
    warn "Package manager lock still held. Waiting for you to resolve."
    read -rp "Press Enter once the other apt/dpkg process has finished (or Ctrl+C to cancel)..."

    if fuser "${lock}" >/dev/null 2>&1; then
        die "Package manager lock is still active. Cannot continue."
    fi
}

# ---- Phase A: Dependencies -------------------------------------------------
phase_a_dependencies() {
    info "Phase A: Installing system dependencies..."

    # Prevent interactive debconf prompts during package installation
    export DEBIAN_FRONTEND=noninteractive

    # Enable 32-bit architecture
    sudo dpkg --add-architecture i386 || true
    sudo apt-get update

    # Wait for any other apt/dpkg process to release the lock
    wait_for_dpkg_lock

    # Install all packages in a single compound command
    # Categories: build tools, printing, MSI tooling, LLVM, 32-bit libs, X11, networking, fonts, Wine
    sudo apt-get install -y --no-install-recommends \
        build-essential gcc-multilib g++-multilib flex bison \
        git wget curl pkg-config gettext \
        zenity \
        cups-daemon cups-client printer-driver-all \
        system-config-printer printer-driver-cups-pdf \
        msitools \
        clang lld \
        libc6:i386 libgcc1:i386 libstdc++6:i386 \
        libfreetype6:i386 libx11-6:i386 libxext6:i386 \
        libxrender1:i386 libxrandr2:i386 \
        winbind samba-common samba-libs gnutls-bin \
        ttf-mscorefonts-installer \
        wine64 wine32 winetricks

    info "Dependencies installed or already present."
}

# ---- Phase B: Create Clean Wine Prefix --------------------------------------
phase_b_wine_prefix() {
    info "Phase B: Creating clean Wine prefix at ${WINE_PREFIX}..."

    # Remove any stale prefix to avoid conflicts
    if [ -d "${WINE_PREFIX}" ]; then
        warn "Existing prefix found. Removing to start fresh..."
        rm -rf "${WINE_PREFIX}"
    fi

    export WINEPREFIX="${WINE_PREFIX}"
    export WINEARCH="win64"

    # Initialize prefix
    wineboot --init

    # Set Windows version to Windows 10 (required by modern Office)
    wine reg add "HKCU\\Software\\Wine" /v Version /d "win10" /f || true

    # Install common redistributables Office expects
    info "Installing Winetricks packages (corefonts, msxml6, gdiplus)..."
    winetricks -q corefonts msxml6 gdiplus || warn "Some winetricks packages may have failed; continuing."

    # Rebuild dosdevices exactly as in the original clean structure
    info "Rebuilding Wine dosdevices..."
    rm -rf "${WINE_PREFIX}/dosdevices"
    mkdir -p "${WINE_PREFIX}/dosdevices"

    ln -s ../drive_c "${WINE_PREFIX}/dosdevices/c:"
    ln -s /          "${WINE_PREFIX}/dosdevices/z:"
    ln -s /dev/null  "${WINE_PREFIX}/dosdevices/c::"
    ln -s /dev/null  "${WINE_PREFIX}/dosdevices/z::"
    ln -s /media     "${WINE_PREFIX}/dosdevices/d:"
    ln -s "${HOME}"  "${WINE_PREFIX}/dosdevices/e:"

    # Rebuild user folders
    info "Rebuilding user folders..."
    mkdir -p "${WINE_PREFIX}/drive_c/users/crossover/AppData/Local"
    mkdir -p "${WINE_PREFIX}/drive_c/users/crossover/AppData/Roaming"

    # Fix ownership/permissions
    sudo chown -R "${USER}:${USER}" "${WINE_PREFIX}"
    chmod -R u+rwX "${WINE_PREFIX}"

    # Final update of the prefix
    wine wineboot -u

    info "Wine prefix created and configured."
}

# ---- Phase C: Prompt for Official Installer ---------------------------------
phase_c_get_installer() {
    info "Phase C: Preparing for official Office installer download..."

    echo
    echo "============================================================================"
    echo " IMPORTANT: You must download the official Microsoft Office installer."
    echo ""
    echo " 1. We will open your web browser to https://www.microsoft.com/en-us/microsoft-365/download-office"
    echo " 2. Click 'Download for Windows' to get the Office Deployment Tool (ODT)."
    echo " 3. Save the downloaded file (usually 'OfficeSetup.exe')"
    echo "    to your Downloads folder: ${DOWNLOADS}"
    echo " 4. Return here and press Enter to continue."
    echo "============================================================================"
    echo

    # Attempt to open browser
    if command -v xdg-open &>/dev/null; then
        xdg-open "https://www.microsoft.com/en-us/microsoft-365/download-office" &
    elif command -v firefox &>/dev/null; then
        firefox "https://www.microsoft.com/en-us/microsoft-365/download-office" &
    elif command -v google-chrome &>/dev/null; then
        google-chrome "https://www.microsoft.com/en-us/microsoft-365/download-office" &
    else
        warn "Could not detect a browser. Please manually open https://www.microsoft.com/en-us/microsoft-365/download-office"
    fi

    wait_for_enter

    # Locate installer
    local installer=""
    for candidate in "${DOWNLOADS}/Setup.exe" "${DOWNLOADS}/OfficeSetup.exe"; do
        if [ -f "${candidate}" ]; then
            installer="${candidate}"
            break
        fi
    done

    if [ -z "${installer}" ]; then
        die "No Setup.exe or OfficeSetup.exe found in ${DOWNLOADS}. " \
            "Please download the official installer and try again."
    fi

    echo "Found installer: ${installer}"
    INSTALLER_PATH="${installer}"
}

# ---- Phase D: Run Official Installer in Wine (ODT-aware) --------------------
phase_d_install_office() {
    info "Phase D: Installing official Office into Wine prefix..."

    export WINEPREFIX="${WINE_PREFIX}"
    export WINEARCH="win64"

    # Generate ODT configuration XML
    local config_path="/tmp/o365_configuration.xml"
    cat > "${config_path}" <<EOF
<Configuration>
  <Add OfficeClientEdition="64" Channel="Current">
    <Product ID="O365ProPlusRetail">
      <Language ID="en-GB" />
    </Product>
  </Add>
  <Display Level="None" AcceptEULA="TRUE" />
  <Property Name="AUTOACTIVATE" Value="0" />
  <Property Name="FORCEAPPSHUTDOWN" Value="TRUE" />
  <Property Name="SharedComputerLicensing" Value="0" />
  <Property Name="PinIconsToTaskbar" Value="FALSE" />
  <Updates Enabled="TRUE" Channel="Current" />
</Configuration>
EOF

    local office_cache="${DOWNLOADS}/OfficeCache"

    # Check if download cache already exists
    if [ -d "${office_cache}" ] && [ "$(ls -A "${office_cache}" 2>/dev/null | wc -l)" -gt 0 ]; then
        info "Office download cache found at ${office_cache}. Skipping /download."
    else
        info "Downloading Office binaries (~4-5 GB). This will take time..."
        mkdir -p "${office_cache}"
        wine "${INSTALLER_PATH}" /download "${config_path}" || die "ODT /download failed."
        info "Download complete."
    fi

    # Install from cache into prefix
    info "Installing Office from cache into Wine prefix..."
    wine "${INSTALLER_PATH}" /configure "${config_path}" || die "ODT /configure failed."

    # Verify installation
    local word_path="${WINE_PREFIX}/drive_c/Program Files/Microsoft Office/root/Office16/WINWORD.EXE"
    if [ ! -f "${word_path}" ]; then
        die "Office installation verification failed: ${word_path} not found."
    fi

    info "Office installed successfully."
}

# ---- Phase E: Copy Launchers & Wrappers -------------------------------------
phase_e_launchers() {
    info "Phase E: Setting up application launchers..."

    # Create launcher directory
    sudo mkdir -p "${LAUNCHER_DIR}"
    sudo chmod 755 "${LAUNCHER_DIR}"

    # Copy wrappers from package
    sudo cp "${SCRIPT_DIR}/wrappers/"*365.sh "${LAUNCHER_DIR}/"
    sudo chown root:root "${LAUNCHER_DIR}/"*365.sh
    sudo chmod 755 "${LAUNCHER_DIR}/"*365.sh

    info "Launchers installed to ${LAUNCHER_DIR}."
}

# ---- Phase F: Icons & .desktop Files ----------------------------------------
phase_f_desktop_integration() {
    info "Phase F: Installing icons and .desktop entries..."

    # Icons
    sudo mkdir -p "${ICON_HICOLOR}"
    sudo cp "${SCRIPT_DIR}/icons/"*365.svg "${ICON_HICOLOR}/"
    sudo gtk-update-icon-cache "/usr/share/icons/hicolor/" || warn "gtk-update-icon-cache failed."

    # .desktop files
    sudo cp "${SCRIPT_DIR}/desktops/"*365.desktop "${APP_DIR}/"
    sudo chown root:root "${APP_DIR}/"*365.desktop
    sudo chmod 644 "${APP_DIR}/"*365.desktop

    sudo update-desktop-database || warn "update-desktop-database failed."

    info "Desktop integration complete."
}

# ---- Phase G: Fonts & MIME -------------------------------------------------
phase_g_fonts_mime() {
    info "Phase G: Installing fonts and setting MIME associations..."

    # Copy bundled fonts
    if [ -d "${SCRIPT_DIR}/fonts" ] && [ "$(ls -A "${SCRIPT_DIR}/fonts/")" ]; then
        sudo mkdir -p "${FONT_DIR}"
        sudo cp "${SCRIPT_DIR}/fonts/"*.ttf "${SCRIPT_DIR}/fonts/"*.TTF "${SCRIPT_DIR}/fonts/"*.ttc "${FONT_DIR}/" 2>/dev/null || true
        sudo fc-cache -fv || warn "fc-cache failed."
    fi

    # MIME defaults
    xdg-mime default word365.desktop application/msword
    xdg-mime default word365.desktop application/vnd.openxmlformats-officedocument.wordprocessingml.document

    xdg-mime default excel365.desktop application/vnd.ms-excel
    xdg-mime default excel365.desktop application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
    xdg-mime default excel365.desktop text/csv

    xdg-mime default powerpoint365.desktop application/vnd.ms-powerpoint
    xdg-mime default powerpoint365.desktop application/vnd.openxmlformats-officedocument.presentationml.presentation

    xdg-mime default access365.desktop application/vnd.ms-access
    xdg-mime default publisher365.desktop application/vnd.ms-publisher

    info "Fonts and MIME associations configured."
}

# ---- Phase H: Test Launch ---------------------------------------------------
phase_h_test() {
    info "Phase H: Running execution test..."

    export WINEPREFIX="${WINE_PREFIX}"
    local word_path="${WINE_PREFIX}/drive_c/Program Files/Microsoft Office/root/Office16/WINWORD.EXE"

    # Launch Word briefly then kill to confirm the binary runs
    echo "Launching WINWORD.EXE for 5 seconds to verify execution..."
    timeout 5 wine "${word_path}" &>/dev/null || true
    pkill -9 -f WINWORD.EXE || true

    info "Test complete. If no severe errors were shown above, installation is functional."
}

# ---- Phase I: Cleanup Prompt -------------------------------------------------
phase_i_cleanup() {
    local office_cache="${DOWNLOADS}/OfficeCache"
    local tmp_config="/tmp/o365_configuration.xml"

    echo
    read -rp "Delete Office download cache and temp files to save disk space? [y/n]: " answer
    if [[ "${answer}" =~ ^[Yy]$ ]]; then
        if [ -d "${office_cache}" ]; then
            rm -rf "${office_cache}"
            info "Office cache deleted."
        fi
        if [ -f "${tmp_config}" ]; then
            rm -f "${tmp_config}"
        fi
        # Also clean Winetricks temp
        rm -f /tmp/winetricks.* 2>/dev/null || true
    else
        info "Cache preserved at ${office_cache}."
    fi
}

# ---- Main Orchestrator ------------------------------------------------------
main() {
    echo "========================================"
    echo "  Office365LinuxInstaller v1.0.101"
    echo "  Clean Office 365 via Wine"
    echo "========================================"
    echo
    echo "This installer uses sudo to install system packages"
    echo "and desktop integration files. You may be prompted for"
    echo "your password."
    echo

    phase_a_dependencies
    phase_b_wine_prefix
    phase_c_get_installer
    phase_d_install_office
    phase_e_launchers
    phase_f_desktop_integration
    phase_g_fonts_mime
    phase_h_test
    phase_i_cleanup

    echo
    echo "========================================"
    echo "  Installation Complete!"
    echo "========================================"
    echo
    echo "You can now launch Office apps from your application menu."
    echo "Sign in with your Microsoft account when first opening each app."
    echo
    echo "To uninstall, run: ./uninstall.sh"
    echo
}

main "$@"
