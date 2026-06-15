# Development Context — Office365LinuxInstaller

## 1. Project Genesis

This project was born from a user need to run Microsoft Office 365 desktop applications on a Linux workstation (specifically Xubuntu / Debian-based distributions) through the Wine compatibility layer. An existing third-party guide provided a seemingly convenient path: download a pre-built `.tar.zst` archive, extract a ready-made Wine prefix containing Office binaries, and run a series of shell commands to integrate it into the system.

**The problem:** That archive contained `ohook` — a known software activation bypass tool — and distributed pre-activated Microsoft Office binaries of completely unknown provenance. Using it would have meant:
1. Installing cracked/pirated software.
2. Violating Microsoft's licensing terms.
3. Introducing unverified, potentially malicious binaries into the system.

**The resolution:** Rebuild the entire package from scratch, preserving only the *structurally useful* elements (Wine prefix conventions, launcher wrappers, `.desktop` integration patterns) while replacing every pirated component with a legitimate, user-driven workflow. The result is `Office365LinuxInstaller`: a clean, open-source Bash installer supporting **four methods** to obtain and install Office binaries legally.

**Current version:** 2.1.2 (4 methods, direct QEMU VM extractor, direct C2R download).

---

## 2. Design Philosophy

### 2.1 Legitimacy-First Architecture
Every decision in this codebase prioritizes legal and ethical compliance:
- **No redistribution:** We do not bundle, host, or link to Microsoft Office binaries.
- **No cracks:** `ohook`, KMS emulators, keygens, or any activation circumvention tools are strictly absent.
- **User-supplied installer:** The script pauses and opens the user's browser to `https://www.microsoft.com/en-us/microsoft-365/download-office`. The user downloads the **Office Deployment Tool (ODT)** (`OfficeSetup.exe`), and the script then runs it with explicit `/download` and `/configure` commands inside the clean Wine prefix.

### 2.2 Idempotency and Cleanliness
The installer is designed to be runnable multiple times without leaving stale state:
- It **wipes and recreates** `~/.Microsoft_Office_365` on every run, ensuring no remnants of prior (potentially cracked) prefixes survive.
- It uses `set -euo pipefail` for strict error handling.
- Every phase is a discrete Bash function with clear entry/exit semantics.

### 2.3 System Integration, Not System Invasion
The installer modifies system directories (`/usr/share/applications/`, `/usr/share/icons/`, `/opt/launchers/`), but only with explicit `sudo` invocations and only for the specific files it manages. The `uninstall.sh` counterpart reverses every single one of these changes, restoring the system to its pre-installation state.

---

## 3. Technical Architecture

### 3.1 Execution Flow (install.sh) — 4 Methods

