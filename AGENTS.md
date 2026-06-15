# AGENTS.md — AI Agent Context

## Project Identity

**Name:** Office365LinuxInstaller
**Type:** Bash-based deployment helper for Microsoft Office 365 on Linux via Wine
**License:** MIT
**Version:** 2.1.2
**Repository:** https://github.com/aldobox/Office365LinuxInstaller

## Build & Run

No compilation required. Pure Bash + SVG assets.

**Install:**
```bash
./install.sh
```

**Uninstall:**
```bash
./uninstall.sh
```

**Validate script syntax:**
```bash
bash -n install.sh
bash -n uninstall.sh
bash -n office365_vm_extractor.sh
bash -n office365_direct_downloader.sh
```

## Architecture

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

## Critical Rules for Agents

1. **No piracy**: Never add, reference, or facilitate `ohook`, crack tools, or activation bypasses.
2. **No hardcoded paths**: Use `$HOME`, `$USER`, or relative paths. Never hardcode `/home/ciro/`.
3. **No model names**: Per CIRO LAW 4, do not hardcode LLM model names in any file.
4. **MIT License**: All contributions must be compatible with MIT.
5. **Sanitize personal data**: Remove system-specific usernames, IPs, or paths before committing.
6. **Do not alter `unattend.xml` ProductKey** — the generic Pro key `VK7JG-NPHTM-C97JM-9MPGT-3V66T` is for **edition selection only**, not activation.

## Dependencies

### Method 1 (Prebuilt URL)
- `wget`, `tar`, `zstd`, `wine64`, `wine32`, `winetricks`

### Method 2 (VM Extractor)
- `qemu-system-x86_64`, `qemu-img`, `swtpm`, `mtools`, `7z`, `genisoimage`
- **Optional:** `libguestfs-tools`, `qemu-nbd`, `ntfs-3g` (for Phase 8 extraction, may need sudo)
- **Not needed:** `libvirt-daemon-system`, `libvirt-clients`, `virtinst` — we use direct QEMU
- KVM acceleration strongly recommended; TCG fallback works but is ~10× slower

### Method 3 (User Packages)
- `wine64`, `wine32`, `winetricks`

### Method 4 (Direct C2R Download)
- `wget`, `7z`, `wine64`, `wine32`

### Shared
- `zenity` (for dialogs), `sudo` (for system packages), active Microsoft 365 subscription

## Current Limitations

1. **Method 2 VM boot:** Microsoft Windows 11 Consumer ISO (~7.3 GB) does not boot reliably in QEMU's CD-ROM emulation. Stalls at "Booting from DVD/CD...". Not a script bug — QEMU/ISO compatibility issue.
2. **Method 4 C2R install:** `setup.exe /configure` fails under Wine because C2R engine requires Windows kernel services (COM+/BITS/C2R servicing stack). WineHQ Bug 47016. Files can be used on a real Windows PC/VM.
3. **SHA256 placeholders:** `WIN_ISO_SHA256`, `ODT_SHA256`, `OFFICE_IMG_SHA256` are placeholders. Script warns and continues.

## Known Issues

- `libguestfs-tools` requires `fusermount` group membership for `guestmount` to work without sudo
- `qemu-nbd` requires `sudo` to connect to `/dev/nbd0`
- SeaBIOS ignores `-boot order=d` when a bootable floppy is present — floppy must NOT have a valid boot sector

## Git Workflow

- Branch: `main`
- Never commit to `main` directly — use feature branches + PRs.
- Tag format: `vX.Y.ZZZ` (e.g., `v1.0.000`)
- Commit messages: follow conventional commits (`feat(...)`, `fix(...)`, `docs(...)`)

## Engineer Log

See `debug/engineerlog.md` for detailed session history, decisions, and rollback procedures.

## For Next Engineer

1. **Method 2 boot fix:** Top priority. Try alternative Windows sources (evaluation VHDX, Win10 Eval ISO, PE ISO).
2. **Method 4 stabilization:** Decide if it should be promoted from BETA or documented more clearly.
3. **SHA256 population:** After first successful downloads, compute hashes and update placeholders.
4. **Extraction without sudo:** Investigate `virt-copy-out` (guestfish) for Phase 8 — works without FUSE if libguestfs is installed.

## Files Never to Modify Without Discussion

- `cbap/cbap.py` — CIRO protocol contract (versioned separately)
- `LICENSE` — MIT license text
- `AGENTS.md` — This file (agents need stable context)
