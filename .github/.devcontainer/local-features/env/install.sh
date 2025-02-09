#!/bin/bash

GITHUB_REPO="${GITHUBENV_REPO:-"${GITHUB_REPOSITORY}"}"
ENV_FILE="${ENVFILE:-"/usr/local/etc/devcontainer.env"}"

# Create env directory
mkdir -p "$(dirname "${ENV_FILE}")"

# If we have a repo (should always be true in GitHub Actions)
if [ -n "$GITHUB_REPO" ]; then
    echo "Fetching environment variables from GitHub repository: ${GITHUB_REPO}"
    
    # gh cli is automatically authenticated in GitHub Actions
    gh secret list --repo "${GITHUB_REPO}" --json name,value | \
    jq -r '.[] | select(.value != null) | "\(.name)=\(.value)"' > "${ENV_FILE}"
fi

# Make env file readable only by owner
chmod 600 "${ENV_FILE}"

# Single source of truth for environment loading
echo "[ -f ${ENV_FILE} ] && { set -a; source ${ENV_FILE}; set +a; }" > /etc/profile.d/devcontainer-env.sh
