#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Office365LinuxInstaller
# Clean, legal Microsoft Office 365 (Desktop) installation via Wine on Ubuntu/Debian
# Version: 1.0.000
# Architecture: Status-first, gap-fill only, ODT-based
# =============================================================================

# ---- Configuration ----------------------------------------------------------
WINE_PREFIX="${HOME}/.Microsoft_Office_365"
DOWNLOADS="${HOME}/Downloads"
OFFICE_CACHE="${DOWNLOADS}/OfficeCache"
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

pkg_installed() { dpkg -l "$1" 2>/dev/null | grep -q "^ii"; }
cmd_exists()    { command -v "$1" >/dev/null 2>&1; }

# ---- Status Detection -------------------------------------------------------
detect_status() {
    echo
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║              System Status Detection                       ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo

    # System packages
    if pkg_installed wine64 || pkg_installed wine; then HAS_WINE="yes"; else HAS_WINE="no"; fi
    if cmd_exists winetricks; then HAS_WINETRICKS="yes"; else HAS_WINETRICKS="no"; fi
    if cmd_exists zenity; then HAS_ZENITY="yes"; else HAS_ZENITY="no"; fi

    # Winetricks cache
    HAS_COREFONTS="$(ls ~/.cache/winetricks/corefonts/ 2>/dev/null | wc -l)"
    HAS_MSXML6="$(ls ~/.cache/winetricks/msxml6/ 2>/dev/null | wc -l)"
    HAS_GDIPLUS="$(ls ~/.cache/winetricks/gdiplus/ 2>/dev/null | wc -l)"

    # Wine prefix
    if [ -d "${WINE_PREFIX}/drive_c" ]; then PREFIX_EXISTS="yes"; else PREFIX_EXISTS="no"; fi
    PREFIX_SIZE=$(du -sh "${WINE_PREFIX}/" 2>/dev/null | cut -f1 || echo "N/A")
    if [ -f "${WINE_PREFIX}/drive_c/Program Files/Microsoft Office/root/Office16/WINWORD.EXE" ]; then
        PREFIX_HAS_OFFICE="yes"
    else
        PREFIX_HAS_OFFICE="no"
    fi

    # ODT installer
    if [ -f "${DOWNLOADS}/OfficeSetup.exe" ]; then ODT_FOUND="yes"; else ODT_FOUND="no"; fi
    if wine "${DOWNLOADS}/OfficeSetup.exe" /help 2>/dev/null | grep -q "Office Deployment Tool"; then
        ODT_VERIFIED="yes"
    else
        ODT_VERIFIED="no"
    fi

    # Office cache
    if [ -d "${OFFICE_CACHE}" ] && [ "$(ls -A "${OFFICE_CACHE}" 2>/dev/null | wc -l)" -gt 0 ]; then
        OFFICE_CACHE_EXISTS="yes"
    else
        OFFICE_CACHE_EXISTS="no"
    fi
    OFFICE_CACHE_SIZE=$(du -sh "${OFFICE_CACHE}" 2>/dev/null | cut -f1 || echo "N/A")

    # Print report
    echo "  [System]"
    echo "    Wine:        ${HAS_WINE}"
    echo "    Winetricks:  ${HAS_WINETRICKS}"
    echo "    Zenity:      ${HAS_ZENITY}"
    echo
    echo "  [Winetricks Cache]"
    echo "    Corefonts:   ${HAS_COREFONTS} files"
    echo "    msxml6:      ${HAS_MSXML6} files"
    echo "    gdiplus:     ${HAS_GDIPLUS} files"
    echo
    echo "  [Wine Prefix]"
    echo "    Exists:      ${PREFIX_EXISTS} (${PREFIX_SIZE})"
    echo "    Office:      ${PREFIX_HAS_OFFICE}"
    echo
    echo "  [ODT Installer]"
    echo "    Found:       ${ODT_FOUND}"
    echo "    Verified:    ${ODT_VERIFIED}"
    echo
    echo "  [Office Download Cache]"
    echo "    Exists:      ${OFFICE_CACHE_EXISTS} (${OFFICE_CACHE_SIZE})"
    echo
}

# ---- Gap Fill: System Packages ----------------------------------------------
ensure_packages() {
    local missing=""

    if [ "${HAS_WINE}" = "no" ]; then missing="${missing} wine64 wine32"; fi
    if [ "${HAS_WINETRICKS}" = "no" ]; then missing="${missing} winetricks"; fi
    if [ "${HAS_ZENITY}" = "no" ]; then missing="${missing} zenity"; fi

    if [ -n "${missing}" ]; then
        info "Installing missing packages:${missing} ..."
        sudo dpkg --add-architecture i386 || true
        sudo apt-get update
        sudo apt-get install -y --no-install-recommends ${missing} \
            build-essential gcc-multilib g++-multilib flex bison \
            git wget curl pkg-config gettext \
            cups-daemon cups-client printer-driver-all \
            system-config-printer cups-pdf printer-driver-cups-pdf \
            msitools clang lld \
            libc6:i386 libgcc1:i386 libstdc++6:i386 \
            libfreetype6:i386 libx11-6:i386 libxext6:i386 \
            libxrender1:i386 libxrandr2:i386 \
            winbind samba-common samba-libs gnutls-bin \
            ttf-mscorefonts-installer || true
    else
        info "All system packages present. Skipping apt."
    fi
}

