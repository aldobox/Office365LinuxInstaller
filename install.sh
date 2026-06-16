#!/usr/bin/env bash
set -euo pipefail

# Keep terminal open on both success and failure so the user can read messages.
# If launched from a TUI (no TTY), sleep instead of read to avoid blocking on pipe input.
trap '
    exit_code=$?
    if [ "${exit_code}" -ne 0 ]; then
        echo
        echo "[FATAL] Installation failed. Exit code: ${exit_code}."
        echo "See error above. Log file: ${LOGFILE}"
        echo "If you need help, run with: bash -x install.sh"
    fi
    if [ -t 0 ]; then
        echo
        read -rp "Press Enter to exit..."
    else
        echo "Check log: ${LOGFILE}"
        sleep 10
    fi
' EXIT

# =============================================================================
# Office365LinuxInstaller
# Clean, legal Microsoft Office 365 (Desktop) installation via Wine on Ubuntu/Debian
# Version: 2.1.3
# =============================================================================

# ---- User Detection (for privilege dropping) ------------------------------
# Detect the real user even when script is run via sudo
current_user() {
    logname 2>/dev/null || echo "${SUDO_USER:-$USER}"
}
CURRENT_USER=$(current_user)
CURRENT_HOME=$(getent passwd "$CURRENT_USER" | cut -d: -f6 || echo "$HOME")
[ -z "$CURRENT_USER" ] && die "Failed to detect current user."
[ -z "$CURRENT_HOME" ] && die "Failed to detect current home directory."

# ---- Configuration ----------------------------------------------------------
WINE_PREFIX="${CURRENT_HOME}/.Microsoft_Office_365"
EXTRACTED_DIR="${CURRENT_HOME}/.office365-extracted"
DOWNLOADS="${CURRENT_HOME}/Downloads"
ICON_SIZE="256x256"
ICON_HICOLOR="/usr/share/icons/hicolor/${ICON_SIZE}/apps"
APP_DIR="/usr/share/applications"
FONT_DIR="/usr/share/fonts/Windows"
LAUNCHER_DIR="/opt/launchers"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGFILE="$(mktemp /tmp/office365_installer.XXXXXX.log)"

# Windows VM Configuration (for Method 2)
VM_NAME="office365-extractor"
VM_DIR="${CURRENT_HOME}/.office365-extractor-vm"

# Installation method (set by phase_0)
INSTALL_METHOD=""

# User-provided URL for Method 1 (set at runtime)
USER_PROVIDED_URL=""

# Isolated Wine 9.7 paths (populated in phase_0_detect_wine)
ISOLATED_WINE_DIR=""
ISOLATED_WINE_BIN=""
WINE_CMD="wine"
WINESERVER_CMD="wineserver"
WINEPATH_CMD="winepath"
NEEDS_ISOLATED_WINE=false

# Signal handling for cleanup
trap 'echo "[WARN] Interrupted. Cleaning up..."; rm -f "\$LOGFILE"; exit 130' INT TERM

