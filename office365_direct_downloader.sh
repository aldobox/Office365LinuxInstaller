#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Office365 Direct Downloader (Method 4 — BETA)
# Downloads official Office C2R offline .img from Microsoft CDN,
# extracts it, and attempts installation under Wine.
#
# WARNING: The Office Click-to-Run installer (setup.exe /configure)
# requires Windows services (COM+, BITS) that Wine does not emulate.
# This method may fail at the configure step. If it does, the extracted
# files remain available for installation on a real Windows system.
#
# Source: https://massgrave.dev/office_c2r_links
# Version: 2.1.1
# =============================================================================

# ---- Configuration ----------------------------------------------------------
IMG_CACHE_DIR="${HOME}/.office365-img-cache"
EXTRACTED_DIR="${HOME}/.office365-extracted"
LOGFILE="/tmp/office365_direct_downloader.log"

# Office Deployment Tool (ODT) — from Microsoft
ODT_URL="https://download.microsoft.com/download/2/7/A/27AF1BE6-DD20-4CB4-B154-EBAB8A7D4A7E/officedeploymenttool_17830-20162.exe"
# TODO: Compute SHA256 after first download
ODT_SHA256="PLACEHOLDER_UPDATE_AFTER_FIRST_DOWNLOAD"

# Office C2R Offline IMG — O365ProPlusRetail en-us
# Microsoft CDN URL. To change language, swap the /en-us/ segment.
# See https://massgrave.dev/office_c2r_links for other languages.
OFFICE_IMG_URL="https://officecdn.microsoft.com/db/492350f6-3a01-4f97-b9c0-c7c6ddf67d60/media/en-us/O365ProPlusRetail.img"
OFFICE_IMG_NAME="O365ProPlusRetail.img"
# TODO: Compute SHA256 after first download
OFFICE_IMG_SHA256="PLACEHOLDER_UPDATE_AFTER_FIRST_DOWNLOAD"

# ---- Helpers ----------------------------------------------------------------
info() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }
die() { error "$*"; exit 1; }
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOGFILE"; }

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

# SHA256 verification
verify_sha256() {
    local file="$1"
    local expected="$2"
    local label="$3"
    if [[ "$expected" == "PLACEHOLDER"* ]] || [[ -z "$expected" ]]; then
        warn "SHA256 for ${label} is not set. Skipping verification."
        return 0
    fi
    info "Verifying SHA256 for ${label}..."
    local actual
    actual=$(sha256sum "$file" | awk '{print $1}')
    if [[ "$actual" != "$expected" ]]; then
        die "SHA256 mismatch for ${label}! Expected: ${expected} Got: ${actual}"
    fi
    info "SHA256 verified for ${label}."
}

# ---- Phase 1: Prerequisites -------------------------------------------------
phase_1_prerequisites() {
    info "Phase 1: Checking prerequisites..."
    log "Phase 1: Prerequisites"

    check_disk_space 15 "direct download method (.img + extraction)"

    # Check required commands
    for cmd in wget curl 7z wine; do
        if ! command -v "$cmd" > /dev/null 2>&1; then
            warn "Required command not found: $cmd. Some steps may fail."
        fi
    done

    log "Phase 1: Prerequisites OK"
}

# ---- Phase 2: Download ODT --------------------------------------------------
phase_2_download_odt() {
    info "Phase 2: Downloading Office Deployment Tool..."
    log "Phase 2: ODT download"

    mkdir -p "$IMG_CACHE_DIR"
    local odt_path="${IMG_CACHE_DIR}/ODT.exe"

    if [[ -s "$odt_path" ]]; then
        info "ODT already present. Verifying..."
        verify_sha256 "$odt_path" "$ODT_SHA256" "ODT"
        return 0
    fi

    rm -f "$odt_path"
    info "Downloading ODT from Microsoft..."
    log "ODT URL: ${ODT_URL}"

    if command -v wget > /dev/null 2>&1; then
        wget --show-progress --tries=3 --timeout=60 \
            -O "$odt_path" "$ODT_URL" || die "ODT download failed."
    elif command -v curl > /dev/null 2>&1; then
        curl -L --retry 3 --max-time 0 -o "$odt_path" "$ODT_URL" \
            || die "ODT download failed."
    else
        die "Neither wget nor curl is installed."
    fi

    verify_sha256 "$odt_path" "$ODT_SHA256" "ODT"
    log "Phase 2: ODT obtained"
}

