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

# Prompt for GitHub token — required for lab managers (kai add-user pushes configs to GitHub).
# Researchers can leave this blank.
echo ""
printf "GitHub personal access token (lab managers only — press Enter to skip): "
# Read with no echo if stty is available
if command -v stty >/dev/null 2>&1; then
    stty -echo 2>/dev/null
    read -r KAI_GITHUB_TOKEN
    stty echo 2>/dev/null
    echo ""
else
    read -r KAI_GITHUB_TOKEN
fi

if [ -n "${KAI_GITHUB_TOKEN}" ]; then
    mkdir -p "${KAI_HOME}"
    CRED_FILE="${KAI_HOME}/credentials"
    # Preserve any existing credentials and upsert github_token
    if [ -f "${CRED_FILE}" ]; then
        # Remove existing github_token line if present, then append
        grep -v '^github_token:' "${CRED_FILE}" > "${CRED_FILE}.tmp" 2>/dev/null || true
        mv "${CRED_FILE}.tmp" "${CRED_FILE}"
    fi
    printf 'github_token: %s\n' "${KAI_GITHUB_TOKEN}" >> "${CRED_FILE}"
    chmod 600 "${CRED_FILE}"
    echo "✓ GitHub token saved to ${CRED_FILE}"
else
    echo "  (skipped — run 'kai setup <config> <kubeconfig> --github-token <TOKEN>' later if needed)"
fi

echo ""
echo "✓ kai installed to ${KAI_BIN}/kai"
echo ""
echo "Next steps:"
echo "  1. Start a new shell (or run: source ${RC})"
echo "  2. Get your config and kubeconfig files from your lab manager, then run:"
echo "       kai setup <config.yaml> <kubeconfig.yaml>"
echo "  3. Enable automatic config updates on login:"
echo "       kai install"
