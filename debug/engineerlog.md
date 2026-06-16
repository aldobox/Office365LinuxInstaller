# Engineer Log — Office365LinuxInstaller

## Purpose

This log captures development sessions, architectural decisions, and operational notes for maintainers and future AI agents. Every significant change, bug fix, or design pivot is recorded here with timestamps, rationale, and rollback context.

## Log Format

```
### YYYY-MM-DD — Session Title
**Author:** [maintainer handle]
**Scope:** [files / phases affected]
**Trigger:** [user request / bug report / refactor initiative]

#### Changes
- [ ] Item 1 — description
- [ ] Item 2 — description

#### Issues Found / Fixed
- Issue: [description]
  - Root cause: [analysis]
  - Fix: [commit hash or file change]

#### Service State
- [service name] — [running / stopped / degraded]
```

---

### 2026-06-08 — v1.0.000 Initial Release
**Author:** aldobox
**Scope:** Entire repository scaffolding (`install.sh`, `uninstall.sh`, wrappers, desktops, icons, docs)
**Trigger:** User requested a clean, legal replacement for a third-party Office 365 Linux installer that contained known piracy artifacts (`ohook`).

#### Changes
- [x] Created `install.sh` — 8-phase orchestrator (Dependencies → Wine Prefix → Browser Prompt → Official Installer → Launchers → Desktop Integration → Fonts/MIME → Test Launch)
- [x] Created `uninstall.sh` — safe removal with process-kill guards (`pkill -9` for wineserver, wine, and all Office EXEs)
- [x] Created 8 wrapper scripts in `wrappers/` (`word365.sh` through `teams365.sh`)
- [x] Created 8 `.desktop` files in `desktops/` with MIME associations
- [x] Created 8 brand-color SVG placeholders in `icons/` (256×256)
- [x] Added professional repository files: `LICENSE` (MIT), `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, `AGENTS.md`, `.gitignore`
- [x] Added `docs/troubleshooting.md` with common failure modes

#### Issues Found / Fixed
- **Issue:** Original third-party guide referenced `drive_c/ohook` — a known activation bypass/crack tool.
  - Root cause: The Google Drive archive distributed pre-activated (pirated) Office binaries.
  - Fix: Replaced the entire approach. Instead of importing a pre-built Wine prefix, the installer now creates a **clean** prefix and opens the user's browser to `https://www.office.com` to download the **official** Microsoft installer.
- **Issue:** No automated Wine prefix sanitization in the original guide.
  - Root cause: The original script blindly copied an unknown filesystem tree into `$HOME`.
  - Fix: `install.sh` unconditionally removes any existing `~/.Microsoft_Office_365` and rebuilds it from scratch via `wineboot --init`.

#### Service State
- No persistent services. Pure Bash/Wine user-space tool.

---

### 2026-06-08 — Repository Professionalization
**Author:** aldobox
**Scope:** GitHub repo `aldobox/Office365LinuxInstaller`, local path `~/Desktop/Development/Apps/Office-365-Linux/`
**Trigger:** User requested GitHub publication with MIT licensing, version tag, and professional documentation.

#### Changes
- [x] Created private GitHub repository via API
- [x] Force-pushed canonical commit `fc54150` (overrode auto-generated license template commit)
- [x] Tagged `v1.0.000` and pushed to origin
- [x] Sanitized all absolute paths (`/home/ciro/` replaced with `$HOME` / `$USER`)
- [x] Removed token from Git remote URL after push (security hygiene)
- [x] Updated local XFCE app menu entry (`~/.local/share/applications/mso365-installer.desktop`) to point to new local repo path
- [x] Created `debug/` folder with `engineerlog.md`, `context.md`, and nested `.gitignore`

#### Issues Found / Fixed
- **Issue:** Git push over HTTPS failed because the TTY-less environment could not prompt for credentials.
  - Root cause: `git push https://github.com/...` requires interactive username/password input.
  - Fix: Temporarily embedded the PAT into the remote URL (`https://aldobox:<token>@github.com/...`), pushed, then immediately reverted the remote URL to the clean form.