# ---- Gap Fill: Winetricks Libraries -----------------------------------------
ensure_winetricks_libs() {
    local needed=""

    if [ "${HAS_COREFONTS}" -eq 0 ]; then needed="${needed} corefonts"; fi
    if [ "${HAS_MSXML6}" -eq 0 ]; then needed="${needed} msxml6"; fi
    if [ "${HAS_GDIPLUS}" -eq 0 ]; then needed="${needed} gdiplus"; fi

    if [ -n "${needed}" ]; then
        info "Installing missing Winetricks libraries:${needed} ..."
        export WINEPREFIX="${WINE_PREFIX}"
        winetricks -q ${needed} || warn "Some winetricks packages may have failed; continuing."
    else
        info "All Winetricks libraries cached. Skipping."
    fi
}

# ---- Gap Fill: Wine Prefix --------------------------------------------------
ensure_prefix() {
    if [ "${PREFIX_EXISTS}" = "yes" ]; then
        info "Wine prefix exists (${PREFIX_SIZE}). Updating..."
        export WINEPREFIX="${WINE_PREFIX}"
        export WINEARCH="win64"
        wine wineboot -u
    else
        info "Creating clean Wine prefix at ${WINE_PREFIX}..."
        export WINEPREFIX="${WINE_PREFIX}"
        export WINEARCH="win64"
        wineboot --init

        wine reg add "HKCU\\Software\\Wine" /v Version /d "win10" /f || true

        # Rebuild dosdevices
        rm -rf "${WINE_PREFIX}/dosdevices"
        mkdir -p "${WINE_PREFIX}/dosdevices"
        ln -s ../drive_c "${WINE_PREFIX}/dosdevices/c:"
        ln -s /          "${WINE_PREFIX}/dosdevices/z:"
        ln -s /dev/null  "${WINE_PREFIX}/dosdevices/c::"
        ln -s /dev/null  "${WINE_PREFIX}/dosdevices/z::"
        ln -s /media     "${WINE_PREFIX}/dosdevices/d:"
        ln -s "${HOME}"  "${WINE_PREFIX}/dosdevices/e:"

        # Rebuild user folders
        mkdir -p "${WINE_PREFIX}/drive_c/users/crossover/AppData/Local"
        mkdir -p "${WINE_PREFIX}/drive_c/users/crossover/AppData/Roaming"

        sudo chown -R "${USER}:${USER}" "${WINE_PREFIX}"
        chmod -R u+rwX "${WINE_PREFIX}"

        wine wineboot -u
    fi
}

# ---- Gap Fill: ODT Installer --------------------------------------------------
ensure_odt() {
    if [ "${ODT_FOUND}" = "yes" ] && [ "${ODT_VERIFIED}" = "yes" ]; then
        info "ODT verified at ${DOWNLOADS}/OfficeSetup.exe."
        return 0
    fi

    info "ODT not found or not verified. Preparing download..."
    echo
    echo "============================================================================"
    echo " IMPORTANT: Download the Office Deployment Tool (ODT) from Microsoft."
    echo ""
    echo " 1. We will open your browser to:"
    echo "    https://www.microsoft.com/en-us/microsoft-365/download-office"
    echo " 2. Click 'Download for Windows' to get OfficeSetup.exe (~7 MB)."
    echo " 3. Save it to your Downloads folder: ${DOWNLOADS}"
    echo " 4. Return here and press Enter to continue."
    echo "============================================================================"
    echo

    if cmd_exists xdg-open; then
        xdg-open "https://www.microsoft.com/en-us/microsoft-365/download-office" &
    elif cmd_exists firefox; then
        firefox "https://www.microsoft.com/en-us/microsoft-365/download-office" &
    elif cmd_exists google-chrome; then
        google-chrome "https://www.microsoft.com/en-us/microsoft-365/download-office" &
    else
        warn "Could not detect browser. Please manually open the URL above."
    fi

    read -rp "Press Enter once OfficeSetup.exe is in ${DOWNLOADS}..."

    if [ ! -f "${DOWNLOADS}/OfficeSetup.exe" ]; then
        die "OfficeSetup.exe still not found in ${DOWNLOADS}. Aborting."
    fi

    if ! wine "${DOWNLOADS}/OfficeSetup.exe" /help 2>/dev/null | grep -q "Office Deployment Tool"; then
        die "File found but does not appear to be the Office Deployment Tool. Aborting."
    fi

    info "ODT verified."
}

# ---- Generate ODT Configuration XML -----------------------------------------
generate_odt_config() {
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
  <SourcePath>${OFFICE_CACHE}</SourcePath>
</Configuration>
EOF

    echo "${config_path}"
}

