#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Office365 VM Extractor
# Creates a headless Windows 10 VM, runs ODT inside it, extracts Office binaries
# Version: 1.1.000
# =============================================================================

# ---- Configuration ----------------------------------------------------------
VM_NAME="office365-extractor"
VM_DIR="${HOME}/.office365-extractor-vm"
VM_RAM_MB=3072
VM_VCPUS=2
VM_SIZE_GB=25
WIN_USER="OfficeUser"
WIN_PASS="Office365!"
EXTRACTED_DIR="${HOME}/.office365-extracted"
DOWNLOADS="${HOME}/Downloads"
LOGFILE="/tmp/office365_vm_extractor.log"

# Windows 10/11 Evaluation ISO (official Microsoft, no key needed, 90-day trial)
# NOTE: Microsoft changes these URLs. If this URL fails, manually download
# the ISO from https://www.microsoft.com/en-us/evalcenter/evaluate-windows-10-enterprise
# and place it at ${VM_DIR}/Windows10_Evaluation.iso before running.
WIN_ISO_URL="https://software-download.microsoft.com/download/pr/Win10_22H2_English_x64.iso"
WIN_ISO_NAME="Windows10_Evaluation.iso"

# ODT URL
ODT_URL="https://download.microsoft.com/download/2/7/A/27AF1BE6-DD20-4CB4-B154-EBAB8A7D4A7E/officedeploymenttool_17830-20162.exe"

