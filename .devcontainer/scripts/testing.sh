#!/bin/bash

setup_dotfiles_test_environment() {
    log_info "Setting up test environment..."
    
    install_bats
    setup_test_directories
    install_pester
    
    log_success "Test environment setup complete"
    log_info "To run tests:"
    log_info "  Bats tests: cd $DOTFILES_DIR && bats tests/"
    log_info "  Pester tests: cd $DOTFILES_DIR && pwsh -Command 'Invoke-Pester ./tests/setup.Tests.ps1 -Output Detailed'"
}

install_bats() {
    log_info "Installing Bats Core..."
    if ! command -v bats &> /dev/null; then
        git clone https://github.com/bats-core/bats-core.git /tmp/bats-core
        cd /tmp/bats-core
        sudo ./install.sh /usr/local
        cd - > /dev/null
        rm -rf /tmp/bats-core
    fi
}

setup_test_directories() {
    # Define paths for dotfiles tests
    DOTFILES_DIR="$WORKSPACE_ROOT/personal/dotfiles"
    DOTFILES_TEST_DIR="$DOTFILES_DIR/tests/test_helper"
    
    # Create test helper directory
    mkdir -p "$DOTFILES_TEST_DIR"
    
    # Clone test helper repositories
    local test_helpers=(
        "https://github.com/bats-core/bats-support.git"
        "https://github.com/bats-core/bats-assert.git"
    )
    
    for repo in "${test_helpers[@]}"; do
        local repo_name=$(basename "$repo" .git)
        local target_dir="$DOTFILES_TEST_DIR/$repo_name"
        
        if [[ ! -d "$target_dir" ]]; then
            git clone "$repo" "$target_dir"
        fi
    done
}

install_pester() {
    # Install Pester for PowerShell testing
    if ! pwsh -Command "Get-Module -ListAvailable Pester"; then
        pwsh -Command "Install-Module -Name Pester -Force -SkipPublisherCheck"
    fi
}
