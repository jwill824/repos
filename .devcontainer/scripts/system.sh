#!/bin/bash

install_system_dependencies() {
    local packages=("$@")
    local temp_file=$(mktemp)
    
    log_info "Installing packages: ${packages[*]}"
    
    {
        if ! DEBIAN_FRONTEND=noninteractive sudo apt-get update -qq; then
            log_error "Failed to update package lists"
            return 1
        fi
        
        if ! DEBIAN_FRONTEND=noninteractive sudo apt-get install -y "${packages[@]}"; then
            log_error "Failed to install packages: ${packages[*]}"
            return 1
        fi
    } > "$temp_file" 2>&1
    
    local result=$?
    
    if [[ $result -ne 0 ]]; then
        log_error "Package installation failed. Last output:"
        tail -n 10 "$temp_file"
        rm -f "$temp_file"
        return $result
    fi
    
    rm -f "$temp_file"
    return 0
}
