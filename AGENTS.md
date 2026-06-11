# AGENTS.md — AI Agent Context

## Project Identity

**Name:** Office365LinuxInstaller
**Type:** Bash-based deployment helper for Microsoft Office 365 on Linux via Wine
**License:** MIT
**Version:** 2.1.1
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
```

## Architecture

- `install.sh` — Main orchestrator (4 methods: Prebuilt, VM Extractor, User-provided, Direct C2R Download)
- `install-wrapper.sh` — Terminal emulator launcher for TUI environments
- `uninstall.sh` — Safe removal (process kill → prefix delete → system cleanup)
- `office365_vm_extractor.sh` — QEMU/KVM VM automation for Method 2 (Windows ISO + ODT + extraction)
- `office365_direct_downloader.sh` — Direct download of Microsoft C2R .img for Method 4 (BETA, no VM)
- `wrappers/` — 8 launcher scripts exporting `WINEPREFIX` and `exec`ing Office binaries
- `desktops/` — 8 `.desktop` files for GNOME/KDE/XFCE menus
- `icons/` — 8 brand-color SVG placeholders (256x256)
- `docs/` — Extended documentation (troubleshooting, FAQ)

## Critical Rules for Agents

1. **No piracy**: Never add, reference, or facilitate `ohook`, crack tools, or activation bypasses.
2. **No hardcoded paths**: Use `$HOME`, `$USER`, or relative paths. Never hardcode `/home/ciro/`.
3. **No model names**: Per CIRO LAW 4, do not hardcode LLM model names in any file.
4. **MIT License**: All contributions must be compatible with MIT.
5. **Sanitize personal data**: Remove system-specific usernames, IPs, or paths before committing.

## Dependencies

- `wine64`, `wine32`, `winetricks`
- `zenity` (for dialogs)
- `sudo` (for system package installation)
- Active Microsoft 365 subscription (user-provided)

## Git Workflow

- Branch: `main`
- Never commit to `main` directly — use feature branches + PRs.
- Tag format: `vX.Y.ZZZ` (e.g., `v1.0.000`)