# ---- Phase 3: Extract ODT ---------------------------------------------------
phase_3_extract_odt() {
    info "Phase 3: Extracting Office Deployment Tool..."
    log "Phase 3: ODT extraction"

    local odt_path="${IMG_CACHE_DIR}/ODT.exe"
    local odt_extract_dir="${IMG_CACHE_DIR}/odt"

    if [[ -f "${odt_extract_dir}/setup.exe" ]]; then
        info "ODT already extracted."
        return 0
    fi

    mkdir -p "$odt_extract_dir"

    # ODT.exe is a self-extracting cabinet. Try 7z first (no Wine needed).
    # 7z may emit warnings about reparse streams; we ignore exit code and verify
    # the presence of setup.exe afterward.
    if command -v 7z > /dev/null 2>&1; then
        info "Extracting ODT with 7z..."
        7z x "$odt_path" -o"$odt_extract_dir" -y 2>&1 || \
            warn "7z reported warnings (often benign for self-extracting cabinets)."
    else
        # Fallback: use Wine to run the self-extractor
        warn "7z not found. Falling back to Wine self-extraction."
        if ! command -v wine > /dev/null 2>&1; then
            die "Neither 7z nor Wine is available. Cannot extract ODT."
        fi
        wine "$odt_path" /extract:"$odt_extract_dir" /quiet || \
            die "Wine ODT extraction failed."
    fi

    if [[ ! -f "${odt_extract_dir}/setup.exe" ]]; then
        die "ODT extraction did not produce setup.exe"
    fi

    log "Phase 3: ODT extracted"
}

# ---- Phase 4: Download Office C2R IMG ---------------------------------------
phase_4_download_img() {
    info "Phase 4: Downloading Office C2R offline image..."
    log "Phase 4: IMG download"

    local img_path="${IMG_CACHE_DIR}/${OFFICE_IMG_NAME}"

    if [[ -s "$img_path" ]]; then
        info "Office IMG already present. Verifying..."
        verify_sha256 "$img_path" "$OFFICE_IMG_SHA256" "Office IMG"
        return 0
    fi

    rm -f "$img_path"
    info "Downloading Office C2R .img from Microsoft CDN..."
    info "This file is ~4.5 GB and may take 10-30 minutes."
    info "URL: ${OFFICE_IMG_URL}"
    log "IMG URL: ${OFFICE_IMG_URL}"

    if command -v wget > /dev/null 2>&1; then
        wget --continue --show-progress --tries=3 --timeout=60 \
            -O "$img_path" "$OFFICE_IMG_URL" || die "IMG download failed."
    elif command -v curl > /dev/null 2>&1; then
        curl -L -C - --retry 3 --max-time 0 -o "$img_path" "$OFFICE_IMG_URL" \
            || die "IMG download failed."
    else
        die "Neither wget nor curl is installed."
    fi

    # Verify minimum size (> 3 GB)
    local size
    size=$(stat -c%s "$img_path" 2>/dev/null || echo 0)
    if [[ $size -lt 3221225472 ]]; then
        rm -f "$img_path"
        die "Downloaded IMG is too small (${size} bytes). Expected > 3 GB."
    fi

    verify_sha256 "$img_path" "$OFFICE_IMG_SHA256" "Office IMG"
    log "Phase 4: IMG obtained"
}

# ---- Phase 5: Extract Office IMG ------------------------------------------
phase_5_extract_img() {
    info "Phase 5: Extracting Office C2R image..."
    log "Phase 5: IMG extraction"

    local img_path="${IMG_CACHE_DIR}/${OFFICE_IMG_NAME}"
    local office_extract_dir="${IMG_CACHE_DIR}/office"

    if [[ -d "${office_extract_dir}/Office" ]]; then
        info "Office payload already extracted."
        return 0
    fi

    mkdir -p "$office_extract_dir"

    if ! command -v 7z > /dev/null 2>&1; then
        die "7z is required to extract the Office .img. Install p7zip-full."
    fi

    info "Extracting .img with 7z (this may take a few minutes)..."
    7z x "$img_path" -o"$office_extract_dir" -y || \
        die "7z extraction of Office IMG failed."

    if [[ ! -d "${office_extract_dir}/Office/Data" ]]; then
        die "Extracted IMG does not contain Office/Data/ directory."
    fi

    log "Phase 5: IMG extracted"
}

