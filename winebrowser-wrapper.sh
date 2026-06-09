#!/bin/bash
# MSAL Browser Fallback Handler for Wine
# Intercepts browser launch from MSAL inside Wine and routes to Linux browser
# This enables Microsoft account login on Wine by forcing MSAL to use
# browser-based OAuth2 instead of WAM (Windows Authentication Manager).
#
# How it works:
# 1. Office app (Word/Excel) calls MSAL to sign in
# 2. MSAL detects "Windows 8.1" (no WAM available) → falls back to browser
# 3. MSAL opens socket on 127.0.0.1:PORT and calls ShellExecute(auth_url)
# 4. Wine looks up HKEY_CLASSES_ROOT\http\shell\open\command → this script
# 5. This script opens the URL in the Linux browser via xdg-open
# 6. User logs in, Microsoft redirects to http://localhost:PORT/?code=...
# 7. Browser sends GET to 127.0.0.1:PORT — MSAL socket receives it
# 8. MSAL exchanges code for token, stores in cache
# 9. Office app continues with authenticated session

URL="${1:-}"
LOGFILE="/tmp/office_auth_url.log"
WINE_USER_HOME="${WINEPREFIX:-${HOME}/.Microsoft_Office_365}"

# Log everything for debugging
echo "[$(date '+%Y-%m-%d %H:%M:%S')] PID=$$ URL=$URL" >> "$LOGFILE"

# If no URL provided, just exit
[[ -z "$URL" ]] && exit 0

# Check if this is a Microsoft auth URL
if echo "$URL" | grep -qiE "(login\.microsoftonline\.com|login\.live\.com|accounts\.google\.com|github\.com/login)"; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Auth URL detected." >> "$LOGFILE"

    # Extract redirect_uri to know what port MSAL is listening on
    if echo "$URL" | grep -q "redirect_uri"; then
        # Try to extract and URL-decode the redirect_uri
        REDIRECT_URI=$(echo "$URL" | sed -n 's/.*redirect_uri=\([^&]*\).*/\1/p')
        if [[ -n "$REDIRECT_URI" ]]; then
            # URL-decode manually (common substitutions)
            REDIRECT_URI=$(echo "$REDIRECT_URI" | sed 's/%3A/:/g; s/%2F/\//g; s/%3F/?/g; s/%3D/=/g; s/%26/\&/g')
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Redirect URI: $REDIRECT_URI" >> "$LOGFILE"

            # Extract port from http://localhost:PORT
            PORT=$(echo "$REDIRECT_URI" | grep -oP 'http://localhost:\K\d+' || true)
            if [[ -n "$PORT" ]]; then
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] MSAL listening on port: $PORT" >> "$LOGFILE"

                # Verify localhost is reachable (loopback test)
                if command -v curl >/dev/null 2>&1; then
                    # Do a quick HEAD to verify the port is open
                    if curl -s -o /dev/null --connect-timeout 2 "http://127.0.0.1:${PORT}" 2>/dev/null; then
                        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Loopback port $PORT is reachable ✓" >> "$LOGFILE"
                    else
                        echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: Loopback port $PORT may be isolated. Trying anyway..." >> "$LOGFILE"
                    fi
                fi
            fi
        fi
    fi

    # Open the auth URL in the Linux default browser
    if command -v xdg-open >/dev/null 2>&1; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Opening via xdg-open..." >> "$LOGFILE"
        xdg-open "$URL" &
    elif command -v firefox >/dev/null 2>&1; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Opening via firefox..." >> "$LOGFILE"
        firefox "$URL" &
    elif command -v google-chrome >/dev/null 2>&1; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Opening via google-chrome..." >> "$LOGFILE"
        google-chrome "$URL" &
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: No browser found to open $URL" >> "$LOGFILE"
        echo "Please manually open this URL in your browser:" >&2
        echo "$URL" >&2
    fi

    # The callback will come back to localhost:PORT
    # MSAL inside Wine is already listening on that socket
    # Since Wine 9.7 shares 127.0.0.1 with the host, the browser's redirect
    # will reach MSAL's socket directly. We don't need to proxy it.
    exit 0
fi

# For non-auth URLs, just open normally via Wine's default chain
if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$URL" &
disown 2>/dev/null || true
else
    # Fallback: try to use winebrowser.exe (Wine builtin)
    if command -v winebrowser >/dev/null 2>&1; then
        winebrowser "$URL" &
disown 2>/dev/null || true
    else
        echo "No browser available to open: $URL" >&2
        exit 1
    fi
fi
