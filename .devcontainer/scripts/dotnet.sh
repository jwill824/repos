#!/bin/bash

install_dotnet() {
    log_info "Installing dotnet 9 preview..."

    # Download and execute Microsoft's installation script
    wget https://dot.net/v1/dotnet-install.sh -O dotnet-install.sh
    chmod +x dotnet-install.sh
    sudo ./dotnet-install.sh --version latest --install-dir /usr/share/dotnet
    rm dotnet-install.sh

    # Add dotnet to PATH
    echo 'export PATH="$PATH:/usr/share/dotnet"' >> ~/.bashrc
    source ~/.bashrc

    log_info "dotnet 9 preview installed"
}