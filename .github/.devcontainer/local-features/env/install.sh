#!/bin/bash

set -e

GITHUB_REPO="${GITHUBREPO:-"${GITHUB_REPOSITORY}"}"
ENV_FILE="${ENVFILE:-"/usr/local/etc/devcontainer.env"}"
ENV_DIR="$(dirname "${ENV_FILE}")"

# Create env directory with proper permissions
mkdir -p "${ENV_DIR}"
chmod 755 "${ENV_DIR}"

# Create empty env file first
touch "${ENV_FILE}"
chmod 600 "${ENV_FILE}"

# If we have a repo and gh cli is available, try to fetch secrets
if [ -n "${GITHUB_REPO}" ] && command -v gh >/dev/null 2>&1; then
    echo "Attempting to fetch environment variables from GitHub repository: ${GITHUB_REPO}"
    
    if gh secret list --repo "${GITHUB_REPO}" --json name,value >/dev/null 2>&1; then
        gh secret list --repo "${GITHUB_REPO}" --json name,value | \
        jq -r '.[] | select(.value != null) | "\(.name)=\(.value)"' > "${ENV_FILE}"
    else
        echo "Warning: Unable to fetch secrets from GitHub. Will use empty env file."
    fi
else
    echo "Note: GitHub CLI not available or repo not specified. Using empty env file."
fi

# Create profile script to load env vars
echo "[ -f ${ENV_FILE} ] && { set -a; source ${ENV_FILE}; set +a; }" > /etc/profile.d/devcontainer-env.sh
chmod 644 /etc/profile.d/devcontainer-env.sh
