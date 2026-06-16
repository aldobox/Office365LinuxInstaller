#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Office365 VM Extractor
# Creates a headless Windows 11 VM, runs ODT inside it, extracts Office binaries
# Version: 2.1.2
# =============================================================================

# ---- Configuration ----------------------------------------------------------
VM_NAME="office365-extractor"
VM_DIR="${HOME}/.office365-extractor-vm"
VM_RAM_MB=6144
VM_VCPUS=2
VM_SIZE_GB=25
WIN_USER="OfficeUser"
WIN_PASS="Office365!"
EXTRACTED_DIR="${HOME}/.office365-extracted"
DOWNLOADS="${HOME}/Downloads"
LOGFILE="/tmp/office365_vm_extractor.log"

# Windows 11 Consumer ISO (direct Microsoft CDN link)
# Source: massgrave.dev / Microsoft's official static distribution CDN
# This is a genuine Microsoft file; no login or account required.
# Language: English (en-us) | Edition: Windows 11 Pro (index 3 in the ISO)
# To use a different language, visit https://massgrave.dev/windows_11_links
WIN_ISO_URL="https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66749/26200.6584.250915-1905.25h2_ge_release_svc_refresh_CLIENT_CONSUMER_x64FRE_en-us.iso"
WIN_ISO_NAME="Windows11_Consumer.iso"
# TODO: Compute SHA256 after download: sha256sum "${VM_DIR}/${WIN_ISO_NAME}"
WIN_ISO_SHA256="PLACEHOLDER_UPDATE_AFTER_FIRST_DOWNLOAD"

# ODT URL (from Microsoft). Microsoft does not publish an official SHA256 for this utility.
# Compute it once manually after downloading, then pin the value below.
ODT_URL="https://download.microsoft.com/download/2/7/A/27AF1BE6-DD20-4CB4-B154-EBAB8A7D4A7E/officedeploymenttool_17830-20162.exe"
# TODO: Compute locally with: sha256sum officedeploymenttool_17830-20162.exe
ODT_SHA256="PLACEHOLDER_UPDATE_FROM_ODT_DOWNLOAD"

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

# Guestmount cleanup trap
GUESTMOUNT_ACTIVE=false
cleanup_guestmount() {
    if [[ "$GUESTMOUNT_ACTIVE" == true ]]; then
        local mount_point=/mnt/vm_disk
        sudo guestunmount "$mount_point" 2>/dev/null || true
        GUESTMOUNT_ACTIVE=false
        log "Guestmount cleaned up"
    fi
}
trap 'cleanup_guestmount' EXIT ERR INT TERM

