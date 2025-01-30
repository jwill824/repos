#!/bin/bash

export ENV_EXAMPLE="$DEVCONTAINER_DIR/.env.example"
export ENV_FILE="$DEVCONTAINER_DIR/.env"

setup_environment() {
    log_info "Setting up environment..."
    
    # Create .env if needed
    if [[ ! -f "$ENV_FILE" ]]; then
        cp "$ENV_EXAMPLE" "$ENV_FILE"
        log_warning "Created .env file. Please update it with your Anthropic API key"
    fi
    
    # Source environment
    if [[ -f "$ENV_FILE" ]]; then
        set -a
        source "$ENV_FILE"
        set +a
        
        if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
            git config --global ai.apikey "$ANTHROPIC_API_KEY"
            log_success "Configured git with API key"
            export ANTHROPIC_API_KEY
        else
            log_warning "ANTHROPIC_API_KEY not found in environment"
        fi
    fi
}

setup_bashrc() {
    local bashrc="$HOME/.bashrc"
    if ! grep -q "source $ENV_FILE" "$bashrc"; then
        cat >> "$bashrc" << EOF

# Source devcontainer environment variables
if [[ -f $ENV_FILE ]]; then
    set -a
    source $ENV_FILE
    set +a
fi
EOF
        log_success "Added environment sourcing to .bashrc"
    fi
}