# ---- Phase 6: Generate ODT Config ------------------------------------------
phase_6_generate_config() {
    info "Phase 6: Generating ODT configuration..."
    log "Phase 6: Config generation"

    local odt_extract_dir="${IMG_CACHE_DIR}/odt"
    local office_extract_dir="${IMG_CACHE_DIR}/office"

    # Convert Linux path to Wine Z: drive path for SourcePath
    local wine_sourcepath
    wine_sourcepath="Z:$(echo "$office_extract_dir" | sed 's|/|\\|g')"

    cat > "${odt_extract_dir}/o365_config.xml" <<XMLEOF
<Configuration>
  <Add OfficeClientEdition="32" Channel="Current">
    <Product ID="O365ProPlusRetail">
      <Language ID="en-us" />
    </Product>
  </Add>
  <Display Level="None" AcceptEULA="TRUE" />
  <Property Name="AUTOACTIVATE" Value="0" />
  <Property Name="FORCEAPPSHUTDOWN" Value="TRUE" />
  <Property Name="SharedComputerLicensing" Value="0" />
  <Property Name="PinIconsToTaskbar" Value="FALSE" />
  <Property Name="SourcePath" Value="${wine_sourcepath}" />
</Configuration>
XMLEOF

    log "Phase 6: Config generated"
}

