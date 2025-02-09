#!/bin/bash

set -e

# Ensure PowerShell is available
if ! command -v pwsh &> /dev/null; then
    echo "PowerShell is required but not installed. Please install PowerShell feature first."
    exit 1
fi

# Install Pester
if [ "${VERSION}" = "latest" ]; then
    pwsh -Command "Install-Module -Name Pester -Force -SkipPublisherCheck"
else
    pwsh -Command "Install-Module -Name Pester -RequiredVersion ${VERSION} -Force -SkipPublisherCheck"
fi

# Verify installation
pwsh -Command "Get-Module -Name Pester -ListAvailable"
