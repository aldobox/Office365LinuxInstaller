# Project Manifest — Office365LinuxInstaller

## Repository Structure

```
Office365LinuxInstaller/
├── install.sh                    # Main installer (entry point)
├── uninstall.sh                  # Complete removal script
├── README.md                     # Project overview and quick-start guide
├── LICENSE                       # MIT License
├── MANIFEST.md                   # This file — directory structure documentation
├── MANIFEST.yaml                 # Machine-readable manifest (same content, YAML format)
│
├── AGENTS.md                     # AI agent context and contribution rules
├── CONTRIBUTING.md               # How to contribute, code style, issue reporting
├── SECURITY.md                   # Vulnerability reporting policy
├── CODE_OF_CONDUCT.md            # Community standards
│
├── .gitignore                    # Git exclusions (logs, caches, temp files)
│
├── wrappers/                     # Bash launcher scripts (8 apps)
│   ├── word365.sh
│   ├── excel365.sh
│   ├── powerpoint365.sh
│   ├── outlook365.sh
│   ├── access365.sh
│   ├── publisher365.sh
│   ├── onenote365.sh
│   └── teams365.sh
│
├── desktops/                     # XFCE/GNOME/KDE .desktop menu entries (8 apps)
│   ├── word365.desktop
│   ├── excel365.desktop
│   ├── powerpoint365.desktop
│   ├── outlook365.desktop
│   ├── access365.desktop
│   ├── publisher365.desktop
│   ├── onenote365.desktop
│   └── teams365.desktop
│
├── icons/                        # 256x256 SVG placeholder icons (8 apps)
│   ├── word365.svg
│   ├── excel365.svg
│   ├── powerpoint365.svg
│   ├── outlook365.svg
│   ├── access365.svg
│   ├── publisher365.svg
│   ├── onenote365.svg
│   └── teams365.svg
│
├── docs/                         # Extended documentation
│   └── troubleshooting.md        # Common issues and fixes
│
└── debug/                        # Development scratchpad
    ├── .gitignore                # Nested ignore rules for debug artifacts
    ├── engineerlog.md            # Session-by-session development log
    └── context.md                # Architecture, design philosophy, operational notes
```

---

## File Purpose Reference

| File | Purpose | When to Read / Edit |
|------|---------|---------------------|
| `install.sh` | Main orchestrator: dependencies → Wine prefix → ODT `/download` + `/configure` → system integration | Run to install. Edit for new Wine/ODT logic. |
| `uninstall.sh` | Safe removal: kills processes → deletes prefix → removes system files | Run to uninstall. Edit if new system paths are added. |
| `README.md` | Public-facing project overview, requirements, quick-start | Edit when workflow changes (e.g., new ODT behavior). |
| `LICENSE` | MIT License text | Do not edit without legal review. |
| `MANIFEST.md` | This document — human-readable directory tree and file purpose map | Edit when files/folders are added, removed, or renamed. |
| `MANIFEST.yaml` | Machine-readable version of this manifest | Edit in parallel with `MANIFEST.md`. |
| `AGENTS.md` | AI agent instructions: build steps, critical rules (no piracy, no hardcoded paths), architecture | Edit when agent workflow or project identity changes. |
| `CONTRIBUTING.md` | Guidelines for external contributors: code style, issue templates, PR process | Edit when contribution workflow changes. |
| `SECURITY.md` | Scope, supported versions, vulnerability reporting procedure | Edit when security scope or contact methods change. |
| `CODE_OF_CONDUCT.md` | Community behavior standards | Rarely edited. |
| `.gitignore` | Excludes: logs, temp files, Wine backups, `OfficeSetup.exe`, `OfficeCache/`, IDE configs | Edit when new temporary artifacts are generated. |
| `debug/.gitignore` | Additional exclusions for `debug/` folder: session dumps, `.env.local`, scratch files | Edit for local debug tooling. |
| `debug/engineerlog.md` | Chronological log of development sessions, decisions, bugs fixed, rollbacks | Append after every significant session. Do not delete old entries. |
| `debug/context.md` | Living document: genesis, design philosophy, architecture diagram, compatibility matrix, dependencies, security, roadmap, glossary | Edit when architecture, dependencies, or roadmap changes. |
| `docs/troubleshooting.md` | FAQ for end-users: installer errors, runtime crashes, font issues, ODT-specific problems | Edit when new failure modes are discovered. |

---

## Runtime Directories (Created During Installation, Not in Repo)

These paths are managed by `install.sh` and `uninstall.sh` but are **not** part of the Git repository:

| Path | Created By | Removed By | Contents | Size |
|------|-----------|-----------|----------|------|
| `~/.Microsoft_Office_365` | `install.sh` Phase B | `uninstall.sh` | Wine prefix (registry, `drive_c/`, dosdevices) | 1-2 GB |
| `/opt/launchers/` | `install.sh` Phase E | `uninstall.sh` | Bash wrapper scripts (`*365.sh`) | - |
| `/usr/share/applications/` | `install.sh` Phase F | `uninstall.sh` | `.desktop` menu entries | - |
| `/usr/share/icons/hicolor/256x256/apps/` | `install.sh` Phase F | `uninstall.sh` | SVG icons | - |
| `/usr/share/fonts/Windows/` | `install.sh` Phase G | `uninstall.sh` | Bundled Microsoft-compatible fonts | - |
| `~/Downloads/OfficeCache/` | `install.sh` Phase D (`/download`) | `uninstall.sh` or Phase I prompt | ODT-downloaded Office binaries | 4-5 GB |
| `/tmp/o365_configuration.xml` | `install.sh` Phase D | `uninstall.sh` or Phase I prompt | Auto-generated ODT configuration | - |
| `~/.cache/winetricks/` | `winetricks` during Phase B | `uninstall.sh` | Cached Windows libraries (fonts, DLLs) | 1-2 GB |

---

## Version History

| Version | Date | Key Changes |
|---------|------|-------------|
| 1.0.000 | 2026-06-08 | Initial release — browser-prompt installer, Wine prefix setup, launchers, MIME |
| 1.0.101 | 2026-06-09 | ODT-aware Phase D (`/download` + `/configure`), cache detection, cleanup prompt `[y/n]`, URL fix to `microsoft.com/.../download-office`, `cups-pdf` removal |

---

*This manifest is canonical. Update it when the directory structure changes.*