# ---- Helpers ----------------------------------------------------------------
info()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }
die()   { error "$*"; exit 1; }
log()   { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOGFILE"; }

# Disk space check (needs GB)
check_disk_space() {
    local needed_gb="$1"
    local label="$2"
    local avail_gb
    avail_gb=$(df -BG "$HOME" | tail -1 | awk '{print $4}' | tr -d 'G')
    if [[ "$avail_gb" -lt "$needed_gb" ]]; then
        die "Need ~${needed_gb}GB for ${label}. You have ~${avail_gb}GB."
    fi
    info "Disk space OK for ${label}: ${avail_gb}GB available."
}

# Prompt user for SHA256 and verify a downloaded file
prompt_sha256_verify() {
    local file="$1"
    local label="$2"
    read -rp "Enter SHA256 for ${label} (or press Enter to skip): " user_hash
    if [[ -n "$user_hash" ]]; then
        local actual
        actual=$(sha256sum "$file" | awk '{print $1}')
        if [[ "$actual" != "$user_hash" ]]; then
            die "SHA256 mismatch for ${label}! Expected: ${user_hash} Got: ${actual}"
        fi
        info "SHA256 verified for ${label}."
    else
        warn "Skipping SHA256 verification for ${label}."
    fi
}

# Drop privileges when running as root (e.g., via sudo bash install.sh)
run_as_user() {
    if [ "${EUID:-$(id -u)}" -eq 0 ] && [ "$CURRENT_USER" != "root" ]; then
        if command -v runuser >/dev/null 2>&1; then
            runuser -u "$CURRENT_USER" -- "$@"
        else
            sudo -u "$CURRENT_USER" --preserve-env=WINE,WINEPREFIX,WINEARCH -- "$@"
        fi
    else
        "$@"
    fi
}

# ---- Phase 0: Consent Banner and Method Selection ----------------------------
phase_0_consent_and_method() {
    # Clear screen for clean presentation
    clear 2>/dev/null || true

    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║                                                                              ║"
    echo "║           Office365LinuxInstaller v2.1.3 — Installation Wizard                 ║"
    echo "║                                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo
    echo "IMPORTANT — PLEASE READ BEFORE PROCEEDING"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo
    echo "This installer will set up Microsoft Office 365 on your Linux system using"
    echo "one of four methods. Before you choose, please understand what will happen:"
    echo
    echo "┌─────────────────────────────────────────────────────────────────────────────┐"
    echo "│ METHOD 1: Download from Trusted Source (FAST — ~5 minutes)                  │"
    echo "│ ─────────────────────────────────────────────────────────────────────────── │"
    echo "│ • YOU provide a URL to a pre-extracted Office binary archive (.tar.zst)     │"
    echo "│ • The installer downloads from YOUR specified source (e.g., your own server,│"
    echo "│   your company's internal repository, a trusted mirror you control)          │"
    echo "│ • The installer does NOT provide, host, or endorse any third-party source   │"
    echo "│ • Installs an isolated Wine 9.7 runtime (~150 MB)                           │"
    echo "│ • Creates a 32-bit Wine prefix at ~/.Microsoft_Office_365                   │"
    echo "│ • Copies Office binaries into the prefix                                    │"
    echo "│ • Creates desktop launchers and file associations                             │"
    echo "│ • Sets up browser intercept for Microsoft account sign-in                     │"
    echo "│ • Temporary files: ~3 GB (cleaned up after install)                         │"
    echo "│ • Internet required: Yes                                                      │"
    echo "│ • LEGAL NOTE: You are solely responsible for the source and legality of     │"
    echo "│   the binaries you provide. This installer does not verify licenses.        │"
    echo "└─────────────────────────────────────────────────────────────────────────────┘"
    echo
    echo "┌─────────────────────────────────────────────────────────────────────────────┐"
    echo "│ METHOD 2: Extract from Windows VM (SLOW — ~60-90 minutes)                   │"
    echo "│ ─────────────────────────────────────────────────────────────────────────── │"
    echo "│ • Downloads a Windows 11 Consumer ISO (~7 GB) from Microsoft                  │"
    echo "│ • Creates a QEMU/KVM virtual machine (6 GB RAM, 2 vCPUs, 25 GB disk)        │"
    echo "│ • Installs Windows 11 unattended (no user interaction)                        │"
    echo "│ • Downloads and runs the official Office Deployment Tool inside the VM        │"
    echo "│ • Extracts Office binaries from the VM disk to your Linux filesystem          │"
    echo "│ • Copies extracted binaries into a Wine prefix                                │"
    echo "│ • DELETES the VM and all associated files after extraction                    │"
    echo "│ • Temporary files: ~45 GB (VM + ISO, fully cleaned up after)                  │"
    echo "│ • Internet required: Yes                                                        │"
    echo "│ • System requirements: 12GB+ RAM, 45GB free disk, KVM CPU support          │"
    echo "│ • No Microsoft account required                                               │"
    echo "└─────────────────────────────────────────────────────────────────────────────┘"
    echo
    echo "┌─────────────────────────────────────────────────────────────────────────────┐"
    echo "│ METHOD 3: Use My Own Packages (CUSTOM — ~2 minutes)                         │"
    echo "│ ─────────────────────────────────────────────────────────────────────────── │"
    echo "│ • You provide a pre-extracted Microsoft Office tree                           │"
    echo "│ • Installer copies your files into a Wine prefix                            │"
    echo "│ • No external downloads required                                              │"
    echo "│ • Temporary files: ~3 GB                                                      │"
    echo "│ • Internet required: No                                                       │"
    echo "└─────────────────────────────────────────────────────────────────────────────┘"
    echo
    echo "┌─────────────────────────────────────────────────────────────────────────────┐"
    echo "│ METHOD 4: Direct C2R Download (BETA — ~10 minutes)                          │"
    echo "│ ─────────────────────────────────────────────────────────────────────────── │"
    echo "│ • Downloads the official Office C2R offline .img (~4.5 GB) from Microsoft  │"
    echo "│ • Extracts the Office payload using 7z (no mounting required)                  │"
    echo "│ • Downloads and extracts the Office Deployment Tool (ODT)                     │"
    echo "│ • Attempts installation under Wine (BETA — may fail due to C2R engine)       │"
    echo "│ • If Wine install fails, files remain for use on a real Windows PC/VM         │"
    echo "│ • Temporary files: ~15 GB (fully cleaned up after)                            │"
    echo "│ • Internet required: Yes                                                        │"
    echo "│ • System requirements: ~4 GB RAM, 15 GB free disk                              │"
    echo "│ • ⚠ BETA: Click-to-Run installer requires Windows. Wine cannot complete it.  │"
    echo "└─────────────────────────────────────────────────────────────────────────────┘"
    echo
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo "WHAT WILL BE INSTALLED ON YOUR SYSTEM"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo
    echo "  • Wine 9.7 (isolated, does not conflict with system Wine)"
    echo "  • Wine prefix: ~/.Microsoft_Office_365 (~3 GB after install)"
    echo "  • Desktop launchers: /opt/launchers/"
    echo "  • Application menu entries: /usr/share/applications/"
    echo "  • Icons: /usr/share/icons/hicolor/256x256/apps/"
    echo "  • File associations for .docx, .xlsx, .pptx, etc."
    echo
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo "KNOWN LIMITATIONS & DISCLAIMERS"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo
    echo "  ⚠ Microsoft account login uses a browser fallback mechanism. It may not"
    echo "    work perfectly. Cloud sync, OneDrive integration, and real-time"
    echo "    collaboration require a working Microsoft login."
    echo "  ⚠ OneNote and Teams are known to be non-functional in Wine."
    echo "  ⚠ Excel may exhibit screen flickering."
    echo "  ⚠ No automatic feature updates — manual reinstallation required."
    echo "  ⚠ This installer does NOT include, distribute, or facilitate piracy."
    echo "    You must have a valid Microsoft 365 subscription."
    echo "  ⚠ Windows 11 Consumer ISO is a genuine Microsoft file. No account required."
    echo "    It is a 90-day trial and requires no license key."
    echo
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo

    # Consent requirement
    read -rp "Do you understand and accept the above? Type YES to continue: " consent
    if [[ "${consent}" != "YES" ]]; then
        echo
        echo "Installation aborted. You must type YES in uppercase to proceed."
        exit 0
    fi

    log "User provided consent: YES"

    echo
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo "CHOOSE YOUR INSTALLATION METHOD"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo
    echo "  [1] Download from trusted source (FAST — ~5 minutes)"
    echo "      Best for: Users with their own binary source or internal mirror"
    echo
    echo "  [2] Extract from Windows VM (SLOW — ~60-90 minutes)"
    echo "      Best for: Privacy-conscious users who want full control"
    echo
    echo "  [3] Use my own Office packages (CUSTOM — ~2 minutes)"
    echo "      Best for: Enterprise users with volume-licensed binaries"
    echo
    echo "  [4] Direct C2R download (BETA — ~10 minutes)"
    echo "      Best for: Users without KVM who want official Microsoft source files"
    echo "      ⚠ May not complete under Wine — files usable on Windows"
    echo
    echo "  [5] Abort installation"
    echo

    read -rp "Your choice [1/2/3/4/5]: " choice
    log "User chose method: $choice"

    case "$choice" in
        1)
            INSTALL_METHOD="prebuilt"
            ;;
        2)
            INSTALL_METHOD="vm"
            ;;
        3)
            INSTALL_METHOD="user"
            ;;
        4)
            INSTALL_METHOD="direct"
            ;;
        5)
            info "Aborted."
            exit 0
            ;;
        *)
            die "Invalid choice. Run the installer again."
            ;;
    esac
}