```
┌─────────────────────────────────────────────────────────────┐
│  Phase A: Dependencies (all methods)                         │
│  ├── dpkg --add-architecture i386                         │
│  ├── apt-get update                                         │
│  └── Install: wine64, wine32, winetricks, zenity, fonts   │
│  └── If Method 2 (VM): also install qemu-system-x86,      │
│      qemu-utils, mtools, genisoimage, swtpm-tools, cpio   │
├─────────────────────────────────────────────────────────────┤
│  METHOD 1: Download from Your Trusted Source                │
│  ├── User pastes a URL to a .tar.zst archive               │
│  ├── Download + extract into Wine prefix                   │
│  └── Verify: WINWORD.EXE exists                           │
├─────────────────────────────────────────────────────────────┤
│  METHOD 2: Extract from Windows VM (BETA — boot may fail)    │
│  ├── Download Windows 11 Consumer ISO from Microsoft       │
│  ├── Create QEMU VM with direct execution (no libvirt)    │
│  ├── Inject answer files via floppy image (A: drive)       │
│  ├── Windows installs unattended, ODT runs inside VM       │
│  ├── Extract Office binaries from VM disk                  │
│  └── Copy into Wine prefix                                │
├─────────────────────────────────────────────────────────────┤
│  METHOD 3: Use Your Own Packages                            │
│  ├── User points to pre-extracted Office tree              │
│  ├── Copy into Wine prefix                                 │
│  └── Verify: WINWORD.EXE exists                           │
├─────────────────────────────────────────────────────────────┤
│  METHOD 4: Direct C2R Download (BETA)                       │
│  ├── Download O365ProPlusRetail.img from Microsoft CDN     │
│  ├── Download ODT (OfficeSetup.exe) from Microsoft         │
│  ├── Extract .img with 7z (no mount required)              │
│  ├── Attempt wine setup.exe /configure                     │
│  └── ⚠ May fail under Wine; files usable on real Windows   │
├─────────────────────────────────────────────────────────────┤
│  Phase E-H: Wrappers, Desktop Integration, Fonts, Test    │
│  └── Same for all methods                                   │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 Directory Structure

| Path | Purpose | Lifecycle |
|------|---------|-----------|
| `~/.Microsoft_Office_365` | Wine prefix containing Office binaries | Created fresh per install; removed by uninstall |
| `~/.office365-extractor-vm/` | VM disk, ISO cache, build artifacts (Method 2) | Created on Method 2; removed by uninstall or Phase 9 cleanup |
| `~/.office365-img-cache/` | ODT + .img cache (Method 4) | Created on Method 4; removed by uninstall |
| `~/.office365-extracted/` | Extracted Office binaries from VM (Method 2) | Created on Method 2; removed by uninstall |
| `/opt/launchers/` | Bash wrappers for each Office app | Created on install; removed on uninstall |
| `/usr/share/applications/` | System `.desktop` menu entries | Created on install; removed on uninstall |
| `/usr/share/icons/hicolor/256x256/apps/` | App icons (SVG) | Created on install; removed on uninstall |
| `/usr/share/fonts/Windows/` | Bundled Microsoft-compatible fonts | Created on install; removed on uninstall |

### 3.3 Wrapper Design

Each wrapper (`wrappers/word365.sh`, etc.) is a minimal, deterministic launcher:
- Exports `WINEPREFIX=$HOME/.Microsoft_Office_365`
- Uses `exec wine <path_to_exe> "$@"` to pass through arguments (enables opening files from the command line)
- No logic, no side effects — just delegation.

The `teams365.sh` wrapper includes a fallback chain because Teams has multiple possible installation paths depending on the Office deployment channel.

### 3.4 ODT-Based Installation (v1.0.101+ → v2.1.2)

As of v1.0.101, Phase D supported the **Office Deployment Tool (ODT)** (`OfficeSetup.exe`). As of v2.1.2, there are **four methods** to obtain Office binaries:

**Method 1: Prebuilt URL**
- User provides a URL to a `.tar.zst` archive containing pre-extracted Office binaries.
- Fastest path (~5 minutes). Installer does not host or endorse any source.

**Method 2: VM Extractor (BETA — boot may fail)**
- Downloads Windows 11 Consumer ISO from Microsoft static CDN.
- Creates QEMU VM via **direct execution** (no libvirt required).
- Uses **floppy image injection** to deliver `autounattend.xml` on A: drive.
- Windows installs unattended; ODT runs inside VM; binaries extracted to host.
- **Limitation:** Microsoft Consumer ISO (~7.3 GB UDF+ISO9660 hybrid) does not boot reliably in QEMU CD-ROM emulation. Stalls at "Booting from DVD/CD...".
- **Workaround:** Use Method 1 or Method 3 if VM boot fails.

**Method 3: User-Provided Packages**
- User points to an existing extracted Office tree.
- Installer copies into Wine prefix. No downloads required.

**Method 4: Direct C2R Download (BETA)**
- Downloads `O365ProPlusRetail.img` (~4.5 GB) from Microsoft CDN.
- Downloads ODT (`OfficeSetup.exe`) from Microsoft.
- Extracts `.img` with `7z` (no mount/sudo needed).
- Attempts `wine setup.exe /configure`.
- **Limitation:** Click-to-Run (C2R) engine requires Windows kernel services (COM+, BITS, C2R servicing stack) that Wine does not emulate. `setup.exe /configure` will fail under Wine.
- **Use case:** Files are usable on a real Windows PC or VM. Not a Wine install path.

All methods converge on Phases E-H: wrappers, desktop integration, fonts/MIME, test launch.

---

## 4. Compatibility Matrix

| Distribution | Status | Notes |
|--------------|--------|-------|
| Ubuntu 22.04+ | ✅ Supported | Primary test target |
| Xubuntu 22.04+ | ✅ Supported | User's workstation |
| Linux Mint 21+ | ✅ Supported | Debian-based, same package manager |
| Debian 12+ | ✅ Supported | `apt` package names identical |
| Pop!_OS 22.04+ | ✅ Supported | Ubuntu derivative |
| Arch / Manjaro | ⚠️ Untested | Would require `pacman` package translation |
| Fedora | ⚠️ Untested | Would require `dnf` package translation |

---

## 5. Dependencies

### 5.1 System Packages (installed via `apt`) — All Methods
- `wine64`, `wine32` — Wine compatibility layer
- `winetricks` — Helper for installing Windows libraries
- `zenity` — GUI dialogs (for future interactive prompts)
- `ttf-mscorefonts-installer` — Microsoft core fonts (legally redistributable)
- `libc6:i386`, `libgcc1:i386`, `libstdc++6:i386` — 32-bit runtime libraries
- `libfreetype6:i386`, `libx11-6:i386`, `libxext6:i386`, `libxrender1:i386`, `libxrandr2:i386` — Graphics/X11 32-bit support
- `winbind`, `samba-common`, `gnutls-bin` — Windows networking compatibility
- `cups-*`, `printer-driver-*` — Printing subsystem support
- `msitools` — MSI package introspection tools
- `build-essential`, `gcc-multilib`, `g++-multilib` — Compilation toolchain

### 5.2 Method 2 (VM Extractor) Additional Packages
- `qemu-system-x86` — QEMU x86_64 system emulator (replaces libvirt)
- `qemu-utils` — `qemu-img` for disk creation
- `mtools` — `mformat`, `mcopy` for floppy image creation (no root)
- `genisoimage` — ISO building (with `-allow-limited-size` for >4GB files)
- `swtpm-tools` — TPM 2.0 emulator for Windows 11 requirements
- `cpio` — Archive tooling (used by guestfs)
- `libguestfs-tools` — Optional: `guestmount` / `virt-copy-out` for Phase 8 extraction
- `ntfs-3g` — Optional: NTFS filesystem support for `qemu-nbd` fallback

**Not needed:** `libvirt-daemon-system`, `libvirt-clients`, `virtinst` — we use direct QEMU execution.

### 5.3 Method 4 (Direct C2R) Additional Packages
- `p7zip-full` — `7z` command for extracting `.img` without mount

### 5.4 User-Supplied
- **Microsoft 365 subscription** (Personal, Family, or Business) — required to activate Office after installation.
- **For Method 1:** A trusted URL to a `.tar.zst` archive with pre-extracted Office binaries.
- **For Method 2/4:** No additional user files; everything downloads from Microsoft CDN.

---

## 6. Security Considerations

### 6.1 What We Protect Against
- **Piracy infiltration:** By never touching pre-activated binaries, we eliminate the risk of installing cracked software or activation malware.
- **Supply-chain attacks:** The user downloads the ODT directly from Microsoft's HTTPS endpoint (`microsoft.com/en-us/microsoft-365/download-office`), not from a third-party mirror.
- **Privilege escalation:** The script uses `sudo` only for specific, bounded operations (package install, system icon/desktop updates). It does not run `wine` or the Office installer as root.

### 6.2 Known Limitations
- **Wine is not a sandbox:** A compromised Windows binary running under Wine has the same filesystem access as the Linux user. This is a Wine architectural limitation, not something our installer can mitigate.
- **Microsoft's installer behavior:** The ODT downloads and installs Office binaries. The Click-to-Run service runs inside Wine and can be terminated with `uninstall.sh`.
- **Method 2 (VM Extractor) ISO boot:** Microsoft Windows 11 Consumer ISO (~7.3 GB, UDF+ISO9660 hybrid) does not boot reliably in QEMU's CD-ROM emulation. Both UEFI (OVMF) and SeaBIOS stall at DVD boot. This is a QEMU/Microsoft ISO compatibility issue, not a script bug. If boot fails, use Method 1 or 3.
- **Method 4 (Direct C2R) Wine install:** `setup.exe /configure` fails under Wine because the Click-to-Run engine requires Windows kernel services (COM+, BITS, C2R servicing stack) that Wine does not emulate. Files can be used on a real Windows PC/VM.
- **FUSE group for guestmount:** `libguestfs-tools`'s `guestmount` requires the user to be in the `fuse` group to mount VM disks without sudo. If not, Phase 8 extraction falls back to `qemu-nbd` which requires sudo.
- **KVM vs TCG speed:** Method 2 strongly prefers KVM acceleration. Without `/dev/kvm` access, QEMU falls back to TCG (software emulation) which is ~10× slower and may cause Windows install timeouts.

---

## 7. Future Evolution

### 7.1 Near-Term (v2.1.x)
- [x] Add Method 4: Direct C2R Download (BETA) — **COMPLETED in v2.1.2**
- [x] Replace libvirt with direct QEMU execution — **COMPLETED in v2.1.2**
- [x] Add floppy image injection for VM answer files — **COMPLETED in v2.1.2**
- [x] Fix genisoimage >4GB abort — **COMPLETED in v2.1.2**
- [x] Fix sudo mount blocker with 7z extraction — **COMPLETED in v2.1.2**
- [ ] Fix Method 2 VM ISO boot (top priority) — Investigate alternative Windows sources (VHDX, Win10 Eval, PE ISO)
- [ ] Replace placeholder SVG icons with official Microsoft Fluent UI System Icons
- [ ] Add `--silent` mode for automated/CI deployment testing

### 7.2 Mid-Term (v2.2.x)
- [ ] Integrate `winetricks` dotnet48 / corefonts checks as hard prerequisites (currently warnings)
- [ ] Provide `.deb` packaging for one-shot `dpkg -i` installation
- [ ] Cross-distribution support (Arch PKGBUILD, Fedora RPM spec)

### 7.3 Long-Term (v3.x)
- [ ] GTK/Qt GUI frontend as alternative to terminal installer
- [ ] Integration with `proton` or `bottles` as alternative Wine prefixes
- [ ] Native Wayland support (Wine 10.0+ has experimental Wayland backend)

---

## 8. Operational Notes for Maintainers

### 8.1 Before Every Release
1. Run `bash -n install.sh && bash -n uninstall.sh && bash -n office365_vm_extractor.sh && bash -n office365_direct_downloader.sh`
2. Test on a clean VM (Ubuntu 22.04 LTS or 26.04 recommended)
3. Verify all 4 methods at least reach their first verification checkpoint:
   - Method 1: URL prompt → download → WINWORD.EXE check
   - Method 2: VM creation → ISO download → Phase 5 (accept boot may stall)
   - Method 3: Path prompt → copy → WINWORD.EXE check
   - Method 4: ODT download → .img download → extraction → setup.exe launch (accept Wine failure)
4. Check that `uninstall.sh` leaves no files in `/usr/share/applications/`, `/usr/share/icons/`, `/opt/launchers/`, `~/.office365-*`
5. Update version string in `install.sh`, `uninstall.sh`, `AGENTS.md`, `README.md`

### 8.2 If Method 2 VM Boot Fails
- **Symptom:** QEMU stalls at "Booting from DVD/CD..." or UEFI PXE loops. Disk never grows past 324K.
- **Root cause:** Microsoft Consumer ISO (7.3 GB, UDF+ISO9660 hybrid) incompatible with QEMU CD-ROM emulation.
- **Not a script bug:** Confirmed across UEFI (OVMF) and SeaBIOS variants. Works in VMware/VirtualBox.
- **Workaround:** Use Method 1 (prebuilt URL) or Method 3 (user packages). Or investigate alternative Windows sources (VHDX, Win10 Eval ISO).

### 8.3 If a User Reports "Installer Says Dependencies Installed But Nothing Was Installed"
- Likely cause: `apt-get` failed (e.g., dpkg lock held by another process) but `|| true` masked the error. This was fixed in v1.0.101 by removing `|| true` from the apt-get install line.
- If user is on a pre-v1.0.101 version: check for `E: Unable to acquire the dpkg frontend lock` in terminal output.
- Resolution: Kill any hanging `apt-get` or `dpkg` processes, then re-run `./install.sh`. The `wait_for_dpkg_lock()` function handles this automatically.

### 8.4 If a User Reports Wine COM Errors (`0x80004002`)
- These are **normal Wine 10.0 initialization warnings** when creating a fresh 64-bit prefix.
- They do **not** indicate a crash or installation failure.
- Only investigate further if the script exits with a non-zero code *after* these messages.

### 8.5 If Icons Do Not Appear in the Menu
- Run `sudo gtk-update-icon-cache /usr/share/icons/hicolor/`
- Run `sudo update-desktop-database /usr/share/applications/`
- Log out and log back in (XFCE caches menu entries aggressively).

### 8.6 If Method 4 Reports "Success" But No Office Apps Launch
- Likely cause: Prior WAM stub install left `~/.office365-extracted/` directory, causing false positive.
- Fix: Check `WINWORD.EXE` file presence, not directory existence. Fixed in `351fafe`.
- Resolution: Delete `~/.office365-extracted/` and re-run Method 4 (or use Method 1/3).

---

## 9. Glossary

| Term | Definition |
|------|------------|
| **Wine Prefix** | An isolated Windows environment (registry, `C:` drive, system DLLs) managed by Wine. Default is `~/.wine`; ours is `~/.Microsoft_Office_365`. |
| **Winetricks** | A helper script that automates installation of Windows libraries (DLLs, fonts, runtimes) into a Wine prefix. |
| **DOSDevices** | Wine's symlink layer mapping Windows drive letters (`C:`, `D:`, `Z:`) to Linux filesystem paths. |
| **Click-to-Run (C2R)** | Microsoft's streaming installation technology used by Office 365. Requires Windows kernel services (COM+, BITS) not available in Wine. |
| **ODT** | Office Deployment Tool — Microsoft's command-line alternative to `Setup.exe` for enterprise deployments. |
| **C2R** | Click-to-Run — Microsoft's streaming installation technology used by Office 365. Requires Windows kernel services. |
| **FUSE** | Filesystem in Userspace — required for `guestmount` to work without sudo. |
| **QEMU/KVM** | QEMU emulator + Linux Kernel Virtual Machine acceleration. Method 2 uses direct QEMU (no libvirt). |
| **SeaBIOS** | Open-source legacy BIOS firmware for QEMU. Used instead of OVMF for better ISO compatibility. |
| **OVMF** | Open Virtual Machine Firmware — UEFI firmware for QEMU. Cannot boot Microsoft Consumer ISOs in QEMU. |
| **mtools** | MS-DOS filesystem manipulation tools. Used to create FAT12 floppy images without root. |
| **MIME Association** | Links file extensions (e.g., `.docx`) to applications (e.g., `word365.desktop`) so double-clicking opens the right program. |

---

*Document version: 2.1.2 — Last updated: 2026-06-15*