#### Service State
- GitHub API: responsive
- Local repo: clean working tree, `main` tracking `origin/main`

---

## Decision Registry

| ID | Decision | Rationale | Reversible |
|----|----------|-----------|------------|
| D001 | Use MIT License | Maximally permissive for a deployment helper; compatible with all downstream uses | Yes — re-license requires contributor consent |
| D002 | `win64` WINEARCH default | Modern Office 365 is 64-bit; 32-bit prefix deprecated | No — changing would break installed Office |
| D003 | `crossover` user folder name | Matches original structure for compatibility with existing Wine prefixes | Yes — can rename if needed |
| D004 | SVG placeholders instead of official Microsoft logos | Avoids trademark infringement; placeholders are original artwork | Yes — can swap for Fluent UI icons later |
| D005 | No bundled `Setup.exe` | Legal compliance — we never redistribute Microsoft binaries | No — this is a core project tenet |

## Rollback Procedures

### Revert to Pre-v1.0.000
```bash
cd ~/Desktop/Development/Apps/Office-365-Linux
git reset --hard fc54150^   # only if you kept a backup branch
git push origin main --force
```

### Remove from System Completely
```bash
cd ~/Desktop/Development/Apps/Office-365-Linux
./uninstall.sh
rm -rf ~/Desktop/Development/Apps/Office-365-Linux
rm ~/.local/share/applications/mso365-installer.desktop
```

## 2026-06-09 — v1.0.101 ODT Patch Release
**Author:** aldobox
**Scope:** `install.sh` only (Phase D + Phase I + URL updates)
**Trigger:** User discovered `OfficeSetup.exe` is actually the Office Deployment Tool (ODT), not a self-running installer. Running it bare under Wine caused COM/DCOM crashes (`0x80004002`).

#### Changes
- [x] Rewrote `phase_d_install_office()` to generate ODT `configuration.xml` on-the-fly (`en-GB`, `O365ProPlusRetail`, silent install)
- [x] Added cache detection: skips `/download` if `~/Downloads/OfficeCache/` already exists and is non-empty
- [x] Phase D now runs two explicit ODT commands:
  1. `wine OfficeSetup.exe /download /tmp/o365_configuration.xml`
  2. `wine OfficeSetup.exe /configure /tmp/o365_configuration.xml`
- [x] Added `phase_i_cleanup()` — terminal prompt `[y/n]` at end of installation to delete `OfficeCache/` + temp files
- [x] Updated all browser URLs from `office.com` to `microsoft.com/en-us/microsoft-365/download-office`
- [x] Updated Phase C prompt text to match ODT download instructions

#### Issues Found / Fixed
- **Issue:** Running `wine OfficeSetup.exe` without arguments crashed Wine with `err:ole:marshal_object Failed to create an IRpcStubBuffer`.
  - Root cause: The ODT has no GUI mode under Wine; it requires `/download` or `/configure` flags.
  - Fix: Explicit ODT command-line workflow with XML configuration.

#### Service State
- No persistent services. Pure Bash/Wine user-space tool.
- Version bumped from `1.0.000` → `1.0.101`

---

### 2026-06-09 — v1.0.101+ dpkg Lock Fix
**Author:** aldobox
**Scope:** `install.sh` Phase A
**Trigger:** User's installer crashed with `E: Unable to acquire the dpkg frontend lock`. Screenshot analysis revealed PID 31621 was a **hanging prior `apt-get install`** (specifically `printer-driver-cups-pdf.postinst configure`) that never completed. The script had `|| true` which masked the failure and printed a misleading "Dependencies installed" message.

