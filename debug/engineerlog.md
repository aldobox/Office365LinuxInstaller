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