# ---- Gap Fill: Office Download Cache ----------------------------------------
ensure_office_download() {
    if [ "${OFFICE_CACHE_EXISTS}" = "yes" ]; then
        info "Office download cache present (${OFFICE_CACHE_SIZE}). Skipping /download."
        return 0
    fi

    info "Office download cache missing. Running ODT /download..."
    info "This will download ~4-5 GB of Office binaries. Please be patient."

    local config_path
    config_path="$(generate_odt_config)"

    export WINEPREFIX="${WINE_PREFIX}"
    mkdir -p "${OFFICE_CACHE}"

    wine "${DOWNLOADS}/OfficeSetup.exe" /download "${config_path}" || die "ODT /download failed."

    info "Office binaries downloaded to ${OFFICE_CACHE}."
}

# ---- Gap Fill: Office Installation ------------------------------------------
ensure_office_install() {
    if [ "${PREFIX_HAS_OFFICE}" = "yes" ]; then
        info "Office already installed in prefix. Skipping /configure."
        return 0
    fi

    info "Installing Office into Wine prefix via ODT /configure..."

    local config_path
    config_path="$(generate_odt_config)"

    export WINEPREFIX="${WINE_PREFIX}"
    wine "${DOWNLOADS}/OfficeSetup.exe" /configure "${config_path}" || die "ODT /configure failed."

    # Verify
    local word_path="${WINE_PREFIX}/drive_c/Program Files/Microsoft Office/root/Office16/WINWORD.EXE"
    if [ ! -f "${word_path}" ]; then
        die "Office installation verification failed: ${word_path} not found."
    fi

    info "Office installed successfully."
}

# ---- Always: Launchers & System Integration -----------------------------------
ensure_launchers() {
    info "Installing launchers, icons, and .desktop entries..."

    sudo mkdir -p "${LAUNCHER_DIR}"
    sudo chmod 755 "${LAUNCHER_DIR}"

    sudo cp "${SCRIPT_DIR}/wrappers/"*365.sh "${LAUNCHER_DIR}/"
    sudo chown root:root "${LAUNCHER_DIR}/"*365.sh
    sudo chmod 755 "${LAUNCHER_DIR}/"*365.sh

    sudo mkdir -p "${ICON_HICOLOR}"
    sudo cp "${SCRIPT_DIR}/icons/"*365.svg "${ICON_HICOLOR}/"
    sudo gtk-update-icon-cache "/usr/share/icons/hicolor/" || warn "gtk-update-icon-cache failed."

    sudo cp "${SCRIPT_DIR}/desktops/"*365.desktop "${APP_DIR}/"
    sudo chown root:root "${APP_DIR}/"*365.desktop
    sudo chmod 644 "${APP_DIR}/"*365.desktop

    sudo update-desktop-database || warn "update-desktop-database failed."

    # Fonts
    if [ -d "${SCRIPT_DIR}/fonts" ] && [ "$(ls -A "${SCRIPT_DIR}/fonts/" 2>/dev/null | wc -l)" -gt 0 ]; then
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

    info "System integration complete."
}

# ---- Test Launch ------------------------------------------------------------
test_launch() {
    info "Running execution test..."

    export WINEPREFIX="${WINE_PREFIX}"
    local word_path="${WINE_PREFIX}/drive_c/Program Files/Microsoft Office/root/Office16/WINWORD.EXE"

    echo "Launching WINWORD.EXE for 5 seconds to verify..."
    timeout 5 wine "${word_path}" &>/dev/null || true
    pkill -9 -f WINWORD.EXE || true

    info "Test complete."
}

# ---- Cache Cleanup Prompt ---------------------------------------------------
prompt_cache_cleanup() {
    if [ "${OFFICE_CACHE_EXISTS}" = "no" ]; then
        # We just downloaded it; compute size
        local cache_size
        cache_size=$(du -sh "${OFFICE_CACHE}" 2>/dev/null | cut -f1 || echo "unknown")
        echo
        read -rp "Office installation complete. Delete download cache (${cache_size}) to save disk space? [y/N]: " answer
        if [[ "${answer}" =~ ^[Yy]$ ]]; then
            rm -rf "${OFFICE_CACHE}"
            info "Cache deleted."
        else
            info "Cache preserved at ${OFFICE_CACHE}."
        fi
    else
        # Cache existed before we ran; user already decided to keep it
        info "Office cache preserved at ${OFFICE_CACHE}."
    fi
}

# ---- Main Orchestrator ------------------------------------------------------
main() {
    echo "========================================"
    echo "  Office365LinuxInstaller v1.0.000"
    echo "  Clean Office 365 via Wine (ODT)"
    echo "========================================"
    echo

    detect_status
    ensure_packages
    ensure_winetricks_libs
    ensure_prefix
    ensure_odt
    ensure_office_download
    ensure_office_install
    ensure_launchers
    test_launch
    prompt_cache_cleanup

    echo
    echo "========================================"
    echo "  Installation Complete!"
    echo "========================================"
    echo
    echo "Launch Office apps from your application menu."
    echo "Sign in with your Microsoft account on first open."
    echo
    echo "To uninstall: ./uninstall.sh"
    echo
}

main "$@"
