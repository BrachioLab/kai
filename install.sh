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

# Prompt for the configs repository — required to continue installation.
# Once set, kai setup only needs a kubeconfig; the config is fetched automatically.
echo ""
printf "Configs repository (e.g. brachiolab/brachiolab-configs): "
read -r CONFIGS_REPO_SLUG

if [ -z "${CONFIGS_REPO_SLUG}" ]; then
    echo "error: configs repository is required" >&2
    exit 1
fi

CONFIGS_REPO_URL="https://raw.githubusercontent.com/${CONFIGS_REPO_SLUG}/main"
printf '%s\n' "${CONFIGS_REPO_URL}" > "${KAI_HOME}/configs_repo"
echo "✓ Configs repo → ${KAI_HOME}/configs_repo"

echo ""
echo "✓ kai installed to ${KAI_BIN}/kai"
echo ""
echo "Next steps:"
echo "  1. Start a new shell (or run: source ${RC})"
echo "  2. Get your kubeconfig from your lab manager, then run:"
echo "       kai setup <kai-kubeconfig-<user>.yaml>"
echo "  3. Enable automatic config updates on login:"
echo "       kai install"
