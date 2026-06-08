#!/bin/sh
# kai installer — installs kai to ~/.kai, mirrors oh-my-zsh install pattern.
#
# Usage (one-liner):
#   sh -c "$(curl -fsSL https://raw.githubusercontent.com/BrachioLab/kai/main/install.sh)"
set -e

KAI_HOME="${HOME}/.kai"
KAI_BIN="${KAI_HOME}/bin"
KAI_SCRIPT_URL="https://raw.githubusercontent.com/BrachioLab/kai/main/kai"

echo "Installing kai to ${KAI_HOME} ..."
mkdir -p "${KAI_BIN}"

if command -v curl >/dev/null 2>&1; then
    curl -fsSL "${KAI_SCRIPT_URL}" > "${KAI_BIN}/kai"
elif command -v wget >/dev/null 2>&1; then
    wget -qO "${KAI_BIN}/kai" "${KAI_SCRIPT_URL}"
else
    echo "error: curl or wget is required" >&2
    exit 1
fi

chmod +x "${KAI_BIN}/kai"

# Add ~/.kai/bin to PATH in the user's shell rc
SHELL_NAME="$(basename "${SHELL:-bash}")"
if [ "${SHELL_NAME}" = "zsh" ]; then
    RC="${HOME}/.zshrc"
else
    RC="${HOME}/.bashrc"
fi

if ! grep -q '\.kai/bin' "${RC}" 2>/dev/null; then
    printf '\n# kai\nexport PATH="${HOME}/.kai/bin:${PATH}"\n' >> "${RC}"
    echo "✓ Added ~/.kai/bin to PATH in ${RC}"
fi

export PATH="${KAI_BIN}:${PATH}"

echo ""
echo "✓ kai installed to ${KAI_BIN}/kai"
echo ""
echo "Next steps:"
echo "  1. Start a new shell (or run: source ${RC})"
echo "  2. Get your config and kubeconfig files from your lab manager, then run:"
echo "       kai setup <config.yaml> <kubeconfig.yaml>"
echo "  3. Enable automatic config updates on login:"
echo "       kai install"
