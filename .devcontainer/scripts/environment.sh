#!/bin/bash

export ENV_EXAMPLE="$DEVCONTAINER_DIR/.env.example"
export ENV_FILE="$DEVCONTAINER_DIR/.env"

setup_environment() {
    log_info "Setting up environment..."
    
    # Create .env.example if needed
    if [[ ! -f "$ENV_EXAMPLE" ]]; then
        cat > "$ENV_EXAMPLE" << EOF
# Anthropic API Key for AI-powered commit messages
ANTHROPIC_API_KEY=your_api_key_here
EOF
        log_success "Created .env.example template"
    fi
    
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
