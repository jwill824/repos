#!/bin/bash

set -e

# Install git if not present
if ! command -v git &> /dev/null; then
    apt-get update
    apt-get install -y git
fi

# Install bats-core
git clone https://github.com/bats-core/bats-core.git /tmp/bats-core
cd /tmp/bats-core
./install.sh /usr/local
cd - > /dev/null

# Create helpers directory
HELPER_DIR="/usr/local/lib/bats/helpers"
mkdir -p "${HELPER_DIR}"

# Install bats-support
git clone https://github.com/bats-core/bats-support.git "${HELPER_DIR}/bats-support"

# Install bats-assert
git clone https://github.com/bats-core/bats-assert.git "${HELPER_DIR}/bats-assert"

# Clean up
rm -rf /tmp/bats-core
apt-get clean
rm -rf /var/lib/apt/lists/*
