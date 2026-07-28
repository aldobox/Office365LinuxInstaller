# Contributing

Thank you for your interest in contributing! This project welcomes improvements, bug fixes, and documentation updates.

**Project:** Office365LinuxInstaller — Bash-based deployment helper for Microsoft Office 365 on Linux via Wine
**License:** MIT
**Repository:** https://github.com/aldobox/Office365LinuxInstaller

## How to Contribute

1. **Fork** the repository on GitHub.
2. **Clone** your fork locally.
3. Create a **feature branch** (`git checkout -b feature/my-improvement`).
4. Make your changes with clear, atomic commits.
5. Ensure `bash -n` passes on any modified `.sh` files.
6. **Push** your branch and open a **Pull Request** against `main`.
7. Tag format for releases: `vX.Y.Z` (e.g., `v2.1.4`).
8. Commit messages follow conventional commits (`feat(...)`, `fix(...)`, `docs(...)`).

## Code Style

- Use `#!/usr/bin/env bash` shebang.
- Enable `set -euo pipefail` in all scripts.
- Prefer `$HOME` and `$USER` over hardcoded paths.
- Comment sections with `---- Section Name ----` headers.
- Use descriptive function names (`phase_x_description`).

## Build, Run & Test

No compilation required. Pure Bash + SVG assets.

**Install:**
```bash
./install.sh
```

**Uninstall:**
```bash
./uninstall.sh
```

**Validate script syntax (run before submitting any change to scripts):**
```bash
bash -n install.sh
bash -n uninstall.sh
bash -n office365_vm_extractor.sh
bash -n office365_direct_downloader.sh
```

## Project Architecture

- `install.sh` — Main orchestrator (4 methods: Prebuilt, VM Extractor, User-provided, Direct C2R Download)
- `install-wrapper.sh` — Terminal emulator launcher for TUI environments
- `uninstall.sh` — Safe removal (process kill → prefix delete → system cleanup)
- `office365_vm_extractor.sh` — Direct QEMU VM automation for Method 2 (Windows ISO + ODT + extraction)
  - **No libvirt** — uses direct `qemu-system-x86_64` + `swtpm` socket (avoids permission issues)
  - **SeaBIOS** — legacy BIOS boot (OVMF/UEFI cannot boot Microsoft Consumer ISOs in QEMU)
  - **Floppy injection** — answer files delivered via A: drive (avoids ISO rebuild corruption)
  - **PID-based lifecycle** — `vm_is_running()`, `vm_wait_shutdown()`, `vm_destroy()`, `vm_start()`
- `office365_direct_downloader.sh` — Direct download of Microsoft C2R .img for Method 4 (BETA, no VM)
- `wrappers/` — 8 launcher scripts exporting `WINEPREFIX` and `exec`ing Office binaries
- `desktops/` — 8 `.desktop` files for GNOME/KDE/XFCE menus
- `icons/` — 8 brand-color SVG placeholders (256×256)
- `docs/` — Extended documentation (troubleshooting, FAQ)

## Project Rules

1. **No piracy**: Never add, reference, or facilitate `ohook`, crack tools, or activation bypasses.
2. **No hardcoded paths**: Use `$HOME`, `$USER`, or relative paths. Never hardcode personal directories.
3. **MIT License**: All contributions must be compatible with MIT.
4. **Sanitize personal data**: Remove system-specific usernames, IPs, or paths before committing.
5. **Do not alter `unattend.xml` ProductKey** — the generic Pro key `VK7JG-NPHTM-C97JM-9MPGT-3V66T` is for **edition selection only**, not activation.

## Dependencies

### Method 1 (Prebuilt URL)
- `wget`, `tar`, `zstd`, `wine64`, `wine32`, `winetricks`

### Method 2 (VM Extractor)
- `qemu-system-x86_64`, `qemu-img`, `swtpm`, `mtools`, `7z`, `genisoimage`
- **Optional:** `libguestfs-tools`, `qemu-nbd`, `ntfs-3g` (for Phase 8 extraction, may need sudo)
- **Not needed:** `libvirt-daemon-system`, `libvirt-clients`, `virtinst` — direct QEMU is used instead
- KVM acceleration strongly recommended; TCG fallback works but is ~10× slower

### Method 3 (User Packages)
- `wine64`, `wine32`, `winetricks`

### Method 4 (Direct C2R Download)
- `wget`, `7z`, `wine64`, `wine32`

### Shared
- `zenity` (for dialogs), `sudo` (for system packages), active Microsoft 365 subscription

## Current Limitations

1. **Method 2 VM boot:** Microsoft Windows 11 Consumer ISO (~7.3 GB) does not boot reliably in QEMU's CD-ROM emulation. Stalls at "Booting from DVD/CD...". Not a script bug — QEMU/ISO compatibility issue.
2. **Method 4 C2R install:** `setup.exe /configure` fails under Wine because the C2R engine requires Windows kernel services (COM+/BITS/C2R servicing stack). WineHQ Bug 47016. Files can be used on a real Windows PC/VM.
3. **SHA256 placeholders:** `WIN_ISO_SHA256`, `ODT_SHA256`, `OFFICE_IMG_SHA256` are placeholders. The script warns and continues.

## Known Issues

- `libguestfs-tools` requires `fusermount` group membership for `guestmount` to work without sudo
- `qemu-nbd` requires `sudo` to connect to `/dev/nbd0`
- SeaBIOS ignores `-boot order=d` when a bootable floppy is present — the floppy must NOT have a valid boot sector

## Files Never to Modify Without Maintainer Discussion

- `LICENSE` — MIT license text
- `install.sh` consent banner and legal notices
- `SECURITY.md` — Security policy

## Reporting Issues

- Use GitHub Issues.
- Include your distribution, Wine version, and Office version.
- Attach relevant terminal output (redact personal info).

## Legal Notice

By contributing, you agree that your contributions will be licensed under the MIT License.
You must not submit code that facilitates software piracy or circumvention of licensing.
