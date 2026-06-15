#!/bin/sh
# kai installer — installs kai to ~/.kai, mirrors oh-my-zsh install pattern.
#
# Usage (one-liner):
#   sh -c "$(curl -fsSL https://raw.githubusercontent.com/BrachioLab/kai/main/install.sh)"
set -e

KAI_HOME="${HOME}/.kai"
KAI_BIN="${KAI_HOME}/bin"
KAI_SCRIPT_URL="https://raw.githubusercontent.com/BrachioLab/kai/main/kai"

# ── Prompt for required info before downloading anything ──────────────────────

echo ""
printf "Configs repository (e.g. brachiolab/locust-configs): "
read -r CONFIGS_REPO_SLUG
if [ -z "${CONFIGS_REPO_SLUG}" ]; then
    echo "error: configs repository is required" >&2
    exit 1
fi

printf "Lab namespace (e.g. brachiolab): "
read -r NAMESPACE
if [ -z "${NAMESPACE}" ]; then
    echo "error: lab namespace is required" >&2
    exit 1
fi

# Check that this user already has a config in the repo before proceeding
CONFIGS_REPO_URL="https://raw.githubusercontent.com/${CONFIGS_REPO_SLUG}/main/${NAMESPACE}"
CONFIG_URL="${CONFIGS_REPO_URL}/${USER}.yaml"

printf "Checking for '%s' in %s/%s ... " "${USER}" "${CONFIGS_REPO_SLUG}" "${NAMESPACE}"
if command -v curl >/dev/null 2>&1; then
    HTTP_STATUS=$(curl -o /dev/null -s -w "%{http_code}" "${CONFIG_URL}")
    [ "${HTTP_STATUS}" = "200" ] && FOUND=1 || FOUND=0
elif command -v wget >/dev/null 2>&1; then
    wget -q --spider "${CONFIG_URL}" 2>/dev/null && FOUND=1 || FOUND=0
else
    echo "error: curl or wget is required" >&2
    exit 1
fi

if [ "${FOUND}" = "0" ]; then
    echo "not found"
    echo ""
    echo "error: no config found for '${USER}' in namespace '${NAMESPACE}'" >&2
    echo "  Ask your lab manager to run:" >&2
    echo "    kai add-user --name ${USER}" >&2
    exit 1
fi
echo "found"

# ── Install ───────────────────────────────────────────────────────────────────

echo ""
echo "Installing kai to ${KAI_HOME} ..."
mkdir -p "${KAI_BIN}"

if command -v curl >/dev/null 2>&1; then
    curl -fsSL "${KAI_SCRIPT_URL}" > "${KAI_BIN}/kai"
else
    wget -qO "${KAI_BIN}/kai" "${KAI_SCRIPT_URL}"
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

# Store the namespace-specific configs base URL
printf '%s\n' "${CONFIGS_REPO_URL}" > "${KAI_HOME}/configs_repo"
echo "✓ Configs repo → ${KAI_HOME}/configs_repo"

# Add login hook now that kai is installed
"${KAI_BIN}/kai" install

echo ""
echo "✓ kai installed to ${KAI_BIN}/kai"
echo ""
echo "Next steps:"
echo "  1. Start a new shell (or run: source ${RC})"
echo "  2. Get your kubeconfig from your lab manager, then run:"
echo "       kai setup <kai-kubeconfig-${USER}.yaml>"
