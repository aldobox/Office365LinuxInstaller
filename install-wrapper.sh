#!/usr/bin/env bash
# install-wrapper.sh — Always allocates a real terminal for the installer
# If launched from a TUI (no TTY), opens a new terminal emulator window

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# If stdin is not a terminal (launched from TUI/file manager), open a new terminal
if [ ! -t 0 ] || [ ! -t 1 ]; then
    # Try to find a terminal emulator
    for term in gnome-terminal konsole alacritty kitty xterm; do
        if command -v "$term" >/dev/null 2>&1; then
            # Uniform command: run install.sh then prompt before close.
            # install.sh now has an EXIT trap that pauses on both success
            # and failure, but a second "read" here guarantees the window
            # stays open even if the inner bash exits abruptly.
            case "$term" in
                gnome-terminal)
                    exec gnome-terminal --wait --title="Office 365 Installer" \
                        -- bash -c "cd '$SCRIPT_DIR' && ./install.sh; echo; read -rp '--- Press Enter to close ---'; :"
                    ;;
                konsole)
                    exec konsole -e bash -c "cd '$SCRIPT_DIR' && ./install.sh; echo; read -rp '--- Press Enter to close ---'; :"
                    ;;
                alacritty|kitty)
                    exec "$term" -e bash -c "cd '$SCRIPT_DIR' && ./install.sh; echo; read -rp '--- Press Enter to close ---'; :"
                    ;;
                xterm)
                    exec xterm -T "Office 365 Installer" \
                        -e "bash -c 'cd \"$SCRIPT_DIR\" && ./install.sh; echo; read -rp \"--- Press Enter to close ---\"; :'"
                    ;;
            esac
            # exec replaces the current process, so we never reach here
        fi
    done

    # No terminal emulator found — try zenity warning
    if command -v zenity >/dev/null 2>&1; then
        zenity --error --text="No terminal emulator found.\n\nPlease run from a terminal:\ncd $SCRIPT_DIR \u0026\u0026 ./install.sh" 2>/dev/null || true
    else
        echo "ERROR: No terminal emulator found (tried: gnome-terminal, konsole, alacritty, kitty, xterm)." >&2
        echo "Please run from a terminal: cd $SCRIPT_DIR && ./install.sh" >&2
    fi
    exit 1
fi

# If we have a TTY, run the installer directly
cd "$SCRIPT_DIR" && exec ./install.sh
