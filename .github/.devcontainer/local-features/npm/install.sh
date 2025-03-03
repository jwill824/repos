#!/bin/bash

set -e

PACKAGES=${PACKAGES:-""}

if [ -n "${PACKAGES}" ]; then
    echo "Installing npm packages: ${PACKAGES}"

    # Convert comma-separated list to array
    IFS=',' read -ra PKG_ARRAY <<< "${PACKAGES}"

    # Install each package globally
    for package in "${PKG_ARRAY[@]}"; do
        # Trim whitespace
        package=$(echo "${package}" | xargs)
        if [ -n "${package}" ]; then
            echo "Installing ${package}..."
            npm install -g "${package}"
        fi
    done
fi

echo "Done!"