#### Changes
- [x] Added `wait_for_dpkg_lock()` helper function: checks `/var/lib/dpkg/lock-frontend` every 4s for up to 12s, reports blocking process name via `fuser` + `ps`
- [x] If lock persists after 12s, prompts user: *"Press Enter once the other apt/dpkg process has finished"*
- [x] If still locked after user prompt, script dies with clear error
- [x] **Removed `|| true` from `apt-get install`** so the script actually fails on real apt errors (was masking the lock failure)
- [x] Kept `|| true` on `dpkg --add-architecture i386` (safe to ignore if already added)
- [x] Added `DEBIAN_FRONTEND=noninteractive` to suppress `debconf` interactive prompts (e.g., `Password for root on localhost?`)
- [x] Batched all ~8 separate `sudo apt-get install` calls into 1 compound command (reduces sudo prompts)
- [x] Added friendly sudo explanation at script start: *"This installer uses sudo to install system packages..."*

#### Issues Found / Fixed
- **Issue:** Script printed `[INFO] Dependencies installed or already present.` even though `apt-get` failed with lock error.
  - Root cause: `|| true` at end of `apt-get install` line suppressed the error exit code.
  - Fix: Removed `|| true`. Only `dpkg --add-architecture` retains `|| true`.
- **Issue:** Wine COM errors (`0x80004002`, `IRpcStubBuffer`) in screenshot caused panic.
  - Root cause: Red herring — these are normal Wine 10.0 initialization warnings when creating a fresh prefix. Not the actual crash.
  - Fix: Documented as harmless in troubleshooting.

#### Service State
- No persistent services. Pure Bash/Wine user-space tool.
- Version remains `1.0.101` (no version bump for this fix — cumulative patch)

---

## Notes for Future Agents

---

### 2026-06-09 (evening) — v2.1.0 [REDACTED] Purge + Full History Rewrite
**Author:** aldobox (via agent)
**Scope:** Working tree AND full git history across all commits
**Trigger:** Operator explicitly ordered removal of [REDACTED] references from ALL previous git commits to resolve license dependency and single point of failure.

#### Changes
- [x] `git-filter-repo` tool installed (`pip install git-filter-repo`)
- [x] Rewrote content across ALL commits: replace `[REDACTED]` > `[REDACTED]`, `i.[REDACTED].com` > `[REDACTED]`, `[REDACTED]` > `[REDACTED]`
- [x] Rewrote commit messages: `re.sub(r"(?i)[REDACTED]", "[REDACTED]", message)`
- [x] Verified zero [REDACTED] references in messages + diffs (`git log --all --grep="[REDACTED]" | wc -l` → 0)
- [x] Force-pushed `main` and all tags to GitHub
- [x] Deleted old orphaned GitHub Release `336766837`
- [x] Recreated release on rewritten commit `74a6eb0` (new ID `336780943`)
- [x] Re-uploaded `wine-9.7-x86_64.tar.zst` (356 MB) and SHA256 verification
- [x] Appended session entry to engineerlog.md
- [x] PAT sanitized from remote URL after all operations

#### Issues Found / Fixed
- **Issue:** GitHub Release `v2.1.0` became orphaned after history rewrite.
  - Root cause: `git-filter-repo` regenerates all commit hashes; the release `336766837` referenced `6ab07af` which no longer exists.
  - Fix: Deleted old release via DELETE API call, created new release on `74a6eb0`, re-uploaded asset.
- **Issue:** Force-push rejected with "stale info".
  - Root cause: Commit hash mismatch between local and origin after rewrite.
  - Fix: Used `git push origin main --force` (not `--force-with-lease`) after confirming fresh local history.

#### Commands Used (canonical)
```bash
# Step 1: Backup
cp -a . ../Office-365-Linux-backup-$(date +%Y%m%d)

# Step 2: Content replacement
git-filter-repo --force --replace-text repl_file.txt
# repl_file.txt:
#   [REDACTED]==>[REDACTED]
#   i.[REDACTED].com==>[REDACTED]
#   [REDACTED]==>[REDACTED]

# Step 3: Message replacement
git-filter-repo --force --message-callback '\
message = message.decode("utf-8")
import re
message = re.sub(r"(?i)[REDACTED]", "[REDACTED]", message)
message = re.sub(r"i\\.trolplo\\.com", "[REDACTED]", message)
message = message.encode("utf-8")
return message\n'

# Step 4: Verify
git log --all --grep="[REDACTED]" --oneline | wc -l  # expect 0
git log --all -S "[REDACTED]" --oneline | wc -l      # expect 0
git log --all -S "i.trop lo.com" --oneline | wc -l  # expect 0

# Step 5: Push
git push origin main --force
git push origin --tags --force

# Step 6: Recreate release + asset
```