# ---- Phase 7: Attempt Wine Configure (BETA) ---------------------------------
phase_7_attempt_configure() {
    info "Phase 7: Attempting Office installation under Wine (BETA)..."
    log "Phase 7: Wine configure attempt"

    local odt_extract_dir="${IMG_CACHE_DIR}/odt"
    local setup_exe="${odt_extract_dir}/setup.exe"
    local config_xml="${odt_extract_dir}/o365_config.xml"

    if [[ ! -f "$setup_exe" ]]; then
        die "setup.exe not found at ${setup_exe}"
    fi
    if [[ ! -f "$config_xml" ]]; then
        die "config.xml not found at ${config_xml}"
    fi

    info ""
    info "╔══════════════════════════════════════════════════════════════════════════════╗"
    info "║  BETA WARNING                                                                ║"
    info "║  ──────────────────────────────────────────────────────────────────────────  ║"
    info "║  The Office Click-to-Run installer requires Windows services (COM+, BITS)     ║"
    info "║  that Wine does not emulate. This step may hang, crash, or fail.            ║"
    info "║                                                                              ║"
    info "║  If it fails, the extracted files remain at:                                  ║"
    info "║    ${IMG_CACHE_DIR}/office/"
    info "║                                                                              ║"
    info "║  You can install from these files on a real Windows PC or VM, then use       ║"
    info "║  Method 3 ('Use my own packages') to copy the installed tree to Linux.       ║"
    info "╚══════════════════════════════════════════════════════════════════════════════╝"
    info ""

    # Ensure Wine prefix exists
    export WINEPREFIX="${HOME}/.Microsoft_Office_365"
    export WINEARCH=win32
    if [[ ! -d "$WINEPREFIX" ]]; then
        info "Creating Wine prefix..."
        wineboot --init || warn "wineboot init had issues, continuing..."
    fi

    info "Running: wine setup.exe /configure config.xml"
    info "This may take 20-40 minutes. Do not interrupt."
    log "Starting wine setup.exe /configure"

    # Run configure with timeout (2 hours) in background so we can poll
    local configure_log="/tmp/office365_wine_configure.log"
    timeout 7200 wine "$setup_exe" /configure "$config_xml" > "$configure_log" 2>&1 &
    local configure_pid=$!

    # Poll for completion with progress dots
    local poll_count=0
    local max_poll=120  # 120 * 30s = 60 minutes
    while kill -0 "$configure_pid" 2>/dev/null; do
        sleep 30
        poll_count=$((poll_count + 1))
        if [[ $poll_count -gt $max_poll ]]; then
            warn "Configure step running for >60 minutes. It may be stuck."
            read -rp "Continue waiting? [Y/n/abort]: " ans
            if [[ "${ans,,}" == "abort" ]]; then
                kill "$configure_pid" 2>/dev/null || true
                die "Aborted by user."
            elif [[ "${ans,,}" == "n" ]]; then
                break
            fi
            poll_count=0
        fi
        echo -n "."
    done
    echo

    wait "$configure_pid" || true
    local configure_exit=$?

    if [[ $configure_exit -eq 0 ]]; then
        info "Configure completed successfully (unexpected but welcome!)."
        log "Phase 7: Configure SUCCESS"
    elif [[ $configure_exit -eq 124 ]]; then
        warn "Configure timed out after 2 hours."
        log "Phase 7: Configure TIMEOUT"
    else
        warn "Configure failed or exited with code ${configure_exit}."
        log "Phase 7: Configure FAILED (exit ${configure_exit})"
    fi

    # Check if WINWORD.EXE was created — this is the definitive sign of success
    # (The directory may exist from a prior WAM stub install, so we check the EXE)
    if [[ -f "${WINEPREFIX}/drive_c/Program Files/Microsoft Office/root/Office16/WINWORD.EXE" ]]; then
        info "Office binaries detected in Wine prefix! WINWORD.EXE present."
        info "You may be able to proceed with Phase D (Copy Binaries)."
        log "Phase 7: WINWORD.EXE found in prefix — genuine success"
        return 0
    fi

    # If we get here, configure did not produce usable binaries
    info ""
    info "============================================================"
    info " BETA INSTALLATION DID NOT COMPLETE"
    info "============================================================"
    info ""
    info "The Office Click-to-Run engine could not install under Wine."
    info "This is a known limitation — not a bug in this script."
    info ""
    info "NEXT STEPS:"
    info "  1. Install Office on a real Windows PC or VM using these files:"
    info "       ${IMG_CACHE_DIR}/office/"
    info "  2. Copy the installed 'Microsoft Office' folder to this Linux machine"
    info "  3. Re-run this installer and choose Method 3 ('Use my own packages')"
    info ""
    info "Alternatively, use Method 2 (VM extractor) for fully automated install."
    info ""

    log "Phase 7: Configure did not produce WINWORD.EXE"
    return 1
}

# ---- Phase 8: Report -------------------------------------------------------
phase_8_report() {
    info ""
    info "============================================================"
    info " DIRECT DOWNLOADER REPORT"
    info "============================================================"
    info ""
    info "Cache directory: ${IMG_CACHE_DIR}"
    info "  - ODT:        ${IMG_CACHE_DIR}/odt/setup.exe"
    info "  - Office IMG: ${IMG_CACHE_DIR}/office/"
    info ""
    if [[ -d "${HOME}/.Microsoft_Office_365/drive_c/Program Files/Microsoft Office/root/Office16" ]]; then
        info "Wine prefix:   ${HOME}/.Microsoft_Office_365"
        info "Status:        Binaries present — proceed with launcher setup"
    else
        info "Status:        No binaries in Wine prefix (configure step failed)"
        info ""
        info "To use these files on Windows:"
        info "  1. Copy ${IMG_CACHE_DIR}/office/ to a Windows PC"
        info "  2. Run setup.exe /configure o365_config.xml from the ODT folder"
        info ""
        info "Then bring the installed tree back to Linux for Method 3."
    fi
    info ""
    log "Phase 8: Report complete"
}

# ---- Main -------------------------------------------------------------------
main() {
    log "=== Office365 Direct Downloader (Method 4 BETA) started ==="

    phase_1_prerequisites
    phase_2_download_odt
    phase_3_extract_odt
    phase_4_download_img
    phase_5_extract_img
    phase_6_generate_config
    phase_7_attempt_configure || true  # Don't die on expected failure
    phase_8_report

    log "=== Office365 Direct Downloader finished ==="
}

main "$@"