# VM lifecycle helpers (no libvirt)
vm_is_running() {
    local pid_file="${VM_DIR}/qemu.pid"
    if [[ ! -f "$pid_file" ]]; then
        return 1
    fi
    local pid
    pid=$(cat "$pid_file" 2>/dev/null)
    [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

vm_wait_shutdown() {
    local max_wait="${1:-180}"
    local wait_count=0
    while vm_is_running; do
        sleep 30
        wait_count=$((wait_count + 1))
        if [[ $wait_count -gt $max_wait ]]; then
            return 1
        fi
        echo -n "."
    done
    echo
    return 0
}

vm_destroy() {
    local qemu_pid swtpm_pid
    if [[ -f "${VM_DIR}/qemu.pid" ]]; then
        qemu_pid=$(cat "${VM_DIR}/qemu.pid" 2>/dev/null)
        [[ -n "$qemu_pid" ]] && kill -TERM "$qemu_pid" 2>/dev/null || true
        sleep 2
        [[ -n "$qemu_pid" ]] && kill -KILL "$qemu_pid" 2>/dev/null || true
    fi
    if [[ -f "${VM_DIR}/swtpm.pid" ]]; then
        swtpm_pid=$(cat "${VM_DIR}/swtpm.pid" 2>/dev/null)
        [[ -n "$swtpm_pid" ]] && kill -TERM "$swtpm_pid" 2>/dev/null || true
        sleep 1
        [[ -n "$swtpm_pid" ]] && kill -KILL "$swtpm_pid" 2>/dev/null || true
    fi
    rm -f "${VM_DIR}/qemu.pid" "${VM_DIR}/swtpm.pid"
    rm -f "${VM_DIR}/tpm/.lock" "${VM_DIR}/tpm/swtpm-sock"
}

vm_start() {
    local disk_path="${VM_DIR}/${VM_NAME}.qcow2"
    local accel="kvm"
    if [[ ! -r /dev/kvm ]]; then
        accel="tcg"
    fi
    local tpm_dir="${VM_DIR}/tpm"
    rm -f "${tpm_dir}/swtpm-sock" "${tpm_dir}/.lock"
    swtpm socket --tpmstate dir="$tpm_dir" --ctrl type=unixio,path="${tpm_dir}/swtpm-sock" --tpm2 --log level=1 &
    local swtpm_pid=$!
    sleep 1
    if ! kill -0 "$swtpm_pid" 2>/dev/null; then
        die "swtpm failed to start for Stage 2."
    fi
    local original_iso="${VM_DIR}/${WIN_ISO_NAME}"
    local floppy_img="${VM_DIR}/answer_floppy.img"

    # Fallback Strategy C (q35 + OVMF): If SeaBIOS stalls with the Microsoft
    # Consumer ISO, uncomment the block below and comment out the active qemu
    # command. Requires: apt-get install ovmf
    # local ovmf_bios="/usr/share/ovmf/OVMF.fd"
    # nohup qemu-system-x86_64 \
    #     -machine type=q35,accel="$accel" \
    #     -bios "$ovmf_bios" \
    #     -cpu host \
    #     -smp "${VM_VCPUS}" \
    #     -m "${VM_RAM_MB}" \
    #     -drive "file=${disk_path},format=qcow2,if=ide" \
    #     -cdrom "$original_iso" \
    #     -drive "file=${floppy_img},format=raw,if=floppy" \
    #     -boot order=c \
    #     -netdev user,id=net0 \
    #     -device virtio-net-pci,netdev=net0 \
    #     -chardev socket,id=chrtpm,path="${tpm_dir}/swtpm-sock" \
    #     -tpmdev emulator,id=tpm0,chardev=chrtpm \
    #     -device tpm-tis,tpmdev=tpm0 \
    #     -display none \
    #     -serial file:"${VM_DIR}/serial.log" \
    #     >> "${VM_DIR}/qemu.log" 2>&1 &

    nohup qemu-system-x86_64 \
        -machine type=pc,accel="$accel" \
        -cpu host \
        -smp "${VM_VCPUS}" \
        -m "${VM_RAM_MB}" \
        -drive "file=${disk_path},format=qcow2,if=ide" \
        -cdrom "$original_iso" \
        -drive "file=${floppy_img},format=raw,if=floppy" \
        -boot order=c \
        -netdev user,id=net0 \
        -device virtio-net-pci,netdev=net0 \
        -chardev socket,id=chrtpm,path="${tpm_dir}/swtpm-sock" \
        -tpmdev emulator,id=tpm0,chardev=chrtpm \
        -device tpm-tis,tpmdev=tpm0 \
        -display none \
        -serial file:"${VM_DIR}/serial.log" \
        >> "${VM_DIR}/qemu.log" 2>&1 &
    local qemu_pid=$!
    disown "$qemu_pid"
    echo "$qemu_pid" > "${VM_DIR}/qemu.pid"
    echo "$swtpm_pid" > "${VM_DIR}/swtpm.pid"
    info "VM restarted for Stage 2 (PID: $qemu_pid)"
}

# ---- Phase 1: Prerequisites -------------------------------------------------
phase_1_prerequisites() {
    info "Phase 1: Checking prerequisites..."
    log "Phase 1: Prerequisites"

    check_disk_space 45 "VM method (ISO + VM + extraction)"

    # Check KVM
    if ! grep -c -E '(vmx|svm)' /proc/cpuinfo > /dev/null 2>&1; then
        warn "CPU does not support KVM virtualization (no vmx/svm flags). Falling back to TCG."
    fi
    if [[ ! -e /dev/kvm ]]; then
        warn "/dev/kvm not found. Is kvm kernel module loaded? Falling back to TCG."
    fi

    # Check available RAM (7GB free minimum for Win11 VM)
    local avail_ram_kb
    avail_ram_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    if [[ "$avail_ram_kb" -lt 7340032 ]]; then
        warn "Less than 7GB RAM available (${avail_ram_kb} KB)."
        read -rp "Continue anyway? [y/N]: " ans
        [[ "$ans" =~ ^[Yy]$ ]] || die "Aborted."
    fi

    # Check required commands
    for cmd in qemu-system-x86_64 qemu-img swtpm mtools; do
        if ! command -v "$cmd" > /dev/null 2>&1; then
            die "Required command not found: $cmd. Run install.sh with Method 2 first."
        fi
    done
    # Optional commands for Phase 8 extraction (guestmount preferred, qemu-nbd fallback)
    for cmd in guestmount qemu-nbd ntfsfix; do
        if ! command -v "$cmd" > /dev/null 2>&1; then
            warn "Optional command not found: $cmd. Phase 8 extraction may require sudo."
        fi
    done

    log "Phase 1: Prerequisites OK"
}

# ---- Phase 2: Download Windows 11 Consumer ISO --------------------------------
phase_2_download_iso() {
    info "Phase 2: Obtaining Windows 11 Consumer ISO..."
    log "Phase 2: ISO download"

    check_disk_space 8 "Windows 11 ISO download"

    mkdir -p "$VM_DIR"
    local iso_path="${VM_DIR}/${WIN_ISO_NAME}"

    if [[ -s "$iso_path" ]]; then
        info "Windows ISO already present. Verifying..."
        verify_sha256 "$iso_path" "$WIN_ISO_SHA256" "Windows ISO"
        return 0
    fi

    # Remove any stale zero-byte or partial file before download
    rm -f "$iso_path"

    info "Downloading Windows 11 Consumer ISO..."
    info "Source: Microsoft official CDN (via massgrave.dev index)"
    info "URL: ${WIN_ISO_URL}"
    log "Starting ISO download from Microsoft CDN"

    # Download with wget (preferred) or curl, with resume support
    if command -v wget > /dev/null 2>&1; then
        wget --continue --show-progress --tries=3 --timeout=60 \
            -O "$iso_path" "$WIN_ISO_URL" || die "ISO download failed."
    elif command -v curl > /dev/null 2>&1; then
        curl -L -C - --retry 3 --max-time 0 -o "$iso_path" "$WIN_ISO_URL" \
            || die "ISO download failed."
    else
        die "Neither wget nor curl is installed. Cannot download ISO."
    fi

    # Verify minimum size (> 4 GB)
    local size
    size=$(stat -c%s "$iso_path" 2>/dev/null || echo 0)
    if [[ $size -lt 4294967296 ]]; then
        rm -f "$iso_path"
        die "Downloaded ISO is too small (${size} bytes). Expected > 4 GB."
    fi

    verify_sha256 "$iso_path" "$WIN_ISO_SHA256" "Windows ISO"

    log "Phase 2: ISO obtained"
}

# ---- Phase 3: Create answer files + ODT Config -----------------------------
phase_3_answer_file() {
    info "Phase 3: Creating unattended installation files..."
    log "Phase 3: Answer file"

    mkdir -p "${VM_DIR}/autounattend"

    # Office 365 Configuration (NOT 2021 LTSC)
    # User signs in via browser to activate subscription
    cat > "${VM_DIR}/autounattend/o365_config.xml" <<'XMLEOF'
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
</Configuration>
XMLEOF

    # Windows 11 unattended install
    # Uses LabConfig bypasses (TPM, SecureBoot, RAM) in Specialize pass
    # + BypassNRO registry in FirstLogonCommands for local account creation
    cat > "${VM_DIR}/autounattend/autounattend.xml" <<XMLEOF
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <!-- Specialize: bypass Windows 11 hardware requirements -->
  <settings pass="specialize">
    <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <RunSynchronous>
        <RunSynchronousCommand wcm:action="add">
          <Path>reg add HKLM\\SYSTEM\\Setup\\LabConfig /v BypassTPMCheck /t REG_DWORD /d 1 /f</Path>
        </RunSynchronousCommand>
        <RunSynchronousCommand wcm:action="add">
          <Path>reg add HKLM\\SYSTEM\\Setup\\LabConfig /v BypassSecureBootCheck /t REG_DWORD /d 1 /f</Path>
        </RunSynchronousCommand>
        <RunSynchronousCommand wcm:action="add">
          <Path>reg add HKLM\\SYSTEM\\Setup\\LabConfig /v BypassRAMCheck /t REG_DWORD /d 1 /f</Path>
        </RunSynchronousCommand>
      </RunSynchronous>
    </component>
  </settings>

  <!-- windowsPE: Select Windows 11 Pro edition (ImageIndex 3 on Consumer ISO) -->
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <ImageInstall>
        <OSImage>
          <InstallFrom>
            <MetaData wcm:action="add">
              <Key>/IMAGE/INDEX</Key>
              <Value>3</Value>
            </MetaData>
          </InstallFrom>
          <InstallTo>
            <DiskID>0</DiskID>
            <PartitionID>3</PartitionID>
          </InstallTo>
        </OSImage>
      </ImageInstall>
      <UserData>
        <ProductKey>
          <Key>VK7JG-NPHTM-C97JM-9MPGT-3V66T</Key>
          <WillShowUI>Never</WillShowUI>
        </ProductKey>
        <AcceptEula>true</AcceptEula>
      </UserData>
    </component>
  </settings>

  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
      <UserAccounts>
        <LocalAccounts>
          <LocalAccount wcm:action="add">
            <Password>
              <Value>${WIN_PASS}</Value>
              <PlainText>true</PlainText>
            </Password>
            <Description>Office 365 Install User</Description>
            <DisplayName>${WIN_USER}</DisplayName>
            <Group>Administrators</Group>
            <Name>${WIN_USER}</Name>
          </LocalAccount>
        </LocalAccounts>
      </UserAccounts>
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
        <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
        <NetworkLocation>Work</NetworkLocation>
      </OOBE>
      <FirstLogonCommands>
        <!-- Order 1: Bypass Network Requirement for OOBE -->
        <SynchronousCommand wcm:action="add">
          <Order>1</Order>
          <CommandLine>reg add "HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\OOBE" /v BypassNRO /t REG_DWORD /d 1 /f</CommandLine>
          <Description>Allow local account creation without internet</Description>
        </SynchronousCommand>
        <!-- Order 2: Disable Fast Startup so shutdown is clean for guestmount -->
        <SynchronousCommand wcm:action="add">
          <Order>2</Order>
          <CommandLine>powercfg /h off</CommandLine>
          <Description>Disable hibernation / Fast Startup</Description>
        </SynchronousCommand>
        <!-- Order 3: Create ODT install script and register for RunOnce on next boot -->
        <SynchronousCommand wcm:action="add">
          <Order>3</Order>
          <CommandLine>powershell -ExecutionPolicy Bypass -Command "\$ProgressPreference = 'SilentlyContinue'; \$script = @'
\$log = \"C:\\odt_install.log\"
\"[START] ODT install script running\" | Out-File -Append -FilePath \$log
try {
    \"Waiting for network...\" | Out-File -Append -FilePath \$log
    \$retries = 0
    while (-not (Test-Connection -ComputerName \"download.microsoft.com\" -Count 1 -Quiet)) {
        Start-Sleep -Seconds 5
        \$retries++
        if (\$retries -gt 60) { throw \"Network not available after 5 minutes\" }
    }
    \"[OK] Network ready after \$(\$retries * 5) seconds\" | Out-File -Append -FilePath \$log
    Invoke-WebRequest -Uri '${ODT_URL}' -OutFile 'C:\\Users\\${WIN_USER}\\Downloads\\ODT.exe' -UseBasicParsing
    \"[OK] ODT downloaded\" | Out-File -Append -FilePath \$log
    Start-Process -FilePath 'C:\\Users\\${WIN_USER}\\Downloads\\ODT.exe' -ArgumentList '/quiet','/extract:C:\\Users\\${WIN_USER}\\Downloads\\odt' -Wait
    \"[OK] ODT extracted\" | Out-File -Append -FilePath \$log
    Copy-Item -Path 'A:\\o365_config.xml' -Destination 'C:\\Users\\${WIN_USER}\\Downloads\\odt\\config.xml' -Force
    \"[OK] Config copied\" | Out-File -Append -FilePath \$log
    Start-Process -FilePath 'C:\\Users\\${WIN_USER}\\Downloads\\odt\\setup.exe' -ArgumentList '/configure','C:\\Users\\${WIN_USER}\\Downloads\\odt\\config.xml' -Wait
    \"[OK] ODT configure completed\" | Out-File -Append -FilePath \$log
    \"ODT_COMPLETE\" | Out-File -FilePath \"C:\\odt_done.flag\" -Encoding ASCII
    \"[OK] Flag written\" | Out-File -Append -FilePath \$log
} catch {
    \"[ERR] \$_\" | Out-File -Append -FilePath \$log
    \"ODT_FAILED\" | Out-File -FilePath \"C:\\odt_done.flag\" -Encoding ASCII
}
shutdown /s /t 0
'@; Set-Content -Path 'C:\\odt_install.ps1' -Value \$script; New-ItemProperty -Path 'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\RunOnce' -Name 'O365Install' -Value \"powershell -ExecutionPolicy Bypass -File C:\\odt_install.ps1\" -PropertyType String -Force"</CommandLine>
          <Description>Create ODT install script and register for next boot</Description>
        </SynchronousCommand>
        <!-- Order 4: Shutdown after first logon (Stage 1 complete) -->
        <SynchronousCommand wcm:action="add">
          <Order>4</Order>
          <CommandLine>shutdown /s /t 30</CommandLine>
          <Description>Shutdown after Stage 1 setup</Description>
        </SynchronousCommand>
      </FirstLogonCommands>
    </component>
  </settings>
</unattend>
XMLEOF

    log "Phase 3: Answer files created"
}

# ---- Phase 4: Create floppy image with answer files -------------------------
# Windows Setup searches for autounattend.xml on removable drives (A:).
# We create a small floppy image with autounattend.xml + o365_config.xml
# and mount it alongside the original unmodified Windows ISO.
# This avoids rebuilding the ISO (which corrupts UEFI boot on Win11).
phase_4_build_iso() {
    info "Phase 4: Creating answer-file floppy image..."
    log "Phase 4: Build floppy"

    local floppy_img="${VM_DIR}/answer_floppy.img"

    if [[ -f "$floppy_img" ]]; then
        info "Floppy image already present."
        return 0
    fi

    check_disk_space 1 "Answer-file floppy image"

    # Create 1.44 MB FAT12 floppy image using mtools (no root needed)
    dd if=/dev/zero of="$floppy_img" bs=1M count=1 status=none || die "Failed to create floppy image"

    local mtoolsrc="${VM_DIR}/mtoolsrc"
    cat > "$mtoolsrc" <<EOF
drive a: file="${floppy_img}"
EOF
    export MTOOLSRC="$mtoolsrc"

    mformat a: || die "mformat failed — mtools not installed?"
    mcopy "${VM_DIR}/autounattend/autounattend.xml" a:/autounattend.xml || die "Failed to copy autounattend.xml to floppy"
    mcopy "${VM_DIR}/autounattend/o365_config.xml" a:/o365_config.xml || die "Failed to copy o365_config.xml to floppy"

    info "Floppy image created with answer files."
    log "Phase 4: Floppy image built"
}

# ---- Phase 5: Create VM -----------------------------------------------------
phase_5_create_vm() {
    info "Phase 5: Creating VM..."
    log "Phase 5: Create VM"

    check_disk_space 30 "VM disk creation"

    local disk_path="${VM_DIR}/${VM_NAME}.qcow2"
    local custom_iso="${VM_DIR}/windows_custom.iso"

    if [[ -f "$disk_path" ]]; then
        info "VM disk already exists. Skipping creation."
        return 0
    fi

    # Create disk
    qemu-img create -f qcow2 "$disk_path" "${VM_SIZE_GB}G"

    # Check KVM access — prefer KVM, fallback to TCG (slower but works everywhere)
    local accel="kvm"
    if [[ ! -r /dev/kvm ]]; then
        warn "KVM not accessible (user not in kvm group). Falling back to TCG emulation."
        warn "This will be significantly slower. Add yourself to the kvm group and re-login for speedup."
        accel="tcg"
    fi

    # Start TPM emulator (socket-based, no libvirt required)
    local tpm_dir="${VM_DIR}/tpm"
    mkdir -p "$tpm_dir"
    rm -f "${tpm_dir}/swtpm-sock" "${tpm_dir}/.lock"
    swtpm socket --tpmstate dir="$tpm_dir" --ctrl type=unixio,path="${tpm_dir}/swtpm-sock" --tpm2 --log level=1 &
    local swtpm_pid=$!
    sleep 1
    if ! kill -0 "$swtpm_pid" 2>/dev/null; then
        die "swtpm failed to start. TPM emulation required for Windows 11."
    fi

    # Start VM directly with QEMU (no libvirt)
    # Using SeaBIOS (legacy BIOS) — UEFI boot fails with Microsoft Consumer ISOs.
    # Windows 11 installs fine on BIOS with LabConfig bypasses (in autounattend.xml).
    # Fallback Strategy C (q35 + OVMF): If SeaBIOS stalls with the Microsoft
    # Consumer ISO, uncomment the block below and comment out the active qemu
    # command. Requires: apt-get install ovmf
    # local ovmf_bios="/usr/share/ovmf/OVMF.fd"
    # nohup qemu-system-x86_64 \
    #     -machine type=q35,accel="$accel" \
    #     -bios "$ovmf_bios" \
    #     -cpu host \
    #     -smp "${VM_VCPUS}" \
    #     -m "${VM_RAM_MB}" \
    #     -drive "file=${disk_path},format=qcow2,if=ide" \
    #     -cdrom "$original_iso" \
    #     -drive "file=${floppy_img},format=raw,if=floppy" \
    #     -boot order=d \
    #     -netdev user,id=net0 \
    #     -device virtio-net-pci,netdev=net0 \
    #     -chardev socket,id=chrtpm,path="${tpm_dir}/swtpm-sock" \
    #     -tpmdev emulator,id=tpm0,chardev=chrtpm \
    #     -device tpm-tis,tpmdev=tpm0 \
    #     -display none \
    #     -serial file:"${VM_DIR}/serial.log" \
    #     > "${VM_DIR}/qemu.log" 2>&1 &

    local original_iso="${VM_DIR}/${WIN_ISO_NAME}"
    local floppy_img="${VM_DIR}/answer_floppy.img"

    nohup qemu-system-x86_64 \
        -machine type=pc,accel="$accel" \
        -cpu host \
        -smp "${VM_VCPUS}" \
        -m "${VM_RAM_MB}" \
        -drive "file=${disk_path},format=qcow2,if=ide" \
        -cdrom "$original_iso" \
        -drive "file=${floppy_img},format=raw,if=floppy" \
        -boot order=d \
        -netdev user,id=net0 \
        -device virtio-net-pci,netdev=net0 \
        -chardev socket,id=chrtpm,path="${tpm_dir}/swtpm-sock" \
        -tpmdev emulator,id=tpm0,chardev=chrtpm \
        -device tpm-tis,tpmdev=tpm0 \
        -display none \
        -serial file:"${VM_DIR}/serial.log" \
        > "${VM_DIR}/qemu.log" 2>&1 &
    local qemu_pid=$!
    disown "$qemu_pid"

    # Save PID for lifecycle management
    echo "$qemu_pid" > "${VM_DIR}/qemu.pid"
    echo "$swtpm_pid" > "${VM_DIR}/swtpm.pid"

    info "VM started (PID: $qemu_pid, TPM PID: $swtpm_pid)"
    info "Serial log: ${VM_DIR}/serial.log"
    log "Phase 5: VM created (QEMU PID: $qemu_pid, accel: $accel)"
}

# ---- Phase 6: Wait for Stage 1 (Windows Install) ---------------------------
phase_6_wait_stage1() {
    info "Phase 6: Waiting for Windows installation (Stage 1)..."
    info "This will take 20-30 minutes. Do not interrupt."
    log "Phase 6: Stage 1 wait"

    if ! vm_wait_shutdown 180; then
        vm_destroy
        die "VM Stage 1 took too long (90 min). Windows install may have failed."
    fi
    info "Stage 1 complete. Windows installed."
    log "Phase 6: Stage 1 complete"
}

# ---- Phase 6.5: Snapshot Windows Base ---------------------------------------
phase_6_5_snapshot() {
    info "Phase 6.5: Creating snapshot of fresh Windows installation..."
    log "Phase 6.5: Snapshot"

    local disk_path="${VM_DIR}/${VM_NAME}.qcow2"

    # Delete old snapshot if exists (from previous failed run)
    qemu-img snapshot -d windows_base "$disk_path" 2>/dev/null || true

    qemu-img snapshot -c windows_base "$disk_path"
    info "Snapshot 'windows_base' created. You can revert with: qemu-img snapshot -a windows_base ${disk_path}"

    log "Phase 6.5: Snapshot created"
}

# ---- Phase 7: Start Stage 2 (ODT Install) ----------------------------------
phase_7_start_stage2() {
    local disk_path="${VM_DIR}/${VM_NAME}.qcow2"
    info "Phase 7: Starting Stage 2 (ODT installation)..."
    log "Phase 7: Stage 2 start"

    vm_start || die "Failed to start VM for Stage 2"

    local wait_count=0
    local max_wait=120  # 120 * 30s = 60 minutes max for ODT

    while vm_is_running; do
        sleep 30
        wait_count=$((wait_count + 1))
        if [[ $wait_count -gt $max_wait ]]; then
            warn "VM Stage 2 took too long. ODT may have failed or stalled."
            echo
            echo "Options:"
            echo "  [1] Retry Stage 2 (revert snapshot and restart)"
            echo "  [2] Inspect VM (keep running for debugging)"
            echo "  [3] Abort and cleanup"
            read -rp "Choice [1/2/3]: " choice
            case "$choice" in
                1)
                    info "Reverting to windows_base snapshot and restarting..."
                    vm_destroy
                    qemu-img snapshot -a windows_base "$disk_path"
                    vm_start || die "Failed to restart VM for Stage 2"
                    wait_count=0
                    continue
                    ;;
                2)
                    info "VM is still running. Serial log: ${VM_DIR}/serial.log"
                    read -rp "Press Enter when done debugging..."
                    continue
                    ;;
                3)
                    die "Aborted by user."
                    ;;
            esac
        fi
        echo -n "."
    done
    echo

    info "Stage 2 complete. VM shut down."
    log "Phase 7: Stage 2 complete"
}

# ---- Phase 8: Extract Office Binaries --------------------------------------
phase_8_extract() {
    info "Phase 8: Extracting Office binaries from VM disk..."
    log "Phase 8: Extract"

    check_disk_space 5 "Office extraction"

    local disk_path="${VM_DIR}/${VM_NAME}.qcow2"
    local mount_point=/mnt/vm_disk

    sudo mkdir -p "$mount_point"

    # Try guestmount first
    if sudo guestmount -a "$disk_path" -i --rw "$mount_point" 2>/dev/null; then
        GUESTMOUNT_ACTIVE=true
        info "Mounted VM disk via guestmount."
    else
        warn "guestmount failed. Trying qemu-nbd + ntfsfix fallback..."
        local nbd_dev="/dev/nbd0"
        sudo modprobe nbd max_part=8 || die "nbd kernel module not available"
        sudo qemu-nbd -c "$nbd_dev" "$disk_path" || die "qemu-nbd failed"
        # Find largest NTFS partition
        local part
        part=$(sudo fdisk -l "$nbd_dev" 2>/dev/null | grep -i ntfs | sort -k3 -n | tail -1 | awk '{print $1}')
        if [[ -z "$part" ]]; then
            sudo qemu-nbd -d "$nbd_dev" 2>/dev/null || true
            die "No NTFS partition found in VM disk."
        fi
        sudo ntfsfix "$part" || warn "ntfsfix reported issues"
        sudo mount -o rw,remove_hiberfile "$part" "$mount_point" || die "Mount failed even after ntfsfix"
        GUESTMOUNT_ACTIVE=true
        # Update trap to handle nbd disconnect
        trap 'sudo umount "'$mount_point'" 2>/dev/null || true; sudo qemu-nbd -d "'$nbd_dev'" 2>/dev/null || true; exit' EXIT ERR INT TERM
    fi

    # Check for ODT completion flag
    if [[ -f "${mount_point}/odt_done.flag" ]]; then
        local flag_content
        flag_content=$(cat "${mount_point}/odt_done.flag")
        if [[ "$flag_content" == "ODT_COMPLETE" ]]; then
            info "ODT completion flag verified."
        else
            cleanup_guestmount
            die "ODT reported failure (flag: ${flag_content}). Check C:\\odt_install.log inside VM."
        fi
    else
        warn "ODT completion flag not found. ODT may have failed or VM was interrupted."
        read -rp "Continue extraction anyway? [y/N]: " ans
        [[ "$ans" =~ ^[Yy]$ ]] || { cleanup_guestmount; die "Aborted."; }
    fi

    # Extract Office directory
    local office_src="${mount_point}/Program Files/Microsoft Office"
    if [[ -d "$office_src" ]]; then
        mkdir -p "$EXTRACTED_DIR"
        cp -r "$office_src" "${EXTRACTED_DIR}/Microsoft Office"
        info "Office binaries extracted to ${EXTRACTED_DIR}/Microsoft Office"
    else
        # Try alternative path
        office_src="${mount_point}/Program Files (x86)/Microsoft Office"
        if [[ -d "$office_src" ]]; then
            mkdir -p "$EXTRACTED_DIR"
            cp -r "$office_src" "${EXTRACTED_DIR}/Microsoft Office"
            info "Office binaries extracted (x86) to ${EXTRACTED_DIR}/Microsoft Office"
        else
            cleanup_guestmount
            die "Office installation not found in VM. ODT may have failed."
        fi
    fi

    # Verify
    if [[ ! -f "${EXTRACTED_DIR}/Microsoft Office/root/Office16/WINWORD.EXE" ]]; then
        cleanup_guestmount
        die "Extraction incomplete. WINWORD.EXE not found."
    fi

    log "Phase 8: Extraction complete"
}

# ---- Phase 9: Cleanup VM --------------------------------------------------
phase_9_cleanup_vm() {
    info "Phase 9: Cleaning up VM..."
    log "Phase 9: Cleanup"

    vm_destroy
    rm -rf "$VM_DIR"

    log "Phase 9: Cleanup complete"
}

# ---- Phase 10: Final Report ------------------------------------------------
phase_10_report() {
    echo
    echo "========================================"
    echo " VM Extraction Complete!"
    echo "========================================"
    echo
    echo "Office binaries available at:"
    echo "  ${EXTRACTED_DIR}/Microsoft Office/"
    echo
    echo "You can now run install.sh (Method 1) to install these"
    echo "binaries into your Wine prefix."
    echo
    log "Extraction complete"
}

# ---- Main ------------------------------------------------------------------
main() {
    > "$LOGFILE"
    log "VM Extractor v2.1.2 started"

    phase_1_prerequisites
    phase_2_download_iso
    phase_3_answer_file
    phase_4_build_iso
    phase_5_create_vm
    phase_6_wait_stage1
    phase_6_5_snapshot
    phase_7_start_stage2
    phase_8_extract
    phase_9_cleanup_vm
    phase_10_report
}

main "$@"
