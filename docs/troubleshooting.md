# Troubleshooting Guide

## Installation Issues

### "No Setup.exe found"
- Ensure you downloaded the installer from [office.com](https://www.office.com) after signing in.
- The file may be named `OfficeSetup.exe` — both are detected automatically.
- Save it to `~/Downloads/` before pressing Enter in the installer.

### "Office installer failed"
- Check your Wine version: `wine --version`
- Update Wine: `sudo apt upgrade wine64 wine32`
- Ensure you have enough disk space (Office requires ~5-10 GB).

### "WINWORD.EXE not found after installation"
- The installer may have placed files in a different path.
- Check these locations:
  - `~/.Microsoft_Office_365/drive_c/Program Files/Microsoft Office/root/Office16/`
  - `~/.Microsoft_Office_365/drive_c/Program Files (x86)/Microsoft Office/root/Office16/`
- If found elsewhere, edit the corresponding wrapper in `/opt/launchers/`.

## Runtime Issues

### Wine crashes or freezes
- Kill all Wine processes: `./uninstall.sh` (or manually `pkill -9 wine`)
- Restart and try again.
- Consider updating Wine to the latest stable version.

### Fonts look wrong or missing
- Run `sudo fc-cache -fv` to refresh the font cache.
- Ensure `ttf-mscorefonts-installer` is installed.

### "Cannot find wineserver"
- Ensure `wine64` and `wine32` packages are installed.
- Run `which wine` to verify it's in your PATH.

## Uninstall Issues

### "Permission denied" during uninstall
- The uninstaller uses `sudo` for system directories. Ensure your user has sudo privileges.

## Getting Help

- Open a [GitHub Issue](https://github.com/aldobox/Office365LinuxInstaller/issues) (do not include personal info).
- Include: distribution name, Wine version, Office version, and relevant terminal output.
