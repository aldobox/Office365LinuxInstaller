# Office365LinuxInstaller

Clean, legal Microsoft Office 365 (Desktop) installation via Wine on Ubuntu / Debian-based distributions (Xubuntu, Linux Mint, Pop!_OS, etc.).

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Version](https://img.shields.io/badge/version-1.0.000-blue.svg)](https://github.com/aldobox/Office365LinuxInstaller/releases/tag/v1.0.000)

## What This Is

This project provides an automated installer that:
1. Installs Wine, Winetricks, and all required dependencies.
2. Creates a **clean** Wine prefix at `~/.Microsoft_Office_365`.
3. Opens your browser to [microsoft.com/en-us/microsoft-365/download-office](https://www.microsoft.com/en-us/microsoft-365/download-office) so you can **download the official Office Deployment Tool (ODT)** and use it to install Office.
4. Installs that official binary into the Wine prefix.
5. Creates app menu entries, file associations, and launchers for **Word, Excel, PowerPoint, Outlook, Access, Publisher, OneNote, and Teams**.

**No cracked, pre-activated, or pirated binaries are included or referenced.**

## Requirements

- Ubuntu / Debian / Linux Mint / Xubuntu (or derivative)
- Active **Microsoft 365 subscription** (Personal, Family, or Business)
- Internet connection (to download the official installer from Microsoft)
- `sudo` privileges (for installing system packages, fonts, and icons)

## Quick Start

1. **Clone or download** this repository:
   ```bash
   git clone https://github.com/aldobox/Office365LinuxInstaller.git
   cd Office365LinuxInstaller
   ```
2. **Download the Office Deployment Tool (ODT):**
   - Visit [microsoft.com/en-us/microsoft-365/download-office](https://www.microsoft.com/en-us/microsoft-365/download-office)
   - Click **"Download for Windows"**
   - Save `OfficeSetup.exe` to your `~/Downloads/` folder (~7 MB)
3. **Run the installer:**
   ```bash
   ./install.sh
   ```
4. The script will detect your system state, install only missing components, download Office binaries (~4-5 GB), and install them into a clean Wine prefix.
5. After installation, the script will ask if you want to delete the download cache to save disk space.
6. Once complete, find your Office apps in the system application menu.

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

- **"Office installer failed"**: Ensure you downloaded the correct `Setup.exe` from [office.com](https://www.office.com) after signing in.
- **"WINWORD.EXE not found"**: Check `~/.Microsoft_Office_365/drive_c/Program Files/Microsoft Office/root/Office16/`.
- **Fonts look odd**: Run `sudo fc-cache -fv` after installation.
- **Wine crashes**: Keep Wine updated (`sudo apt upgrade wine64 wine32`).

For more details, see [docs/troubleshooting.md](docs/troubleshooting.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## Legal Notice

This project does **not** include, distribute, or facilitate piracy of Microsoft Office.
You must supply your own official installer and valid Microsoft 365 subscription.

Microsoft Office and its trademarks are property of Microsoft Corporation.

## License

[MIT License](LICENSE) — see file for details.