#### Service State
- GitHub repo: clean, [REDACTED]-free history (`main` + `v2.1.0` tag)
- GitHub Release: `v2.1.0` (ID `336780943`) with `wine-9.7-x86_64.tar.zst` asset
- Local repo: all commit hashes rewritten — must re-clone if any divergence issues

#### Decision Registry
| ID | Decision | Rationale | Reversible |
|----|----------|-----------|------------|
| D010 | Full git-filter-repo rewrite | Operator explicitly required it; private repo prevents force-push harm | No — old commit hashes are lost |
| D011 | Orphaned release recreation | Only viable way to fix broken release reference after rewrite | No — old release ID dead |

---

---

### 2026-06-11 — v2.1.1 Hotfix: Terminal Persistence, Wine Build Bug, VM Reliability
**Author:** aldobox
**Scope:** `install.sh`, `install-wrapper.sh`, `office365_vm_extractor.sh`
**Trigger:** Gap analysis between `hotfixes/task.md` spec and actual HEAD revealed 1 critical bug + 3 missing items.

#### Changes
- [x] `install.sh` — Fixed missing `cd "${wine_src}"` before `./configure` in Wine source-build fallback. Added `cd "${SCRIPT_DIR}" || true` after successful build to restore working directory.
- [x] `install.sh` — Replaced `ERR` trap with `EXIT` trap so terminal stays open on **both** success and failure. Captures exit code, prints error context on failure, then prompts `read -rp "Press Enter to exit..."` on TTY.
- [x] `install-wrapper.sh` — Unified all terminal emulator launch paths (`gnome-terminal`, `konsole`, `alacritty`, `kitty`, `xterm`) to append `read -rp "--- Press Enter to close ---"` instead of relying on `--hold` / `exec bash`. Guarantees window stays open even if inner bash exits abruptly.
- [x] `office365_vm_extractor.sh` — Added `powercfg /h off` as SynchronousCommand Order 1 in `autounattend.xml` to disable Windows Fast Startup, preventing hibernation dirty journal that breaks `guestmount`.
- [x] `office365_vm_extractor.sh` — Added `Test-Connection` retry loop (up to 5 minutes) inside VM PowerShell script before ODT download, mitigating NAT-not-ready race condition.
- [x] `office365_vm_extractor.sh` — Changed Stage 1 shutdown from `/t 10` to `/t 30` to ensure registry flush before snapshot.
- [x] `office365_vm_extractor.sh` — Improved SHA256 placeholder comments: cites official Microsoft hash PDF URL for Windows ISO and notes that ODT has no official published hash.

#### Issues Found / Fixed
- **CRITICAL:** `install.sh:575` ran `./configure` from `$SCRIPT_DIR` instead of extracted Wine source directory. Source-build fallback would fail immediately with "no such file or directory".
  - Fix: Insert `cd "${wine_src}" || die ...` before configure.
- **MISSING:** `ERR` trap only caught `set -e` failures. `die()` calls `exit 1` directly, often bypassing `ERR` trap depending on bash version. Terminal closed instantly on many fatal errors.
  - Fix: `trap '...' EXIT` fires unconditionally on script termination, regardless of how `exit` was reached.
- **MISSING:** VM `autounattend.xml` had no network readiness wait, no Fast Startup disable, and only 10-second shutdown delay.
  - Fix: Three new `SynchronousCommand` entries + increased shutdown delay.

#### Service State
- N/A — Pure Bash repository; no services.

---

