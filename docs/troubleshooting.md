# Troubleshooting Guide

## Installation Issues

### "ODT not found or not verified"
- Ensure `OfficeSetup.exe` is in `~/Downloads/`.
- Verify it by running: `wine ~/Downloads/OfficeSetup.exe /help`
- You should see `Office Deployment Tool` in the output.
- If not, re-download from: https://www.microsoft.com/en-us/microsoft-365/download-office

### "ODT /download failed"
- Check your internet connection. The download is ~4-5 GB.
- Ensure you have at least 10 GB of free disk space.
- The ODT caches files to `~/Downloads/OfficeCache/`.

### "ODT /configure failed"
- Ensure the `~/Downloads/OfficeCache/` folder exists and is not empty.
- Ensure your Wine prefix is healthy: `WINEPREFIX=~/.Microsoft_Office_365 wine wineboot -u`
- If the prefix is corrupted, run `./uninstall.sh` then `./install.sh` again.

### "Office installer failed" (legacy message for old ODT stubs)
- If you are using an old consumer `Setup.exe` instead of the ODT, it will fail under Wine due to COM/DCOM limitations.
- **Solution:** Use the official ODT `OfficeSetup.exe` from Microsoft's download page.

### "WINWORD.EXE not found after installation"
- The installer may have placed files in a slightly different path.
- Check:
  - `~/.Microsoft_Office_365/drive_c/Program Files/Microsoft Office/root/Office16/`
  - `~/.Microsoft_Office_365/drive_c/Program Files (x86)/Microsoft Office/root/Office16/`
- If found elsewhere, edit the corresponding wrapper in `/opt/launchers/`.

## Runtime Issues

### Wine crashes or freezes
- Kill all Wine processes: `./uninstall.sh` (or manually `pkill -9 wine`)
- Restart and try again.
- Consider updating Wine: `sudo apt upgrade wine64 wine32`

### Fonts look wrong or missing
- Run `sudo fc-cache -fv` to refresh the font cache.
- Ensure `ttf-mscorefonts-installer` is installed.

### "Cannot find wineserver"
- Ensure `wine64` and `wine32` packages are installed.
- Run `which wine` to verify it is in your PATH.

## Cache Management

### "Can I delete the OfficeCache folder?"
- Yes, after successful installation. The script will ask you automatically.
- If you delete it and later need to repair Office, the ODT will re-download everything.

## Getting Help

- Open a [GitHub Issue](https://github.com/aldobox/Office365LinuxInstaller/issues) (redact personal info).
- Include: distribution, Wine version, and terminal output.
