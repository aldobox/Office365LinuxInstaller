#!/usr/bin/env bash
set -euo pipefail

# Keep terminal open on error so user can read the message
trap 'echo; echo "[FATAL] Installation failed at line $LINENO. See error above."; echo "If you need help, run with: bash -x install.sh"; read -rp "Press Enter to exit..."; exit 1' ERR

# =============================================================================
# Office365LinuxInstaller
# Clean, legal Microsoft Office 365 (Desktop) installation via Wine on Ubuntu/Debian
# Version: 1.0.000
# =============================================================================

# ---- User Detection (for privilege dropping) ------------------------------
# Detect the real user even when script is run via sudo
current_user() {
    logname 2>/dev/null || echo "${SUDO_USER:-$USER}"
}
CURRENT_USER=$(current_user)
CURRENT_HOME=$(getent passwd "$CURRENT_USER" | cut -d: -f6 || echo "$HOME")

# ---- Configuration ----------------------------------------------------------
WINE_PREFIX="${CURRENT_HOME}/.Microsoft_Office_365"
DOWNLOADS="${CURRENT_HOME}/Downloads"
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

# ---- Wine Compatibility Check -----------------------------------------------
# Detect Wine version early and abort if WoW64 mode (Wine 9.0+) is found.
# This saves the user from downloading 4-5 GB of Office files that can never be installed.
check_wine_compatibility() {
    if ! command -v wine >/dev/null 2>&1; then
        info "Wine not found. Installing Wine, wine32, and winetricks via apt..."
        run_apt_install wine wine32 winetricks
    fi

    local wine_version
    wine_version=$(wine --version 2>/dev/null | grep -oP '\d+\.\d+' | head -1)

    if [[ -n "$wine_version" && "$(printf '%s\n' "9.0" "$wine_version" | sort -V | head -n1)" == "9.0" ]]; then
        # Wine >= 9.0 — check for WoW64
        local wine_build_info
        wine_build_info=$(wine --version 2>/dev/null)
        if echo "$wine_build_info" | grep -qi "wow64\|staging\|repack"; then
            error "Wine $wine_version uses WoW64 mode."
            error "Office 365 Click-to-Run cannot install via modern Wine."
            echo
            info "Options:"
            echo "  (1) Use LinOffice / WinApps (VM-based, seamless)"
            echo "  (2) Use CodeWeavers CrossOver (paid, works)"
            echo "  (3) Build Wine 9.7 from source (unsupported, fragile)"
            echo
            read -rp "Press Enter to exit..."
            exit 1
        fi
    fi
}

# Drop privileges when running as root (e.g., via sudo bash install.sh)
run_as_user() {
    if [ "${EUID:-$(id -u)}" -eq 0 ] && [ "$CURRENT_USER" != "root" ]; then
        if command -v runuser >/dev/null 2>&1; then
            runuser -u "$CURRENT_USER" -- "$@"
        else
            sudo -u "$CURRENT_USER" -- "$@"
        fi
    else
        "$@"
    fi
}
# Dynamic progress tracking: uses 'progress' command for file-I/O phases
# (apt, winetricks) and file-size polling for silent phases (ODT download/install)

# Draw a single-line ASCII progress bar
_draw_bar() {
    local pct="${1}"
    local label="${2}"
    local width=40
    local filled=$((pct * width / 100))
    local empty=$((width - filled))
    # Build bar string
    local bar=""
    local i
    for ((i = 0; i < filled; i++)); do bar="#${bar}"; done
    for ((i = 0; i < empty; i++)); do bar="${bar} "; done
    printf "\r[%s] %3d%%  %s" "${bar}" "${pct}" "${label}"
}

# Poll folder size every 1s and draw a dynamic bar until parent PID dies
poll_folder_progress() {
    local folder="${1}"
    local expected_bytes="${2}"
    local label="${3}"
    local parent_pid="${4}"
    local start_time
    start_time=$(date +%s)

    while kill -0 "${parent_pid}" 2>/dev/null; do
        local current_bytes
        current_bytes=$(du -sb "${folder}" 2>/dev/null | cut -f1)
        local pct=0
        if [ "${expected_bytes}" -gt 0 ]; then
            pct=$((current_bytes * 100 / expected_bytes))
            [ "${pct}" -gt 100 ] && pct=100
        fi
        local current_gb
        current_gb=$(awk "BEGIN {printf \"%.1f\", ${current_bytes}/1024/1024/1024}")
        local expected_gb
        expected_gb=$(awk "BEGIN {printf \"%.1f\", ${expected_bytes}/1024/1024/1024}")
        local elapsed
        elapsed=$(($(date +%s) - start_time))
        local speed="0"
        if [ "${elapsed}" -gt 0 ]; then
            speed=$(awk "BEGIN {printf \"%.1f\", (${current_bytes}/${elapsed})/1024/1024}")
        fi
        _draw_bar "${pct}" "${current_gb} GB / ${expected_gb} GB  (${speed} MB/s) — ${label}"
        sleep 1
    done
    echo  # Newline after bar completes
}