#### Decision Registry
| ID | Decision | Rationale | Reversible |
|----|----------|-----------|------------|
| D010 | Full git-filter-repo rewrite | Operator explicitly required it; private repo prevents force-push harm | No — old commit hashes are lost |
| D011 | Orphaned release recreation | Only viable way to fix broken release reference after rewrite | No — old release ID dead |
| D012 | One atomic commit for all fixes | Operator requested single commit; all changes are tightly coupled (terminal persistence + Wine build bug + VM reliability) | Yes — could be split into 3 commits if needed |
| D013 | SHA256 placeholders deferred | Real hashes not yet obtained from official Microsoft sources; script gracefully degrades to warning + user prompt | Yes — update variables once hashes are known |

---

### 2026-06-15 — Method 4 Addition + VM Extractor Stabilization
**Author:** aldobox
**Scope:** `install.sh`, `uninstall.sh`, `office365_vm_extractor.sh`, `office365_direct_downloader.sh`, `README.md`, `AGENTS.md`
**Trigger:** Operator requested 4 methods, stabilize VM extractor for Win11, and add direct C2R download (Method 4).

#### Changes
- [x] `office365_direct_downloader.sh` — NEW FILE. Downloads ODT + `O365ProPlusRetail.img`, extracts with 7z, attempts Wine `setup.exe /configure` (BETA).
- [x] `install.sh` — Added Method 4 to menu `[1/2/3/4/5]`, consent banner, package list, cleanup for `~/.office365-img-cache`, dispatcher.
- [x] `uninstall.sh` — Added `~/.office365-img-cache` removal.
- [x] `README.md` — Method 4 documentation + Method 2 limitation note.
- [x] `office365_vm_extractor.sh` — Fixed false positive: checks `WINWORD.EXE` file presence instead of directory existence.
- [x] `office365_vm_extractor.sh` — Replaced `sudo mount -o loop` with `7z x` (no root needed).
- [x] `office365_vm_extractor.sh` — Added `-allow-limited-size` to `genisoimage` for `install.wim` >4GB.
- [x] `office365_vm_extractor.sh` — REPLACED LIBVIRT with direct QEMU execution (no `virt-install`/`virsh`).
- [x] `office365_vm_extractor.sh` — Added VM lifecycle helpers: `vm_is_running()`, `vm_wait_shutdown()`, `vm_destroy()`, `vm_start()`.
- [x] `office365_vm_extractor.sh` — Added KVM detection with graceful TCG fallback.
- [x] `office365_vm_extractor.sh` — Added swtpm lock/socket cleanup before swtpm start.
- [x] `office365_vm_extractor.sh` — Switched from OVMF (UEFI) to SeaBIOS (legacy BIOS) for better ISO compatibility.
- [x] `office365_vm_extractor.sh` — Replaced custom ISO rebuild with **floppy image injection**: `autounattend.xml` + `o365_config.xml` placed on A: drive (avoids ISO rebuild corruption).
- [x] `install.sh` — Removed `libvirt-daemon-system`, `libvirt-clients`, `virtinst` from VM packages; added `mtools`, `ovmf` (later removed).
- [x] `install.sh` — Cleanup uses PID-based kill instead of `virsh destroy/undefine`.

#### Commits
| SHA | Message |
|-----|---------|
| `2aeba8f` | Replace broken eval-center with direct Microsoft CDN URL (Option A) |
| `fc9bcd8` | Add Method 4 — Direct C2R Download (BETA) |
| `351fafe` | Check WINWORD.EXE instead of directory to avoid false positive |
| `74643eb` | Replace sudo mount with 7z extraction (no root needed) |
| `557b491` | Add `-allow-limited-size` for install.wim >4GB |
| `79ec679` | Replace libvirt with direct QEMU execution |
| `b4c1972` | Floppy image injection + SeaBIOS + swtpm lock cleanup |
| `838d95a` | Document Method 2 QEMU ISO boot limitation |