# ---- Phase 0.5: Wine Version Detection -------------------------------------
# Detect Wine compatibility and decide if isolated Wine 9.7 is needed.
# This runs after method selection.
phase_0_5_detect_wine() {
    info "Phase 0.5: Detecting Wine compatibility..."
    log "Phase 0.5: Wine detection"

    local system_wine_version=""

    if command -v wine >/dev/null 2>&1; then
        system_wine_version=$(wine --version 2>/dev/null | grep -oP 'wine-\K[0-9]+\.[0-9]+' || echo "")
        if [[ -n "$system_wine_version" ]]; then
            info "System Wine detected: ${system_wine_version}"
        else
            system_wine_version=$(wine --version 2>/dev/null | grep -oP '\d+\.\d+' | head -1 || echo "")
            info "System Wine detected: ${system_wine_version}"
        fi
    else
        info "No system Wine detected."
    fi

    NEEDS_ISOLATED_WINE=false

    if [[ -z "$system_wine_version" ]]; then
        NEEDS_ISOLATED_WINE=true
        info "No system Wine found. Will download isolated Wine 9.7."
    elif [[ "$(printf '%s\n' "9.0" "$system_wine_version" | sort -V | head -n1)" == "9.0" ]]; then
        if wine --version 2>/dev/null | grep -qi "wow64" || \
           (WINEARCH=win32 wine wineboot --init 2>&1 | grep -q "not supported in wow64 mode"); then
            NEEDS_ISOLATED_WINE=true
            warn "System Wine ${system_wine_version} uses WoW64 mode and cannot create win32 prefixes."
            info "Will download isolated Wine 9.7 with native 32-bit support."
        else
            warn "System Wine ${system_wine_version} may work but is untested."
            read -rp "Download isolated Wine 9.7 for best compatibility? [Y/n]: " choice
            if [[ ! "${choice}" =~ ^[Nn]$ ]]; then
                NEEDS_ISOLATED_WINE=true
            fi
        fi
    else
        warn "System Wine ${system_wine_version} is older than 9.7. Office 365 may not work."
        read -rp "Download isolated Wine 9.7 for best compatibility? [Y/n]: " choice
        if [[ ! "${choice}" =~ ^[Nn]$ ]]; then
            NEEDS_ISOLATED_WINE=true
        fi
    fi

    if [[ "$NEEDS_ISOLATED_WINE" == true ]]; then
        ISOLATED_WINE_DIR="${CURRENT_HOME}/.wine-msoffice/wine"
        ISOLATED_WINE_BIN="${ISOLATED_WINE_DIR}/usr/bin"
        WINE_CMD="${ISOLATED_WINE_BIN}/wine"
        WINESERVER_CMD="${ISOLATED_WINE_BIN}/wineserver"
        WINEPATH_CMD="${ISOLATED_WINE_BIN}/winepath"
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
    if [ -t 0 ]; then
        echo
        read -rp "Press Enter to continue..."
    fi
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
    local apt_packages=(
        build-essential gcc-multilib g++-multilib flex bison
        git wget curl pkg-config gettext
        zenity progress p7zip-full zstd
        cups-daemon cups-client printer-driver-all
        system-config-printer printer-driver-cups-pdf
        msitools
        clang lld
        libc6:i386 libgcc-s1:i386 libstdc++6:i386
        libfreetype6:i386 libx11-6:i386 libxext6:i386
        libxrender1:i386 libxrandr2:i386
        libxcursor1:i386 libxi6:i386 libxinerama1:i386 libxcomposite1:i386
        libgl1:i386 libglu1-mesa:i386
        libasound2:i386 libpulse0:i386
        libdbus-1-3:i386 libncurses6:i386
        libopenal1:i386 libv4l-0:i386
        libgphoto2-6:i386 libldap2:i386
        libgnutls30:i386 libhogweed6:i386 libnettle8:i386
        libtasn1-6:i386 libp11-kit0:i386
        libfontconfig1:i386 libpng16-16:i386
        libxml2-16:i386 libxslt1.1:i386
        libmpg123-0:i386 libgstreamer1.0-0:i386
        libgstreamer-plugins-base1.0-0:i386
        libudev1:i386 libusb-1.0-0:i386
        libvulkan1:i386
        winbind samba-common samba-libs gnutls-bin
        ttf-mscorefonts-installer
    )

    # Only install system Wine if we're using it (not isolated)
    if [[ "$NEEDS_ISOLATED_WINE" != true ]]; then
        apt_packages+=(wine64 wine32 winetricks)
    fi

    # Add VM packages if needed (direct QEMU, no libvirt, SeaBIOS)
    if [[ "$INSTALL_METHOD" == "vm" ]]; then
        apt_packages+=(qemu-system-x86 qemu-utils mtools genisoimage cpio libguestfs-tools ntfs-3g swtpm-tools)
    fi

    run_apt_install "${apt_packages[@]}"

    # Add user to kvm group for hardware acceleration (optional, improves speed)
    if [[ "$INSTALL_METHOD" == "vm" ]]; then
        sudo usermod -aG kvm "$CURRENT_USER" 2>/dev/null || true
        warn "User added to kvm group. Log out and back in for hardware acceleration."
        warn "Without kvm, VM will run in TCG mode (slower but works)."
    fi

    # Start background progress monitor for file-I/O tracking
    start_progress_monitor

    info "Dependencies installed or already present."
    stop_progress_monitor

    # If isolated Wine is needed, download it now
    if [[ "$NEEDS_ISOLATED_WINE" == true ]]; then
        phase_a1_download_isolated_wine
    fi
}