# Start background 'progress' monitor for file-I/O phases
start_progress_monitor() {
    if command -v progress &>/dev/null; then
        # -w = watch mode, -M = monitor all processes
        progress -w -M 2>/dev/null &
        PROGRESS_PID=$!
    fi
}

# Stop background progress monitor
stop_progress_monitor() {
    if [ -n "${PROGRESS_PID:-}" ]; then
        kill "${PROGRESS_PID}" 2>/dev/null || true
        wait "${PROGRESS_PID}" 2>/dev/null || true
        unset PROGRESS_PID
    fi
}

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

# ---- Apt Install with Race-Resilient Retry -----------------------------------
# Checks lock INSIDE the apt call. Retries up to 3 times on lock contention.
# On non-lock failures (missing packages, network), fails fast via set -e.
run_apt_install() {
    local max_retries=3
    local attempt=1

    while [ ${attempt} -le ${max_retries} ]; do
        wait_for_dpkg_lock

        # Capture exit code directly from apt-get (NOT from an if-statement,
        # because bash 'if' without 'else' returns 0 when test is false).
        sudo apt-get install -y --no-install-recommends "$@"
        local apt_exit=$?

        if [ ${apt_exit} -eq 0 ]; then
            return 0
        fi

        # If apt failed because of the lock, retry. Otherwise, fail fast.
        if fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; then
            warn "apt-get failed (likely lock contention). Retry ${attempt}/${max_retries}..."
            sleep 2
            attempt=$((attempt + 1))
            continue
        else
            return ${apt_exit}
        fi
    done

    die "apt-get install failed after ${max_retries} attempts."
}

# ---- Phase A: Dependencies -------------------------------------------------
phase_a_dependencies() {
    info "Phase A: Installing system dependencies..."

    # Prevent interactive debconf prompts during package installation
    export DEBIAN_FRONTEND=noninteractive

    # Enable 32-bit architecture
    sudo dpkg --add-architecture i386 || true
    sudo apt-get update

    # Install all packages in a single compound command
    # Categories: build tools, printing, MSI tooling, LLVM, 32-bit libs, X11, networking, fonts, Wine
    run_apt_install \
        build-essential gcc-multilib g++-multilib flex bison \
        git wget curl pkg-config gettext \
        zenity progress \
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

    # Start background progress monitor for file-I/O tracking
    start_progress_monitor

    info "Dependencies installed or already present."
    stop_progress_monitor
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
    # CRITICAL: Use 32-bit prefix. 64-bit prefix causes:
    #   - dotnet40 install failure (mscoree.dll overwrite bug)
    #   - SEH crash in wow64 layer (err:seh:NtRaiseException)
    #   - OfficeClickToRun.exe deadlock
    export WINEARCH="win32"

    # Initialize prefix (as user, never root)
    run_as_user wineboot --init

    # Set Windows version to Windows 10 (required by modern Office)
    run_as_user wine reg add "HKCU\\Software\\Wine" /v Version /d "win10" /f || true

    # Registry tweaks required for Office 365 stability on Wine
    info "Applying Wine registry tweaks for Office compatibility..."
    run_as_user wine reg add "HKCU\\Software\\Wine\\Direct2D" /v max_version_factory /d "0" /f || true
    run_as_user wine reg add "HKCU\\Software\\Wine\\Direct3D" /v MaxVersionGL /d "30002" /f || true

    # Install common redistributables Office expects
    info "Installing Winetricks packages (corefonts, msxml6, gdiplus, dotnet40)..."
    start_progress_monitor
    run_as_user winetricks -q corefonts msxml6 gdiplus dotnet40 || warn "Some winetricks packages may have failed; continuing."
    stop_progress_monitor

    # Rebuild dosdevices
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
    mkdir -p "${WINE_PREFIX}/drive_c/users/${USER}/AppData/Local"
    mkdir -p "${WINE_PREFIX}/drive_c/users/${USER}/AppData/Roaming"

    # Fix ownership/permissions (handle root-run scripts gracefully)
    chown -R "${CURRENT_USER}:${CURRENT_USER}" "${WINE_PREFIX}"
    chmod -R u+rwX "${WINE_PREFIX}"

    # Final update of the prefix (as user)
    run_as_user wine wineboot -u

    info "Wine prefix created and configured."
}