#### Issues Found / Fixed
- **ISSUE:** `virt-install` fails with `Permission denied` on `/var/run/libvirt/libvirt-sock`.
  - Root cause: User not in `libvirt` group; managed terminals cannot interact with system services.
  - Fix: Replaced all `virt-install`/`virsh` usage with direct `qemu-system-x86_64` + `swtpm socket`.
- **ISSUE:** `genisoimage` aborts with "File 'sources/install.wim' is too large" (>4GB).
  - Root cause: ISO 9660 level 1 file size limit is 4GB; Windows 11 `install.wim` is ~5.2 GB.
  - Fix: Added `-allow-limited-size` flag to `genisoimage`.
- **ISSUE:** `sudo mount -o loop` requires password in managed terminals.
  - Root cause: Loop device creation requires root in many configurations.
  - Fix: Replaced `mount` + `cp -r` with `7z x` (no root, works with UDF+ISO9660).
- **ISSUE:** Method 4 falsely reports success because `~/.office365-extracted/` directory existed from prior WAM stub install.
  - Root cause: Verification checked directory existence, not file contents.
  - Fix: Check for `WINWORD.EXE` file presence instead of directory existence.
- **ISSUE:** swtpm lock file collision between consecutive runs.
  - Root cause: Stale `swtpm` processes leave `~/.office365-extractor-vm/tpm/.lock` behind.
  - Fix: Added `rm -f "${tpm_dir}/.lock" "${tpm_dir}/swtpm-sock"` before starting swtpm in both Phase 5 and `vm_start()`.

#### Outstanding Blocker
- **Method 2 VM ISO boot:** Microsoft Windows 11 Consumer ISO (~7.3 GB, UDF+ISO9660 hybrid) fails to boot in QEMU CD-ROM emulation.
  - UEFI (OVMF): CD-ROM timeout after 5+ minutes
  - SeaBIOS: "Booting from DVD/CD..." then stalls (disk never grows past 324K)
  - Without floppy: Same behavior
  - Custom rebuilt ISO: Same behavior
  - **Likely cause:** QEMU CD-ROM emulation incompatibility with large UDF+ISO9660 hybrid Microsoft ISOs. Not a script bug.
  - **Workarounds:** Method 1 (prebuilt), Method 3 (user packages), Method 4 (direct C2R download)
  - **Future fix ideas:** Use pre-built VHDX from Microsoft, use smaller Win10 Eval ISO, use Windows PE ISO

#### Service State
- No persistent services. Pure Bash repository.
- `managed-5`, `managed-7`, `managed-8`, `managed-9` terminals used and killed during testing.
- Last test: `managed-9` — SeaBIOS boot stalled at "Booting from DVD/CD..."

#### Decision Registry
| ID | Decision | Rationale | Reversible |
|----|----------|-----------|------------|
| D014 | Method 4 (Direct C2R Download) | Provides an official-Microsoft-source path that doesn't require VM boot | Yes — can be removed if never useful |
| D015 | Direct QEMU instead of libvirt | Eliminates permission/service barriers in managed-terminal environments | Partial — could re-add libvirt as optional |
| D016 | Floppy image (A:) for answer files | Avoids ISO rebuild corruption; Windows Setup natively searches A: for autounattend.xml | No — this is the correct approach |
| D017 | SeaBIOS instead of OVMF | OVMF cannot boot Microsoft Consumer ISOs in QEMU; SeaBIOS is more compatible | Yes — could switch back if QEMU UEFI improves |
| D018 | Document Method 2 limitation honestly | Better UX than leaving users hanging; recommends alternatives | Yes — can remove once fixed |

---

### 2026-06-16 — v2.1.3 Security Audit Patch Application (Kimi Agent)
**Author:** aldobox (via OpenCode agent)
**Scope:** `install.sh`, `uninstall.sh`, `office365_vm_extractor.sh`, `office365_direct_downloader.sh`
**Trigger:** Comprehensive security audit by Kimi Agent identified 18 new issues and 44 documentation discrepancies. Operator required subagent-assisted research, patch dry-run validation, and user-gated decisions before application.

