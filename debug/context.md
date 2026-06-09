# Development Context — Office365LinuxInstaller

## 1. Project Genesis

This project was born from a user need to run Microsoft Office 365 desktop applications on a Linux workstation (specifically Xubuntu / Debian-based distributions) through the Wine compatibility layer. An existing third-party guide provided a seemingly convenient path: download a pre-built `.tar.zst` archive, extract a ready-made Wine prefix containing Office binaries, and run a series of shell commands to integrate it into the system.

**The problem:** That archive contained `ohook` — a known software activation bypass tool — and distributed pre-activated Microsoft Office binaries of completely unknown provenance. Using it would have meant:
1. Installing cracked/pirated software.
2. Violating Microsoft's licensing terms.
3. Introducing unverified, potentially malicious binaries into the system.

**The resolution:** Rebuild the entire package from scratch, preserving only the *structurally useful* elements (Wine prefix conventions, launcher wrappers, `.desktop` integration patterns) while replacing every pirated component with a legitimate, user-driven workflow. The result is `Office365LinuxInstaller`: a clean, open-source Bash installer that sets up the environment, then hands control to the user to download Microsoft's official installer using their own active subscription.

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

### 3.1 Execution Flow (install.sh)

```
┌─────────────────────────────────────────────────────────────┐
│  Phase A: Dependencies                                      │
│  ├── dpkg --add-architecture i386                         │
│  ├── apt-get update                                         │
│  └── Install: wine64, wine32, winetricks, zenity, fonts   │
├─────────────────────────────────────────────────────────────┤
│  Phase B: Clean Wine Prefix                               │
│  ├── rm -rf ~/.Microsoft_Office_365                       │
│  ├── wineboot --init (win64)                              │
│  ├── registry: Windows 10 mode                            │
│  ├── winetricks: corefonts, msxml6, gdiplus               │
│  ├── dosdevices symlinks (c:, d:, e:, z:, c::, z::)      │
│  └── user folders: crossover/AppData/{Local,Roaming}      │
├─────────────────────────────────────────────────────────────┤
│  Phase C: Browser Prompt                                  │
│  ├── xdg-open https://www.office.com                      │
│  ├── User signs in + downloads Setup.exe                   │
│  └── Script waits for Enter key                            │
├─────────────────────────────────────────────────────────────┤
│  Phase D: Official Installer Execution (ODT)              │
│  ├── Generate /tmp/o365_configuration.xml                 │
│  ├── wine OfficeSetup.exe /download config.xml            │
│  │   └── Downloads ~4-5 GB to ~/Downloads/OfficeCache/   │
│  ├── [Cache check] Skip /download if cache exists         │
│  ├── wine OfficeSetup.exe /configure config.xml           │
│  │   └── Installs from cache into Wine prefix              │
│  └── Verify: WINWORD.EXE exists at expected path          │
├─────────────────────────────────────────────────────────────┤
│  Phase E: Wrappers                                        │
│  └── Copy *365.sh → /opt/launchers/                        │
├─────────────────────────────────────────────────────────────┤
│  Phase F: Desktop Integration                             │
│  ├── Copy SVG icons → /usr/share/icons/hicolor/256x256/  │
│  ├── Copy .desktop → /usr/share/applications/              │
│  └── gtk-update-icon-cache + update-desktop-database      │
├─────────────────────────────────────────────────────────────┤
│  Phase G: Fonts & MIME                                    │
│  ├── Copy bundled fonts → /usr/share/fonts/Windows/       │
│  ├── fc-cache -fv                                         │
│  └── xdg-mime default for Word/Excel/PowerPoint/Access    │
├─────────────────────────────────────────────────────────────┤
│  Phase H: Test Launch                                     │
│  └── timeout 5 wine WINWORD.EXE (smoke test)               │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 Directory Structure

| Path | Purpose | Lifecycle |
|------|---------|-----------|
| `~/.Microsoft_Office_365` | Wine prefix containing Office binaries | Created fresh per install; removed by uninstall |
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

### 3.4 ODT-Based Installation (v1.0.101+)

As of v1.0.101, Phase D was completely rewritten to support the **Office Deployment Tool (ODT)** (`OfficeSetup.exe`) rather than a self-running consumer installer:

1. **Generate `configuration.xml`** on-the-fly inside `/tmp/` — specifies `O365ProPlusRetail`, `en-GB`, silent install.
2. **Run `wine OfficeSetup.exe /download configuration.xml`** — downloads ~4-5 GB of Office binaries to `~/Downloads/OfficeCache/`.
3. **Cache detection:** If `~/Downloads/OfficeCache/` already exists and is non-empty, the `/download` step is skipped entirely.
4. **Run `wine OfficeSetup.exe /configure configuration.xml`** — installs from the local cache into `~/.Microsoft_Office_365`.
5. **Cleanup prompt (Phase I):** After the test launch, a `[y/n]` prompt asks whether to delete `OfficeCache/` + temp files.

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

### 5.1 System Packages (installed via `apt`)
- `wine64`, `wine32` — Wine compatibility layer
- `winetricks` — Helper for installing Windows libraries
- `zenity` — GUI dialogs (for future interactive prompts)
- `ttf-mscorefonts-installer` — Microsoft core fonts (legally redistributable)
- `libc6:i386`, `libgcc1:i386`, `libstdc++6:i386` — 32-bit runtime libraries
- `libfreetype6:i386`, `libx11-6:i386`, `libxext6:i386`, `libxrender1:i386`, `libxrandr2:i386` — Graphics/X11 32-bit support
- `winbind`, `samba-common`, `gnutls-bin` — Windows networking compatibility
- `cups-*`, `printer-driver-*` — Printing subsystem support
- `msitools` — MSI package introspection tools
- `build-essential`, `gcc-multilib`, `g++-multilib` — Compilation toolchain (for Wine gecko/mono builds if needed)

### 5.2 User-Supplied
- **Microsoft 365 subscription** (Personal, Family, or Business) — required to activate Office after installation.
- **Official ODT `OfficeSetup.exe`** — downloaded by the user from Microsoft's download page, not provided by this project.

---

## 6. Security Considerations

### 6.1 What We Protect Against
- **Piracy infiltration:** By never touching pre-activated binaries, we eliminate the risk of installing cracked software or activation malware.
- **Supply-chain attacks:** The user downloads the ODT directly from Microsoft's HTTPS endpoint (`microsoft.com/en-us/microsoft-365/download-office`), not from a third-party mirror.
- **Privilege escalation:** The script uses `sudo` only for specific, bounded operations (package install, system icon/desktop updates). It does not run `wine` or the Office installer as root.

### 6.2 Known Limitations
- **Wine is not a sandbox:** A compromised Windows binary running under Wine has the same filesystem access as the Linux user. This is a Wine architectural limitation, not something our installer can mitigate.
- **Microsoft's installer behavior:** The ODT downloads and installs Office binaries. The Click-to-Run service runs inside Wine and can be terminated with `uninstall.sh`.

---

## 7. Future Evolution

### 7.1 Near-Term (v1.1.x)
- [ ] Replace placeholder SVG icons with official Microsoft Fluent UI System Icons (MIT-licensed, from `microsoft/fluentui-system-icons`)
- [ ] Add `--silent` mode for automated/CI deployment testing
- [ ] Support detecting `OfficeSetup.exe` in additional download paths (`~/Downloads/Office/`, browser-specific subdirectories)

### 7.2 Mid-Term (v1.2.x)
  - [x] Add `config.xml` support for Office Deployment Tool (ODT) — **COMPLETED in v1.0.101**
  - [x] Add dpkg lock detection with smart wait — **COMPLETED in v1.0.101**
  - [ ] Integrate `winetricks` dotnet48 / corefonts checks as hard prerequisites (currently warnings)
- [ ] Provide `.deb` packaging for one-shot `dpkg -i` installation

### 7.3 Long-Term (v2.x)
- [ ] GTK/Qt GUI frontend as alternative to terminal installer
- [ ] Cross-distribution support (Arch PKGBUILD, Fedora RPM spec)
- [ ] Integration with `proton` or `bottles` as alternative Wine prefixes

---

## 8. Operational Notes for Maintainers

### 8.1 Before Every Release
1. Run `bash -n install.sh && bash -n uninstall.sh`
2. Test on a clean VM (Ubuntu 22.04 LTS recommended)
3. Verify `microsoft.com/en-us/microsoft-365/download-office` opens correctly
4. Check that `uninstall.sh` leaves no files in `/usr/share/applications/`, `/usr/share/icons/`, `/opt/launchers/`
5. Update version string in `install.sh`, `uninstall.sh`, and `AGENTS.md`

### 8.2 If a User Reports "Installer Says Dependencies Installed But Nothing Was Installed"
- Likely cause: `apt-get` failed (e.g., dpkg lock held by another process) but `|| true` masked the error. This was fixed in v1.0.101 by removing `|| true` from the apt-get install line.
- If user is on a pre-v1.0.101 version: check for `E: Unable to acquire the dpkg frontend lock` in terminal output.
- Resolution: Kill any hanging `apt-get` or `dpkg` processes, then re-run `./install.sh`. The new `wait_for_dpkg_lock()` function handles this automatically.

### 8.3 If a User Reports Wine COM Errors (`0x80004002`)
- These are **normal Wine 10.0 initialization warnings** when creating a fresh 64-bit prefix.
- They do **not** indicate a crash or installation failure.
- Only investigate further if the script exits with a non-zero code *after* these messages.

### 8.4 If Icons Do Not Appear in the Menu
- Run `sudo gtk-update-icon-cache /usr/share/icons/hicolor/`
- Run `sudo update-desktop-database /usr/share/applications/`
- Log out and log back in (XFCE caches menu entries aggressively).

---

## 9. Glossary

| Term | Definition |
|------|------------|
| **Wine Prefix** | An isolated Windows environment (registry, `C:` drive, system DLLs) managed by Wine. Default is `~/.wine`; ours is `~/.Microsoft_Office_365`. |
| **Winetricks** | A helper script that automates installation of Windows libraries (DLLs, fonts, runtimes) into a Wine prefix. |
| **DOSDevices** | Wine's symlink layer mapping Windows drive letters (`C:`, `D:`, `Z:`) to Linux filesystem paths. |
| **Click-to-Run (C2R)** | Microsoft's streaming installation technology used by Office 365. |
| **ODT** | Office Deployment Tool — Microsoft's command-line alternative to `Setup.exe` for enterprise deployments. |
| **MIME Association** | Links file extensions (e.g., `.docx`) to applications (e.g., `word365.desktop`) so double-clicking opens the right program. |

---

*Document version: 1.0.101 — Last updated: 2026-06-09*
