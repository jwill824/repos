#!/bin/bash

CREDENTIAL_STORE=${CREDENTIALSTORE:-"gpg"}
GCM_INSTALL_DIR="/usr/local/gcm"

# Install common dependencies
apt-get update
apt-get install -y curl

install_gpg_dependencies() {
    apt-get install -y gpg pass gnupg2

    # Initialize pass if not already configured
    if ! command -v pass &> /dev/null; then
        GNUPGHOME="$(mktemp -d)"
        export GNUPGHOME
        cat >keydetails <<EOF
%echo Generating GPG key
Key-Type: RSA
Key-Length: 4096
Name-Real: Git Credential Manager
Name-Email: gcm@local
Expire-Date: 0
%no-protection
%commit
%echo Done
EOF
        gpg --batch --generate-key keydetails
        rm keydetails

        gpg_id=$(gpg --list-secret-keys --keyid-format LONG | grep sec | cut -d'/' -f2 | cut -d' ' -f1)
        pass init "$gpg_id"
    fi
}

install_secretservice_dependencies() {
    # Stub for future implementation
    echo "Secret Service store not yet implemented"
    exit 1
}

install_cache_dependencies() {
    # No additional dependencies needed for cache store
    return 0
}

install_plaintext_dependencies() {
    # No additional dependencies needed for plaintext store
    return 0
}

# Install store-specific dependencies
case $CREDENTIAL_STORE in
    "gpg")
        install_gpg_dependencies
        ;;
    "secretservice")
        install_secretservice_dependencies
        ;;
    "cache")
        install_cache_dependencies
        ;;
    "plaintext")
        install_plaintext_dependencies
        ;;
    *)
        echo "Invalid credential store selected"
        exit 1
        ;;
esac

# Install Git Credential Manager
mkdir -p "$GCM_INSTALL_DIR"
dotnet tool install --tool-path "$GCM_INSTALL_DIR" git-credential-manager

# Add GCM to PATH
echo "export PATH=\"$GCM_INSTALL_DIR:\$PATH\"" >> /etc/profile.d/gcm-path.sh
source /etc/profile.d/gcm-path.sh

# Configure GCM
git config --global credential.credentialStore "$CREDENTIAL_STORE"
export GCM_CREDENTIAL_STORE="$CREDENTIAL_STORE"

git-credential-manager configure
