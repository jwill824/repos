#!/bin/bash

set -e

# Clean up parameters
PACKAGES=${PACKAGES:-""}

if [ ! -z "${PACKAGES}" ]; then
    echo "Installing npm packages: ${PACKAGES}"
    
    # Convert comma-separated list to array
    IFS=',' read -ra PKG_ARRAY <<< "${PACKAGES}"
    
    # Install each package globally
    for package in "${PKG_ARRAY[@]}"; do
        # Trim whitespace
        package=$(echo "${package}" | xargs)
        if [ ! -z "${package}" ]; then
            echo "Installing ${package}..."
            npm install -g "${package}"
        fi
    done
fi

echo "Done!"