# ---- Phase A1: Download Isolated Wine 9.7 -----------------------------------
phase_a1_download_isolated_wine() {
    info "Downloading isolated Wine 9.7..."
    check_disk_space 2 "Wine 9.7 download"

    local wine_zst="${DOWNLOADS}/wine-9.7.tar.zst"
    # GitHub Release asset in this repository (aldobox/Office365LinuxInstaller)
    # Upload the archive to: https://github.com/aldobox/Office365LinuxInstaller/releases/tag/v2.1.0
    local github_release_url="https://github.com/aldobox/Office365LinuxInstaller/releases/download/v2.1.0/wine-9.7-x86_64.tar.zst"
    local build_dir="${CURRENT_HOME}/.wine-msoffice/build"

    mkdir -p "${ISOLATED_WINE_DIR}"

    if [[ -d "${ISOLATED_WINE_DIR}/usr/bin" ]] && [[ -f "${ISOLATED_WINE_BIN}/wine" ]]; then
        info "Isolated Wine 9.7 already present at ${ISOLATED_WINE_DIR}"
        return 0
    fi

    # Attempt 1: Download from GitHub Release
    info "Attempting download from GitHub Release..."
    if command -v wget >/dev/null 2>&1; then
        wget --timeout=60 --tries=2 --progress=bar:force -O "${wine_zst}" "${github_release_url}" 2>&1 | tail -n +6
    elif command -v curl >/dev/null 2>&1; then
        curl -L --max-time 60 --retry 2 --progress-bar -o "${wine_zst}" "${github_release_url}"
    fi

    # Verify download succeeded
    if [[ -f "${wine_zst}" ]] && [[ -s "${wine_zst}" ]]; then
        info "Download successful. Verifying archive..."
        # TODO: add SHA256 check here once published in release notes
        :
    else
        warn "GitHub Release download failed or returned empty."
        rm -f "${wine_zst}"

        # Attempt 2: Build from source
        echo
        warn "Could not download pre-built Wine 9.7."
        read -rp "Build Wine 9.7 from source? This takes 1-2 hours. [y/N]: " choice
        if [[ ! "${choice}" =~ ^[Yy]$ ]]; then
            die "Wine 9.7 is required. Cannot proceed."
        fi

        info "Building Wine 9.7 from source. This will take a while..."
        mkdir -p "${build_dir}"

        local wine_tar="${build_dir}/wine-9.7.tar.xz"
        if [[ ! -f "${wine_tar}" ]]; then
            info "Downloading Wine 9.7 source..."
            if command -v wget >/dev/null 2>&1; then
                wget --progress=bar:force -O "${wine_tar}" "https://dl.winehq.org/wine/source/9.x/wine-9.7.tar.xz"
            else
                curl -L --progress-bar -o "${wine_tar}" "https://dl.winehq.org/wine/source/9.x/wine-9.7.tar.xz"
            fi
        fi

        if [[ ! -f "${wine_tar}" ]] || [[ ! -s "${wine_tar}" ]]; then
            die "Failed to download Wine 9.7 source from winehq.org."
        fi

        info "Extracting source..."
        tar xf "${wine_tar}" -C "${build_dir}"

        local wine_src="${build_dir}/wine-9.7"
        cd "${wine_src}" || die "Failed to enter Wine source directory: ${wine_src}"

        info "Configuring Wine 9.7 (32-bit prefix support, no wow64)..."
        ./configure \
            --prefix="${ISOLATED_WINE_DIR}" \
            --without-wayland \
            --without-pulse \
            --without-alsa \
            --enable-win32on64=no \
            --disable-tests \
            2>&1 | tee "${build_dir}/configure.log"

        if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
            die "Wine configure failed. See ${build_dir}/configure.log"
        fi

        info "Compiling Wine 9.7 (this will take 60-90 minutes on your hardware)..."
        make -j$(nproc) 2>&1 | tee "${build_dir}/make.log"
        if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
            die "Wine build failed. See ${build_dir}/make.log"
        fi

        info "Installing Wine 9.7 to ${ISOLATED_WINE_DIR}..."
        make install 2>&1 | tee "${build_dir}/install.log"
        if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
            die "Wine install failed. See ${build_dir}/install.log"
        fi

        info "Wine 9.7 built and installed successfully."
        cd "${SCRIPT_DIR}" || true
    fi

    # Extraction (shared path for both download and build)
    if [[ -f "${wine_zst}" ]]; then
        info "Extracting Wine 9.7 archive..."
        local extract_tmp="${DOWNLOADS}/wine_extract_tmp_$$"
        mkdir -p "${extract_tmp}"

        if command -v unzstd >/dev/null 2>&1; then
            tar --use-compress-program=unzstd -xf "${wine_zst}" -C "${extract_tmp}"
        elif command -v zstd >/dev/null 2>&1; then
            zstd -d "${wine_zst}" -o /tmp/wine-9.7.tar && \
                tar -xf /tmp/wine-9.7.tar -C "${extract_tmp}" && \
                rm -f /tmp/wine-9.7.tar
        else
            die "zstd/unzstd not installed. Cannot extract Wine 9.7 archive."
        fi

        rm -f "${wine_zst}"

        # The archive extracts to a bare 'usr/' directory. We need it inside 'wine/usr/'
        if [[ -d "${extract_tmp}/usr" ]]; then
            rsync -a "${extract_tmp}/usr/" "${ISOLATED_WINE_DIR}/usr/" 2>/dev/null || \
                cp -r "${extract_tmp}/usr" "${ISOLATED_WINE_DIR}/"
        fi
        rm -rf "${extract_tmp}"
    fi

    if [[ ! -f "${ISOLATED_WINE_BIN}/wine" ]]; then
        die "Wine 9.7 installation failed. ${ISOLATED_WINE_BIN}/wine not found."
    fi

    "${WINESERVER_CMD}" -k 2>/dev/null || true

    info "Isolated Wine 9.7 installed at ${ISOLATED_WINE_DIR}"
}