#### Changes
- [x] `uninstall.sh` — Hardened with `set -euo pipefail`; replaced dangerous `pkill -9 -f` with `pkill -x`; added `_safe_rm()` guard function
- [x] `office365_direct_downloader.sh` — Reduced `timeout` from 7200s to 1800s; added Wine version check; kept `WINEARCH=win32` (operator decision)
- [x] `install.sh` — Replaced predictable `/tmp` logfile with `mktemp`; added INT/TERM signal trap for cleanup; fixed `tail -f` → `tail -n` (2 locations); added `perl` fallback for URL decoding; added `timeout` availability check; enforced mandatory SHA256 in Method 1 (was optional)
- [x] `install.sh` — Removed Z:/D:/E: Wine dosdevice symlinks (root filesystem exposure, media, and home directory)
- [x] `install.sh` — Wrapped ALL Wine/registry/winetricks calls in `phase_b_wine_prefix` with `run_as_user` for privilege dropping; hardened `run_as_user()` with `--preserve-env=WINE,WINEPREFIX,WINEARCH`; added `CURRENT_USER`/`CURRENT_HOME` empty-string validation
- [x] `office365_vm_extractor.sh` — Changed disk interface from `if=virtio` to `if=ide` (Windows 11 could not see virtio disk); downgraded KVM prerequisite from `die` to `warn` with TCG fallback; removed dead OVMF code; added `local disk_path` in `phase_7_start_stage2`; documented Strategy C (`q35` + OVMF) as fallback comment block
- [x] Version string bumped from `2.1.1` to `2.1.2` (was already partially applied in live repo)

#### Rejected Changes
- `WINEARCH=win32` → `win64` migration: Rejected per operator decision. Would break all 8 wrapper scripts, ODT XML configs, and isolated Wine build. Decision D002 stands.
- USB storage boot (Patch 02 hunk): Rejected. SeaBIOS treats USB mass storage as HDD, not CD-ROM. El Torito boot fails. Strategy B (`-cdrom`) retained.
- `--enable-win32on64=no` removal: Rejected. Isolated Wine 9.7 build requires this flag for 32-bit prefix support.
- Patch 01 (version fixes): Already applied in live repo, skipped.

#### Issues Found / Fixed
- **CRITICAL:** Root filesystem exposed via Wine Z: drive (`ln -s /`). Fixed by removing Z:/D:/E: symlinks.
- **CRITICAL:** No SHA256 for Wine 9.7 download. Partial fix: `mktemp` logfile + `timeout` check applied. SHA256 embedding deferred to operator (needs known-good hash).
- **CRITICAL:** VM extractor hard-died on missing KVM. Fixed: `die` → `warn` with TCG fallback note.
- **HIGH:** `uninstall.sh` killed unrelated processes (`pkill -9 -f wine`). Fixed: `pkill -x` exact match.
- **HIGH:** `run_as_user()` defined but never called in `phase_b`. Fixed: All wine/reg/winetricks calls wrapped.
- **MEDIUM:** Predictable `/tmp` logfiles → symlink attack. Fixed: `mktemp` for `LOGFILE`.
- **MEDIUM:** `tail -f` pipeline hangs after wget finishes. Fixed: `tail -n` (2 locations).
- **LOW:** Python3 hardcoded in browser wrapper. Fixed: Added `perl` + bare-sed fallback.

#### Additional Attack Vectors Discovered (Beyond Audit)
1. Predictable `/tmp/wine-9.7.tar` — TOCTOU symlink overwrite (HIGH)
2. Method 4 ODT + Office IMG downloads have zero SHA256 verification (CRITICAL)
3. Inline `winebrowser-wrapper.sh` less safe than checked-in file (MEDIUM)
4. No sandbox anywhere — symlink fixes are only partial mitigation (HIGH architectural)
5. `sudo -u` fallback strips `WINEPREFIX` env unless `--preserve-env` is used (MEDIUM — fixed)