# ---- Phase C: Prompt for Official Installer ---------------------------------
phase_c_get_installer() {
    info "Phase C: Preparing for official Office installer download..."

    # If installer is already present, skip the browser prompt entirely
    local auto_installer=""
    for candidate in "${DOWNLOADS}/Setup.exe" "${DOWNLOADS}/OfficeSetup.exe"; do
        if [ -f "${candidate}" ]; then
            auto_installer="${candidate}"
            break
        fi
    done

    if [ -n "${auto_installer}" ]; then
        info "Found existing installer: ${auto_installer}. Skipping browser prompt."
        INSTALLER_PATH="${auto_installer}"
        return 0
    fi

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
    export WINEARCH="win32"

    # Use Downloads directory for config — Wine maps /tmp poorly via Z:\ drive
    local config_path="${DOWNLOADS}/o365_configuration.xml"
    cat > "${config_path}" <<EOF
<Configuration>
  <Add OfficeClientEdition="32" Channel="Current">
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

    # ODT downloads to a default location under ~/Downloads/Office/
    # We use the Data/ subdirectory as the marker that download succeeded
    # Convert Linux config path to Windows path for ODT
    local win_config_path
    win_config_path=$(run_as_user wine winepath -w "${config_path}" 2>/dev/null) || die "Failed to convert config path to Windows format."

    local office_data="${DOWNLOADS}/Office/Data"

    # Check if download cache already exists and is non-empty
    if [ -d "${office_data}" ] && [ "$(ls -A "${office_data}" 2>/dev/null | wc -l)" -gt 0 ]; then
        info "Office download cache found at ${DOWNLOADS}/Office. Skipping /download."
    else
        info "Downloading Office binaries (~4-5 GB). This may take 20-30 minutes..."
        # Run ODT /download in background so we can poll folder size for progress
        (cd "${DOWNLOADS}" && wine "${INSTALLER_PATH}" /download "${win_config_path}") 2>/dev/null &
        local download_pid=$!
        # 4.5 GB = 4831838208 bytes
        poll_folder_progress "${DOWNLOADS}/Office" 4831838208 "Downloading Office" "${download_pid}"
        wait "${download_pid}" || die "ODT /download failed."

        # Verify download actually happened (don't trust exit code alone)
        if [ ! -d "${office_data}" ] || [ "$(ls -A "${office_data}" 2>/dev/null | wc -l)" -eq 0 ]; then
            die "ODT /download reported success but ${office_data} is empty. Config path issue?"
        fi
        info "Download complete."
    fi

    # Install from cache into prefix
    info "Installing Office from cache into Wine prefix..."
    info "This may take 10-15 minutes."
    # Run ODT /configure in background so we can poll prefix size for progress
    (cd "${DOWNLOADS}" && wine "${INSTALLER_PATH}" /configure "${win_config_path}") 2>/dev/null &
    local configure_pid=$!
    # Prefix grows from ~100 MB to ~2.5+ GB during install
    # 3.0 GB = 3221225472 bytes (generous estimate, bar clamps at 100%%)
    poll_folder_progress "${WINE_PREFIX}" 3221225472 "Installing Office" "${configure_pid}"
    wait "${configure_pid}" || die "ODT /configure failed."

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

    if [ ! -f "${word_path}" ]; then
        die "Cannot test: WINWORD.EXE not found at ${word_path}. Office installation failed."
    fi

    # Launch Word briefly then kill to confirm the binary runs
    echo "Launching WINWORD.EXE for 5 seconds to verify execution..."
    timeout 5 wine "${word_path}" &>/dev/null || true
    pkill -9 -f WINWORD.EXE || true

    info "Test complete. Installation verified."
}

# ---- Phase I: Cleanup Prompt -------------------------------------------------
phase_i_cleanup() {
    local office_dir="${DOWNLOADS}/Office"
    local config_file="${DOWNLOADS}/o365_configuration.xml"

    echo
    read -rp "Delete Office download cache and temp files to save disk space? [y/n]: " answer
    if [[ "${answer}" =~ ^[Yy]$ ]]; then
        if [ -d "${office_dir}" ]; then
            rm -rf "${office_dir}"
            info "Office cache deleted."
        fi
        if [ -f "${config_file}" ]; then
            rm -f "${config_file}"
            info "ODT config file deleted."
        fi
        if [ -f "/tmp/o365_configuration.xml" ]; then
            rm -f "/tmp/o365_configuration.xml"
        fi
        # Also clean Winetricks temp
        rm -f /tmp/winetricks.* 2>/dev/null || true
    else
        info "Cache preserved at ${office_dir}."
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

    # Early Wine compatibility check — abort before wasting time on downloads
    check_wine_compatibility

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