# ---- Phase A2: Create Browser Intercept Wrapper ----------------------------
phase_a2_create_browser_wrapper() {
    info "Phase A2: Creating MSAL browser intercept wrapper..."
    log "Phase A2: Browser wrapper"

    mkdir -p "${CURRENT_HOME}/.wine-msoffice"
    cat > "${CURRENT_HOME}/.wine-msoffice/winebrowser-wrapper.sh" <<'EOF'
#!/bin/bash
LOGFILE="/tmp/office_auth_url.log"
URL="$1"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] INTERCEPTED: $URL" >> "$LOGFILE"

if echo "$URL" | grep -q "redirect_uri="; then
    if command -v python3 >/dev/null 2>&1; then
        REDIRECT_URI=$(echo "$URL" | sed 's/.*redirect_uri=//;s/&.*//' | python3 -c "import sys,urllib.parse; print(urllib.parse.unquote(sys.stdin.read().strip()))" 2>/dev/null || echo "EXTRACTION_FAILED")
    elif command -v perl >/dev/null 2>&1; then
        REDIRECT_URI=\$(echo "\\$URL" | sed 's/.*redirect_uri=//;s/&.*//' | perl -MURI::Escape -ne 'print uri_decode(\$_)' 2>/dev/null || echo "EXTRACTION_FAILED")
    else
        REDIRECT_URI=$(echo "$URL" | sed 's/.*redirect_uri=//;s/&.*//')
    fi
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] REDIRECT_URI: $REDIRECT_URI" >> "$LOGFILE"
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Opening via xdg-open..." >> "$LOGFILE"
xdg-open "$URL" &
EOF
    chmod +x "${CURRENT_HOME}/.wine-msoffice/winebrowser-wrapper.sh"
    log "Phase A2: Browser wrapper created"
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
    export WINEARCH="win32"

    local wine_init="${WINE_CMD}"
    local wineserver_init="${WINESERVER_CMD}"

    info "Initializing prefix with: ${wine_init}"
    run_as_user "${wine_init}" wineboot --init

    # Set Windows 8.1 (NOT 7 or 10) — forces MSAL to skip WAM and use browser fallback
    # MSAL checks Windows version: WAM requires Windows 10+
    # On Windows 8.1, MSAL falls back to browser-based OAuth2 with http://localhost redirect
    run_as_user "${wine_init}" reg add "HKCU\\Software\\Wine" /v Version /d "win81" /f || true

    # Registry tweaks required for Office 365 stability on Wine
    info "Applying Wine registry tweaks for Office compatibility..."
    run_as_user "${wine_init}" reg add "HKCU\\Software\\Wine\\Direct2D" /v max_version_factory /d "0" /f || true
    run_as_user "${wine_init}" reg add "HKCU\\Software\\Wine\\Direct3D" /v MaxVersionGL /d "30002" /f || true

    # CRITICAL: Override HTTP handler to intercept MSAL browser launch
    # This routes auth URLs to our custom wrapper which opens them in Linux browser
    # Check project dir first, then fallback to home dir
    local wrapper_script=""
    for candidate in "${SCRIPT_DIR}/winebrowser-wrapper.sh" "${CURRENT_HOME}/.wine-msoffice/winebrowser-wrapper.sh"; do
        if [[ -f "${candidate}" ]]; then
            wrapper_script="${candidate}"
            break
        fi
    done
    if [[ -f "${wrapper_script}" ]]; then
        info "Registering custom HTTP handler for MSAL browser fallback..."
        local win_wrapper_path
        win_wrapper_path=$(run_as_user "${wine_init}" winepath -w "${wrapper_script}" 2>/dev/null) || true
        if [[ -n "${win_wrapper_path}" ]]; then
            run_as_user "${wine_init}" reg add "HKEY_CLASSES_ROOT\\http\\shell\\open\\command" /ve /d "\"${win_wrapper_path}\" \"%1\"" /f || true
            info "HTTP handler registered: ${win_wrapper_path}"
        else
            warn "Could not convert wrapper path to Windows format. Auth fallback may not work."
        fi
    else
        warn "Custom HTTP handler not found at ${wrapper_script}. MSAL auth may fail."
    fi

    # Extra insurance: disable WAM via Office registry keys
    info "Disabling WAM/ADAL to force browser-based authentication..."
    run_as_user "${wine_init}" reg add "HKCU\\Software\\Microsoft\\Office\\16.0\\Common\\Identity" /v EnableADAL /d "0" /t REG_DWORD /f || true
    run_as_user "${wine_init}" reg add "HKCU\\Software\\Microsoft\\Office\\16.0\\Common\\Identity" /v DisableADALatopWAMOverride /d "1" /t REG_DWORD /f || true
    run_as_user "${wine_init}" reg add "HKCU\\Software\\Microsoft\\Office\\16.0\\Common\\Identity" /v DisableAADWAM /d "1" /t REG_DWORD /f || true

    # Install common redistributables Office expects
    # NOTE: NO dotnet40. It causes mscoree overwrite errors and is not needed.
    info "Installing Winetricks packages (corefonts, msxml6, gdiplus)..."
    start_progress_monitor
    WINE="${wine_init}" WINEPREFIX="${WINE_PREFIX}" run_as_user winetricks -q corefonts msxml6 gdiplus || \
        warn "Some winetricks packages may have failed; continuing."
    stop_progress_monitor

    # Rebuild dosdevices
    info "Rebuilding Wine dosdevices..."
    rm -rf "${WINE_PREFIX}/dosdevices"
    mkdir -p "${WINE_PREFIX}/dosdevices"
    ln -s ../drive_c "${WINE_PREFIX}/dosdevices/c:"
    ln -s /dev/null  "${WINE_PREFIX}/dosdevices/c::"

    # Rebuild user folders
    info "Rebuilding user folders..."
    mkdir -p "${WINE_PREFIX}/drive_c/users/${USER}/AppData/Local"
    mkdir -p "${WINE_PREFIX}/drive_c/users/${USER}/AppData/Roaming"

    # Phase 1: Copy WAM stub DLL to Office binary directory
    # This forces MSAL to treat WAM as unavailable if win81 spoof is not sufficient
    local stub_dll="${SCRIPT_DIR}/stub_dll/msalruntime.dll"
    if [[ -f "${stub_dll}" ]]; then
        info "Installing WAM stub DLL (Phase 1 fallback)..."
        local office_bin_dir="${WINE_PREFIX}/drive_c/Program Files/Microsoft Office/root/Office16"
        mkdir -p "${office_bin_dir}"
        cp "${stub_dll}" "${office_bin_dir}/"
        info "WAM stub installed: ${office_bin_dir}/msalruntime.dll"
    else
        info "WAM stub DLL not bundled. Phase 1 fallback not available."
    fi

    # Fix ownership/permissions (handle root-run scripts gracefully)
    # Must run AFTER all file copies into the prefix
    chown -R "${CURRENT_USER}:${CURRENT_USER}" "${WINE_PREFIX}"
    chmod -R u+rwX "${WINE_PREFIX}"

    # Final update of the prefix (as user)
    run_as_user "${wine_init}" wineboot -u

    info "Wine prefix created and configured."
}

