#!/bin/bash

validate_requirements() {
    log_info "Validating required files and commands..."
    
    # Configuration files
    readonly CONFIG_FILES=(
        "$DEVCONTAINER_DIR/repo_config.json"
        "$HOOKS_DIR/commit-msg"
        "$HOOKS_DIR/pre-push"
        "$HOOKS_DIR/prepare-commit-msg"
    )
    
    # Check required files
    for file in "${CONFIG_FILES[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_error "Required file not found: $file"
            exit 1
        fi
    done
    
    # Check required commands
    local required_commands=(
        "git" "jq" "npm" "python" "node" "npx"
    )
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command not found: $cmd"
            exit 1
        fi
    done
    
    log_success "All initial requirements validated"
}
