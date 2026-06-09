#!/usr/bin/env bash
# Debug launcher for install.sh — captures all output while preserving terminal for sudo
# Usage: ./install-debug.sh

LOG_DIR="${HOME}/Desktop/Development/Apps/Office-365-Linux/debug/logs"
mkdir -p "${LOG_DIR}"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/install-debug-${TIMESTAMP}.log"
ENV_FILE="${LOG_DIR}/install-env-${TIMESTAMP}.log"

echo "========================================"
echo "  Debug Launch: $(date)"
echo "  Log: ${LOG_FILE}"
echo "========================================"
echo ""

# Capture environment first (no sudo needed)
echo "--- Environment ---" > "${ENV_FILE}"
env | sort >> "${ENV_FILE}"
echo "--- Wine Version ---" >> "${ENV_FILE}"
wine --version >> "${ENV_FILE}" 2>&1 || echo "wine not in PATH" >> "${ENV_FILE}"
echo "--- Winetricks Version ---" >> "${ENV_FILE}"
winetricks --version >> "${ENV_FILE}" 2>&1 || echo "winetricks not in PATH" >> "${ENV_FILE}"
echo "--- System ---" >> "${ENV_FILE}"
uname -a >> "${ENV_FILE}"
cat /etc/os-release >> "${ENV_FILE}" 2>/dev/null || true

echo "Environment captured to: ${ENV_FILE}"
echo ""

# Run installer with bash -x trace, using 'script' to preserve pseudo-TTY for sudo
cd "${HOME}/Desktop/Development/Apps/Office-365-Linux"
echo "Starting install.sh with bash -x trace..."
echo "All output is being captured to: ${LOG_FILE}"
echo ""

# Use 'script' to create a pseudo-tty — this allows sudo to work while capturing everything
script -q -c "bash -x ./install.sh" "${LOG_FILE}"

EXIT_CODE=$?

echo ""
echo "========================================"
echo "  Exit code: ${EXIT_CODE}"
echo "  Finished: $(date)"
echo "========================================"

if [ ${EXIT_CODE} -ne 0 ]; then
    echo ""
    echo "--- CRASH DETECTED ---"
    echo "Installer exited with code ${EXIT_CODE}."
    echo "Last 50 lines of log:"
    tail -n 50 "${LOG_FILE}"
    echo ""
    echo "Full log saved to: ${LOG_FILE}"
    echo "Please share ${LOG_FILE} for diagnosis."
else
    echo ""
    echo "Installation completed successfully."
    echo "Full log saved to: ${LOG_FILE}"
fi