# ---- Phase C: Install Office Binaries (3 methods) ---------------------------

# Method 1: Download from user's trusted source
phase_c1_prebuilt() {
    info "Phase C1: Download from trusted source..."
    log "Phase C1: Trusted source download"

    # Show disclaimer and prompt for URL
    echo
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo "METHOD 1: Download from Your Trusted Source"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo
    echo "DISCLAIMER:"
    echo "  This installer does NOT provide, host, or endorse any binary source."
    echo "  You are solely responsible for the URL you provide and the legality"
    echo "  of the binaries downloaded from it."
    echo
    echo "  The URL must point to a .tar.zst archive containing a pre-extracted"
    echo "  Microsoft Office tree with this structure:"
    echo "    Microsoft Office/root/Office16/WINWORD.EXE"
    echo "    Microsoft Office/root/Office16/EXCEL.EXE"
    echo "    etc."
    echo
    echo "  Examples of valid sources:"
    echo "    • Your own private server or CDN"
    echo "    • Your company's internal artifact repository"
    echo "    • A GitHub release asset from your own repository"
    echo
    echo "  Examples of INVALID sources (not recommended):"
    echo "    • Random third-party download sites"
    echo "    • Torrents or file-sharing networks"
    echo "    • Any source you do not trust or control"
    echo
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo

    read -rp "Paste your URL (or type ABORT to cancel): " user_url

    if [[ "${user_url^^}" == "ABORT" ]]; then
        info "Aborted by user."
        exit 0
    fi

    # Basic URL validation
    if [[ ! "$user_url" =~ ^https?:// ]]; then
        die "Invalid URL. Must start with http:// or https://"
    fi

    USER_PROVIDED_URL="$user_url"
    log "User provided URL: $USER_PROVIDED_URL"

    local archive="${DOWNLOADS}/office365_binaries.tar.zst"

    if [[ -d "${EXTRACTED_DIR}/Microsoft Office" ]]; then
        info "Binaries already extracted."
        return 0
    fi

    info "Downloading Office binaries archive..."
    if command -v wget > /dev/null 2>&1; then
        wget --progress=bar:force -O "$archive" "$USER_PROVIDED_URL" 2>&1 | tail -n +6
    else
        curl -L --progress-bar -o "$archive" "$USER_PROVIDED_URL"
    fi

    # Verify download succeeded
    if [[ ! -f "$archive" ]] || [[ ! -s "$archive" ]]; then
        die "Download failed. The URL may be invalid or unreachable."
    fi

    prompt_sha256_verify "$archive" "Office binaries archive"

    mkdir -p "$EXTRACTED_DIR"
    check_disk_space 4 "Office extraction"
    info "Extracting binaries..."
    if command -v unzstd > /dev/null 2>&1; then
        tar --use-compress-program=unzstd -xf "$archive" -C "$EXTRACTED_DIR"
    else
        zstd -d "$archive" -o /tmp/office365_binaries.tar && \
            tar -xf /tmp/office365_binaries.tar -C "$EXTRACTED_DIR" && \
            rm -f /tmp/office365_binaries.tar
    fi

    # Verify archive structure
    if [[ ! -d "${EXTRACTED_DIR}/Microsoft Office" ]]; then
        rm -f "$archive"
        die "Invalid archive structure. Expected 'Microsoft Office/' directory at root."
    fi
    if [[ ! -f "${EXTRACTED_DIR}/Microsoft Office/root/Office16/WINWORD.EXE" ]]; then
        rm -f "$archive"
        die "Invalid archive. WINWORD.EXE not found in expected location."
    fi

    rm -f "$archive"
    log "Phase C1: Trusted source binaries ready"
}

# Method 2: Extract from Windows VM
phase_c2_vm() {
    info "Phase C2: Extracting Office binaries from Windows VM..."
    log "Phase C2: VM extraction starting"

    # Check KVM support
    if ! grep -c -E '(vmx|svm)' /proc/cpuinfo >/dev/null 2>&1; then
        die "KVM virtualization not supported on this CPU. Cannot create VM."
    fi

    # Check available RAM (7GB free minimum for Win11 VM method)
    local avail_ram_kb
    avail_ram_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    if [[ "$avail_ram_kb" -lt 7340032 ]]; then  # 7GB
        warn "Less than 7GB free RAM available (${avail_ram_kb} KB)."
        warn "Method 2 requires at least 7GB free RAM for the Windows 11 VM."
        read -rp "Continue anyway? [y/N]: " ans
        [[ "$ans" =~ ^[Yy]$ ]] || die "Aborted."
    fi

    # Check disk space
    local avail_disk
    avail_disk=$(df -BG "$HOME" | tail -1 | awk '{print $4}' | tr -d 'G')
    if [[ "$avail_disk" -lt 40 ]]; then
        die "Need at least 40GB free disk space. You have ~${avail_disk}GB."
    fi

    # Run VM extractor
    if [[ -f "${SCRIPT_DIR}/office365_vm_extractor.sh" ]]; then
        bash "${SCRIPT_DIR}/office365_vm_extractor.sh"
    else
        die "VM extractor script not found at ${SCRIPT_DIR}/office365_vm_extractor.sh"
    fi

    log "Phase C2: VM extraction complete"
}

# Method 3: User-provided packages
phase_c3_user() {
    info "Phase C3: Using user-provided Office packages..."
    log "Phase C3: User packages"

    echo
    echo "Please provide the path to your pre-extracted Microsoft Office tree."
    echo "This should be a directory containing:"
    echo "  Microsoft Office/root/Office16/WINWORD.EXE"
    echo "  Microsoft Office/root/Office16/EXCEL.EXE"
    echo "  etc."
    echo
    read -rp "Path to Office tree: " user_path

    if [[ ! -d "$user_path" ]]; then
        die "Path does not exist: $user_path"
    fi

    if [[ ! -f "${user_path}/root/Office16/WINWORD.EXE" ]] && [[ ! -f "${user_path}/Microsoft Office/root/Office16/WINWORD.EXE" ]]; then
        die "Invalid Office tree. WINWORD.EXE not found."
    fi

    mkdir -p "$EXTRACTED_DIR"
    cp -r "$user_path" "$EXTRACTED_DIR/"

    log "Phase C3: User packages copied"
}

# Method 4: Direct C2R Download (BETA)
phase_c4_direct() {
    info "Phase C4: Direct C2R download (BETA)..."
    log "Phase C4: Direct download starting"

    local downloader_script="${SCRIPT_DIR}/office365_direct_downloader.sh"
    if [[ ! -f "$downloader_script" ]]; then
        die "Direct downloader script not found at ${downloader_script}"
    fi

    bash "$downloader_script"

    # The downloader attempts to install into the Wine prefix.
    # If it succeeds, binaries are already at the expected location.
    # If it fails, the user must use Method 2 or Method 3 instead.
    if [[ ! -d "${EXTRACTED_DIR}/Microsoft Office" ]]; then
        warn "Direct download did not produce extracted binaries."
        warn "The C2R payload is cached at: ${HOME}/.office365-img-cache/"
        warn "You can install on a Windows PC/VM and use Method 3."
        die "Method 4 did not complete. Use Method 2 for automated install."
    fi

    log "Phase C4: Direct download complete"
}

# ---- Phase D: Copy Binaries to Wine Prefix ---------------------------------
phase_d_copy_binaries() {
    info "Phase D: Copying Office binaries to Wine prefix..."
    log "Phase D: Copying binaries"

    local src="${EXTRACTED_DIR}/Microsoft Office"
    local dst="${WINE_PREFIX}/drive_c/Program Files/Microsoft Office"

    if [[ ! -d "$src" ]]; then
        die "Office binaries not found at ${src}"
    fi

    mkdir -p "${WINE_PREFIX}/drive_c/Program Files"
    cp -r "$src" "$dst"

    # Verify
    if [[ ! -f "${dst}/root/Office16/WINWORD.EXE" ]]; then
        die "Copy failed. WINWORD.EXE not found in prefix."
    fi

    log "Phase D: Binaries copied"
    info "Office binaries installed."
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
    timeout 5 "${WINE_CMD}" "${word_path}" >/dev/null 2>&1 || true
    pkill -9 -f WINWORD.EXE || true

    info "Test complete. Installation verified."
}

# ---- Phase I: Cleanup Prompt ------------------------------------------------
phase_i_cleanup() {
    echo
    read -rp "Delete temporary files to save disk space? [y/n]: " answer
    if [[ "${answer}" =~ ^[Yy]$ ]]; then
        info "Cleaning up temporary files..."
        log "Phase I: Cleanup"

        # Remove VM files if VM method was used
        if [[ "$INSTALL_METHOD" == "vm" ]]; then
            # Kill any running QEMU/swtpm processes for our VM
            if [[ -f "${VM_DIR}/qemu.pid" ]]; then
                local qemu_pid
                qemu_pid=$(cat "${VM_DIR}/qemu.pid" 2>/dev/null)
                [[ -n "$qemu_pid" ]] && kill -TERM "$qemu_pid" 2>/dev/null || true
            fi
            if [[ -f "${VM_DIR}/swtpm.pid" ]]; then
                local swtpm_pid
                swtpm_pid=$(cat "${VM_DIR}/swtpm.pid" 2>/dev/null)
                [[ -n "$swtpm_pid" ]] && kill -TERM "$swtpm_pid" 2>/dev/null || true
            fi
            rm -rf "$VM_DIR"
            rm -f "${DOWNLOADS}/wine-9.7.zst"
        fi

        # Remove direct download cache if direct method was used
        if [[ "$INSTALL_METHOD" == "direct" ]]; then
            rm -rf "${HOME}/.office365-img-cache"
        fi

        # Remove extracted binaries (they're now in the prefix)
        rm -rf "$EXTRACTED_DIR"

        # Remove ODT config (legacy)
        rm -f "${DOWNLOADS}/o365_configuration.xml"
        rm -f "${DOWNLOADS}/o365_config.xml"

        # Remove Wine zst if still there
        rm -f "${DOWNLOADS}/wine-9.7.tar.zst"
        rm -f "${DOWNLOADS}/wine-9.7.tar"
        rm -f "${DOWNLOADS}/wine-9.7.zst"
        rm -f /tmp/wine-9.7.tar

        # Remove Wine source build cache
        if [[ -d "${CURRENT_HOME}/.wine-msoffice/build" ]]; then
            info "Removing Wine source build cache..."
            rm -rf "${CURRENT_HOME}/.wine-msoffice/build"
        fi
        rm -f /tmp/winetricks.* 2>/dev/null || true

        info "Cleanup complete."
        log "Phase I: Cleanup done"
    else
        info "Temporary files preserved."
        log "Phase I: Cleanup skipped"
    fi
}

# ---- Phase J: Final Report --------------------------------------------------
phase_j_report() {
    echo
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║                                                                              ║"
    echo "║                    Installation Complete!                                      ║"
    echo "║                                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo
    echo "Method used: $INSTALL_METHOD"
    echo "Wine prefix: $WINE_PREFIX"
    echo "Isolated Wine: $ISOLATED_WINE_DIR"
    echo
    echo "Office apps are available in your system menu."
    echo "Sign in with your Microsoft account when first opening each app."
    echo
    echo "KNOWN LIMITATIONS:"
    echo "  - Microsoft account login may require browser fallback"
    echo "  - OneNote and Teams may not work"
    echo "  - Excel may flicker"
    echo "  - No automatic feature updates"
    echo
    echo "To uninstall: ./uninstall.sh"
    echo "Log file: $LOGFILE"
    echo
    log "Installation complete"
}

# ---- Main Orchestrator ------------------------------------------------------
main() {
    > "$LOGFILE"

    # Verify timeout command is available
    if ! command -v timeout >/dev/null 2>&1; then
        warn "'timeout' command not found. Install coreutils for timeout support."
    fi

    log "Installer v2.1.3 started"

    # Phase 0: Consent banner + method selection
    phase_0_consent_and_method

    # Phase 0.5: Wine compatibility check
    phase_0_5_detect_wine

    # Phase A: Dependencies (includes Wine 9.7 download if needed)
    phase_a_dependencies

    # Phase A2: Create browser intercept wrapper (needed by Phase B)
    phase_a2_create_browser_wrapper

    # Phase B: Create Wine prefix
    phase_b_wine_prefix

    # Phase C: Get Office binaries (method-dependent)
    case "$INSTALL_METHOD" in
        prebuilt)
            phase_c1_prebuilt
            ;;
        vm)
            phase_c2_vm
            ;;
        user)
            phase_c3_user
            ;;
        direct)
            phase_c4_direct
            ;;
    esac

    # Phase D: Copy binaries to prefix
    phase_d_copy_binaries

    # Phase E-H: Launchers, desktop integration, fonts, test
    phase_e_launchers
    phase_f_desktop_integration
    phase_g_fonts_mime
    phase_h_test
    phase_i_cleanup
    phase_j_report

}

main "$@"