# ---- Helpers ----------------------------------------------------------------
info()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }
die()   { error "$*"; exit 1; }
log()   { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOGFILE"; }

# ---- Phase 1: Check Prerequisites -------------------------------------------
phase_1_prerequisites() {
    info "Phase 1: Checking prerequisites..."
    log "Phase 1: Prerequisites"

    # Check KVM
    if ! grep -c -E '(vmx|svm)' /proc/cpuinfo > /dev/null 2>&1; then
        die "CPU does not support KVM virtualization (no vmx/svm flags)."
    fi

    # Check /dev/kvm
    if [ ! -e /dev/kvm ]; then
        die "/dev/kvm not found. Is kvm kernel module loaded?"
    fi

    # Check available RAM
    local avail_ram_kb
    avail_ram_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    if [[ "$avail_ram_kb" -lt 4194304 ]]; then
        warn "Less than 4GB RAM available (${avail_ram_kb} KB)."
        read -rp "Continue anyway? [y/N]: " ans
        [[ "$ans" =~ ^[Yy]$ ]] || die "Aborted."
    fi

    # Check disk space
    local avail_disk
    avail_disk=$(df -BG "$HOME" | tail -1 | awk '{print $4}' | tr -d 'G')
    if [[ "$avail_disk" -lt 40 ]]; then
        die "Need at least 40GB free disk space. You have ~${avail_disk}GB."
    fi

    # Check required commands
    for cmd in qemu-system-x86_64 qemu-img virt-install virsh guestmount; do
        if ! command -v "$cmd" > /dev/null 2>&1; then
            die "Required command not found: $cmd. Run install.sh with Method 2 first."
        fi
    done

    log "Phase 1: Prerequisites OK"
}

# ---- Phase 2: Download Windows ISO ------------------------------------------
phase_2_download_iso() {
    info "Phase 2: Downloading Windows 10 Evaluation ISO..."
    log "Phase 2: ISO download"

    mkdir -p "$VM_DIR"
    local iso_path="${VM_DIR}/${WIN_ISO_NAME}"

    if [[ -f "$iso_path" ]]; then
        info "Windows ISO already present."
        return 0
    fi

    if command -v wget > /dev/null 2>&1; then
        wget --progress=bar:force -O "$iso_path" "$WIN_ISO_URL" 2>&1 | tail -f -n +6
    else
        curl -L --progress-bar -o "$iso_path" "$WIN_ISO_URL"
    fi

    log "Phase 2: ISO downloaded"
}

# ---- Phase 3: Create Answer File --------------------------------------------
phase_3_answer_file() {
    info "Phase 3: Creating unattended installation answer file..."
    log "Phase 3: Answer file"

    mkdir -p "${VM_DIR}/autounattend"

    cat > "${VM_DIR}/autounattend/autounattend.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <settings pass="windowsPE">
        <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <UserData>
                <ProductKey>
                    <Key></Key>
                    <WillShowUI>Never</WillShowUI>
                </ProductKey>
                <AcceptEula>true</AcceptEula>
            </UserData>
            <DiskConfiguration>
                <Disk wcm:action="add">
                    <DiskID>0</DiskID>
                    <WillWipeDisk>true</WillWipeDisk>
                    <CreatePartitions>
                        <CreatePartition wcm:action="add">
                            <Order>1</Order>
                            <Type>Primary</Type>
                            <Size>100</Size>
                        </CreatePartition>
                        <CreatePartition wcm:action="add">
                            <Order>2</Order>
                            <Type>Primary</Type>
                            <Extend>true</Extend>
                        </CreatePartition>
                    </CreatePartitions>
                    <ModifyPartitions>
                        <ModifyPartition wcm:action="add">
                            <Order>1</Order>
                            <PartitionID>1</PartitionID>
                            <Label>System</Label>
                            <Format>NTFS</Format>
                            <Active>true</Active>
                        </ModifyPartition>
                        <ModifyPartition wcm:action="add">
                            <Order>2</Order>
                            <PartitionID>2</PartitionID>
                            <Label>Windows</Label>
                            <Format>NTFS</Format>
                        </ModifyPartition>
                    </ModifyPartitions>
                </Disk>
            </DiskConfiguration>
            <ImageInstall>
                <OSImage>
                    <InstallTo>
                        <DiskID>0</DiskID>
                        <PartitionID>2</PartitionID>
                    </InstallTo>
                </OSImage>
            </ImageInstall>
        </component>
        <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <SetupUILanguage>
                <UILanguage>en-US</UILanguage>
            </SetupUILanguage>
            <InputLocale>en-US</InputLocale>
            <SystemLocale>en-US</SystemLocale>
            <UILanguage>en-US</UILanguage>
            <UserLocale>en-US</UserLocale>
        </component>
    </settings>
    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <UserAccounts>
                <LocalAccounts>
                    <LocalAccount wcm:action="add">
                        <Name>${WIN_USER}</Name>
                        <Group>Administrators</Group>
                        <Password>
                            <Value>${WIN_PASS}</Value>
                            <PlainText>true</PlainText>
                        </Password>
                    </LocalAccount>
                </LocalAccounts>
            </UserAccounts>
            <OOBE>
                <HideEULAPage>true</HideEULAPage>
                <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
                <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
                <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
                <NetworkLocation>Work</NetworkLocation>
                <SkipMachineOOBE>true</SkipMachineOOBE>
                <SkipUserOOBE>true</SkipUserOOBE>
            </OOBE>
            <FirstLogonCommands>
                <SynchronousCommand wcm:action="add">
                    <Order>1</Order>
                    <CommandLine>powershell -ExecutionPolicy Bypass -Command "\$ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri '${ODT_URL}' -OutFile 'C:\\Users\\${WIN_USER}\\Downloads\\ODT.exe'; Start-Process -FilePath 'C:\\Users\\${WIN_USER}\\Downloads\\ODT.exe' -ArgumentList '/quiet /extract:C:\\Users\\${WIN_USER}\\Downloads\\odt' -Wait; \$config = @'\n<Configuration>\n  <Add OfficeClientEdition=\"32\" Channel=\"PerpetualVL2021\"\u003e\n    <Product ID=\"ProPlus2021Volume\"\u003e\n      <Language ID=\"en-us\" /\u003e\n    </Product>\n  </Add>\n  <Display Level=\"None\" AcceptEULA=\"TRUE\" /\u003e\n  <Property Name=\"AUTOACTIVATE\" Value=\"0\" /\u003e\n  <Property Name=\"FORCEAPPSHUTDOWN\" Value=\"TRUE\" /\u003e\n  <Property Name=\"SharedComputerLicensing\" Value=\"0\" /\u003e\n  <Property Name=\"PinIconsToTaskbar\" Value=\"FALSE\" /\u003e\n</Configuration>\n'@; \$config | Out-File -FilePath 'C:\\Users\\${WIN_USER}\\Downloads\\odt\\config.xml' -Encoding UTF8; Start-Process -FilePath 'C:\\Users\\${WIN_USER}\\Downloads\\odt\\setup.exe' -ArgumentList '/configure', 'C:\\Users\\${WIN_USER}\\Downloads\\odt\\config.xml' -Wait; Write-Host 'ODT installation complete.'"
                    </CommandLine>
                    <Description>Download and run ODT</Description>
                </SynchronousCommand>
            </FirstLogonCommands>
        </component>
    </settings>
</unattend>
EOF

    log "Phase 3: Answer file created"
}

# ---- Phase 4: Build Custom ISO ----------------------------------------------
phase_4_build_iso() {
    info "Phase 4: Building custom ISO with answer file..."
    log "Phase 4: Build ISO"

    local original_iso="${VM_DIR}/${WIN_ISO_NAME}"
    local custom_iso="${VM_DIR}/windows_custom.iso"

    if [[ -f "$custom_iso" ]]; then
        info "Custom ISO already present."
        return 0
    fi

    # Mount original ISO
    local mount_point="/mnt/win_iso"
    sudo mkdir -p "$mount_point"
    sudo mount -o loop,ro "$original_iso" "$mount_point" || die "Failed to mount Windows ISO"

    # Copy contents
    local build_dir="${VM_DIR}/iso_build"
    rm -rf "$build_dir"
    mkdir -p "$build_dir"
    cp -r "${mount_point}/"* "$build_dir/" 2>/dev/null || true

    # Inject answer file
    cp "${VM_DIR}/autounattend/autounattend.xml" "${build_dir}/autounattend.xml"

    # Unmount
    sudo umount "$mount_point" || true

    # Build new ISO
    if command -v genisoimage > /dev/null 2>&1; then
        genisoimage -iso-level 4 -J -l -D -N -joliet-long -relaxed-filenames -V "Windows10_Custom" -b "boot/etfsboot.com" -no-emul-boot -boot-load-size 8 -boot-info-table -eltorito-alt-boot -e "efi/microsoft/boot/efisys.bin" -no-emul-boot -o "$custom_iso" "$build_dir"
    else
        die "genisoimage not found. Cannot build custom ISO."
    fi

    rm -rf "$build_dir"

    log "Phase 4: Custom ISO built"
}

# ---- Phase 5: Create VM -----------------------------------------------------
phase_5_create_vm() {
    info "Phase 5: Creating VM..."
    log "Phase 5: Create VM"

    local disk_path="${VM_DIR}/${VM_NAME}.qcow2"
    local custom_iso="${VM_DIR}/windows_custom.iso"

    # Create disk
    qemu-img create -f qcow2 "$disk_path" "${VM_SIZE_GB}G"

    # Create VM using virt-install (headless)
    virt-install \
        --name "$VM_NAME" \
        --memory "$VM_RAM_MB" \
        --vcpus "$VM_VCPUS" \
        --disk "path=${disk_path},format=qcow2" \
        --cdrom "$custom_iso" \
        --os-variant win10 \
        --graphics none \
        --network network=default \
        --boot cdrom,hd \
        --noautoconsole \
        --wait 0 || die "virt-install failed"

    log "Phase 5: VM created"
}

# ---- Phase 6: Wait for VM and Extract --------------------------------------
phase_6_wait_and_extract() {
    info "Phase 6: Waiting for Windows installation to complete..."
    info "This will take 20-30 minutes. Do not interrupt."
    log "Phase 6: Wait and extract"

    # Wait for VM to be ready (check if shutdown)
    local wait_count=0
    local max_wait=180  # 180 * 30s = 90 minutes max

    while virsh domstate "$VM_NAME" 2>/dev/null | grep -q "running"; do
        sleep 30
        wait_count=$((wait_count + 1))
        if [[ $wait_count -gt $max_wait ]]; then
            virsh destroy "$VM_NAME" 2>/dev/null || true
            die "VM took too long. Manual intervention may be needed."
        fi
        echo -n "."
    done
    echo

    info "VM stopped. Extracting Office binaries..."

    # Mount VM disk
    local mount_point="/mnt/vm_disk"
    sudo mkdir -p "$mount_point"

    # Find the Windows partition (usually the largest NTFS partition)
    local disk_path="${VM_DIR}/${VM_NAME}.qcow2"
    sudo guestmount -a "$disk_path" -i --rw "$mount_point" || die "Failed to mount VM disk"

    # Verify mount worked
    if ! mountpoint -q "$mount_point"; then
        die "Mount point not active. guestmount may have failed silently."
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
            info "Office binaries extracted to ${EXTRACTED_DIR}/Microsoft Office"
        else
            sudo guestunmount "$mount_point"
            die "Office installation not found in VM. ODT may have failed."
        fi
    fi

    # Verify
    if [[ ! -f "${EXTRACTED_DIR}/Microsoft Office/root/Office16/WINWORD.EXE" ]]; then
        sudo guestunmount "$mount_point"
        die "Extraction incomplete. WINWORD.EXE not found."
    fi

    sudo guestunmount "$mount_point"

    log "Phase 6: Extraction complete"
}

# ---- Phase 7: Cleanup VM --------------------------------------------------
phase_7_cleanup_vm() {
    info "Phase 7: Cleaning up VM..."
    log "Phase 7: Cleanup"

    virsh destroy "$VM_NAME" 2>/dev/null || true
    virsh undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true
    rm -rf "$VM_DIR"

    log "Phase 7: Cleanup complete"
}

# ---- Phase 8: Final Report --------------------------------------------------
phase_8_report() {
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

# ---- Main -------------------------------------------------------------------
main() {
    > "$LOGFILE"
    log "VM Extractor v1.1.000 started"

    phase_1_prerequisites
    phase_2_download_iso
    phase_3_answer_file
    phase_4_build_iso
    phase_5_create_vm
    phase_6_wait_and_extract
    phase_7_cleanup_vm
    phase_8_report
}

main "$@"