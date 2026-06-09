# Office365LinuxInstaller

Clean, legal Microsoft Office 365 (Desktop) installation via Wine on Ubuntu / Debian-based distributions (Xubuntu, Linux Mint, Pop!_OS, etc.).

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)](https://github.com/aldobox/Office365LinuxInstaller/releases/tag/v2.0.0)

## What This Is

This project provides an automated installer that supports **three installation methods**:

**Method 1: Pre-extracted binaries (FASTEST — ~5 minutes)**
- Downloads pre-extracted Office binaries from an external source you configure
- Installs an isolated Wine 9.7 runtime (~150 MB)
- Creates a 32-bit Wine prefix at `~/.Microsoft_Office_365`
- Sets up desktop launchers, file associations, and MIME types

**Method 2: Extract from Windows VM (SLOW — ~60-90 minutes)**
- Downloads the official Windows 10 Evaluation ISO from Microsoft
- Creates a QEMU/KVM virtual machine (3 GB RAM, 2 vCPUs, 25 GB disk)
- Installs Windows 10 unattended (no user interaction)
- Downloads and runs the official Office Deployment Tool inside the VM
- Extracts Office binaries from the VM disk to your Linux filesystem
- Deletes the VM and all associated files after extraction
- Best for: Privacy-conscious users who want full control

**Method 3: Use your own packages (CUSTOM — ~2 minutes)**
- You provide a pre-extracted Microsoft Office tree
- Installer copies your files into a Wine prefix
- No external downloads required
- Best for: Enterprise users with volume-licensed binaries

**No cracked, pre-activated, or pirated binaries are included or referenced.**

## Requirements

- Ubuntu / Debian / Linux Mint / Xubuntu (or derivative)
- Active **Microsoft 365 subscription** (Personal, Family, or Business)
- `sudo` privileges (for installing system packages, fonts, and icons)
- For **Method 1**: Internet connection + external download source (set `PREBUILT_URL` in `install.sh`)
- For **Method 2**: 8GB+ RAM, 40GB free disk, KVM CPU support, internet connection
- For **Method 3**: A pre-extracted Microsoft Office tree

## Quick Start

1. **Clone or download** this repository:
   ```bash
   git clone https://github.com/aldobox/Office365LinuxInstaller.git
   cd Office365LinuxInstaller
   ```

2. **Run the installer:**
   ```bash
   ./install.sh
   ```

3. **Read the consent banner** and type `YES` to proceed.

4. **Choose your installation method:**
   - **[1]** Download pre-extracted binaries (requires `PREBUILT_URL` to be set)
   - **[2]** Extract from Windows VM (fully automated, takes ~60-90 min)
   - **[3]** Use your own packages (point to your Office tree)

5. The script will:
   - Install system dependencies (Wine 9.7, winetricks, fonts)
   - Create a clean Wine prefix at `~/.Microsoft_Office_365`
   - Copy Office binaries into the prefix
   - Create desktop launchers and file associations
   - Test launch Word to verify execution

6. After installation, the script will ask if you want to delete temporary files.

7. Once complete, find your Office apps in the system application menu.

## First Launch

When you first open Word, Excel, etc., you will be prompted to **sign in with your Microsoft account**. Use the same account associated with your Microsoft 365 subscription.

## Project Structure

```
Office365LinuxInstaller/
├── install.sh          # Main installer (8 phases)
├── uninstall.sh        # Complete removal script
├── LICENSE             # MIT License
├── README.md           # This file
├── CONTRIBUTING.md     # Contribution guidelines
├── SECURITY.md         # Security policy
├── CODE_OF_CONDUCT.md  # Community standards
├── AGENTS.md           # AI agent context
├── wrappers/           # Bash launchers for each Office app
│   ├── word365.sh
│   ├── excel365.sh
│   ├── powerpoint365.sh
│   ├── outlook365.sh
│   ├── access365.sh
│   ├── publisher365.sh
│   ├── onenote365.sh
│   └── teams365.sh
├── desktops/           # .desktop files for system menus
│   ├── word365.desktop
│   ├── excel365.desktop
│   ├── powerpoint365.desktop
│   ├── outlook365.desktop
│   ├── access365.desktop
│   ├── publisher365.desktop
│   ├── onenote365.desktop
│   └── teams365.desktop
├── icons/              # 256x256 SVG placeholders
│   ├── word365.svg
│   ├── excel365.svg
│   ├── powerpoint365.svg
│   ├── outlook365.svg
│   ├── access365.svg
│   ├── publisher365.svg
│   ├── onenote365.svg
│   └── teams365.svg
└── docs/               # Extended documentation
    └── troubleshooting.md
```

## Uninstall

To completely remove Office 365 and all associated files:

```bash
./uninstall.sh
```

## Troubleshooting

- **"PREBUILT_URL not configured"**: For Method 1, edit `install.sh` and set `PREBUILT_URL="https://your-url-here"` to point to your GitHub release asset or other trusted source.
- **"KVM virtualization not supported"**: Method 2 requires CPU virtualization extensions (vmx/svm). Check BIOS settings for Intel VT-x / AMD-V.
- **"WINWORD.EXE not found"**: Check `~/.Microsoft_Office_365/drive_c/Program Files/Microsoft Office/root/Office16/`. If using Method 3, verify your Office tree has the correct structure.
- **Fonts look odd**: Run `sudo fc-cache -fv` after installation.
- **Wine crashes**: Isolated Wine 9.7 is used to avoid conflicts with system Wine.
- **Microsoft account login fails**: The installer sets up a browser intercept for MSAL fallback. Ensure `xdg-open` is available.

For more details, see [docs/troubleshooting.md](docs/troubleshooting.md).

## Known Limitations

- Microsoft account login uses a browser fallback mechanism (experimental)
- OneNote and Teams are known to be non-functional in Wine
- Excel may exhibit screen flickering
- No automatic feature updates — manual reinstallation required
- Isolated Wine 9.7 will not receive security updates

## Project Structure

```
Office365LinuxInstaller/
├── install.sh                    # Main installer (3 methods, consent banner)
├── office365_vm_extractor.sh     # VM extraction script (Method 2)
├── uninstall.sh                  # Complete removal script
├── LICENSE                       # MIT License
├── README.md                     # This file
├── CONTRIBUTING.md               # Contribution guidelines
├── SECURITY.md                   # Security policy
├── CODE_OF_CONDUCT.md            # Community standards
├── AGENTS.md                     # AI agent context
├── stub_dll/                     # WAM stub DLL (MSAL fallback)
│   └── msalruntime.dll
├── wrappers/                     # Bash launchers for each Office app
│   ├── word365.sh
│   ├── excel365.sh
│   ├── powerpoint365.sh
│   ├── outlook365.sh
│   ├── access365.sh
│   ├── publisher365.sh
│   ├── onenote365.sh
│   └── teams365.sh
├── desktops/                     # .desktop files for system menus
│   ├── word365.desktop
│   ├── excel365.desktop
│   ├── powerpoint365.desktop
│   ├── outlook365.desktop
│   ├── access365.desktop
│   ├── publisher365.desktop
│   ├── onenote365.desktop
│   └── teams365.desktop
├── icons/                        # 256x256 SVG placeholders
│   ├── word365.svg
│   ├── excel365.svg
│   ├── powerpoint365.svg
│   ├── outlook365.svg
│   ├── access365.svg
│   ├── publisher365.svg
│   ├── onenote365.svg
│   └── teams365.svg
└── docs/                         # Extended documentation
    └── troubleshooting.md
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## Legal Notice

This project does **not** include, distribute, or facilitate piracy of Microsoft Office.
You must supply your own official installer and valid Microsoft 365 subscription.

Microsoft Office and its trademarks are property of Microsoft Corporation.

## License

[MIT License](LICENSE) — see file for details.