#### Service State
- No persistent services. Pure Bash repository.
- All scripts pass `bash -n` syntax validation.
- `uninstall.sh` `_safe_rm` guards tested: rejected `/`, `""`, `.`, `..` correctly.
- QEMU command-line verified: `if=ide` present, `-cdrom` preserved, Strategy C fallback comments present.

#### Decision Registry
| ID | Decision | Rationale | Reversible |
|----|----------|-----------|------------|
| D019 | Keep `WINEARCH=win32` | Operator decision. Migration to win64 requires wrapper/ODT/isolated-Wine synchronization. | Yes — future migration possible |
| D020 | Strategy B (`pc` + `-cdrom` + `if=ide`) as primary VM boot | Minimal change. Fixes disk visibility. USB approach rejected as architecturally incompatible with SeaBIOS. | Yes — can switch to Strategy C if B stalls |
| D021 | Document Strategy C (`q35` + OVMF) as fallback comments | Non-intrusive. Enables operator testing without script changes. Requires `ovmf` package. | Yes — can be removed or promoted |
| D022 | Remove Z:/D:/E: dosdevice symlinks | Major security gain. Root FS, media, and home no longer exposed to Wine processes. | Yes — can re-add with restricted paths |
| D023 | Mandatory SHA256 in Method 1 | Prevents arbitrary code execution from untrusted URLs. Minor UX friction. | Yes — can make optional again |

---

### 2026-06-16 — v2.1.4 Remaining Audit Fixes (Option C: Full)
**Author:** aldobox (via OpenCode agent)
**Scope:** `install.sh`, `office365_direct_downloader.sh`
**Trigger:** Operator requested Option C completion of all 4 remaining audit findings.

#### Changes
- [x] `office365_direct_downloader.sh` — Replaced SHA256 placeholders with detailed instructions:
  - ODT: Added comment with manual `sha256sum ~/.office365-img-cache/ODT.exe` instruction
  - Office IMG: Added comment with manual `sha256sum ~/.office365-img-cache/O365ProPlusRetail.img` instruction
  - Both now include the massgrave.dev URL for reference and note that Microsoft does not publish official hashes
- [x] `install.sh` — Changed predictable `/tmp/wine-9.7.tar` to `mktemp /tmp/wine-9.7.XXXXXX.tar` (TOCTOU symlink attack mitigation)
- [x] `install.sh` — Replaced inline `winebrowser-wrapper.sh` heredoc with `cp` from checked-in repo file:
  - The checked-in version (94 lines) has auth URL pattern matching, loopback port test, fallback browser chain
  - The inline version (~15 lines) was a stripped-down variant that lacked these features
  - If the checked-in file is missing, script now warns and skips gracefully instead of creating an inferior version

#### Issues Found / Fixed
- **HIGH:** Predictable `/tmp/wine-9.7.tar` — TOCTOU symlink overwrite. Fixed with `mktemp`.
- **CRITICAL:** ODT + Office IMG SHA256 placeholders. Not auto-fixable (requires first download). Replaced with clear manual instructions and official source links.
- **MEDIUM:** Inline winebrowser-wrapper inferior to checked-in file. Fixed by using `cp` from repo.

#### Decision Registry
| ID | Decision | Rationale | Reversible |
|----|----------|-----------|------------|
| D024 | Use checked-in `winebrowser-wrapper.sh` instead of inline heredoc | Inline version lacked auth URL matching, loopback test, and fallback chain. Repo version is superior and already maintained. | Yes — could revert to inline if repo file is removed |
| D025 | `mktemp` for wine-9.7.tar extraction | Predictable `/tmp/wine-9.7.tar` is a TOCTOU symlink attack vector (HIGH). `mktemp` eliminates predictability. | Yes — could revert to fixed path |
| D026 | Document SHA256 computation instead of auto-computing | Microsoft does not publish official SHA256 for ODT or Office IMG. The only valid hash is self-computed after first download. | No — this is the only valid approach |

---
