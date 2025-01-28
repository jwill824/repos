#!/bin/bash

create_account_directories() {
    log_info "Creating account directories..."
    
    # Get all account names (excluding 'default')
    local accounts=($(jq -r 'keys[] | select(. != "default")' "$DEVCONTAINER_DIR/repo_config.json"))
    
    # Create directories for each account
    for account in "${accounts[@]}"; do
        local account_dir="$WORKSPACE_ROOT/$account"
        if [[ ! -d "$account_dir" ]]; then
            mkdir -p "$account_dir"
            log_success "Created directory for $account"
        fi
    done
}

setup_account_repositories() {
    log_info "Setting up repositories for all accounts..."
    
    # Process each account from config (excluding default)
    jq -r 'keys[] | select(. != "default")' "$DEVCONTAINER_DIR/repo_config.json" | while read -r account; do
        local account_dir="$WORKSPACE_ROOT/$account"
        local config=$(jq -r ".$account" "$DEVCONTAINER_DIR/repo_config.json")
        local git_email=$(echo "$config" | jq -r '.email')
        local git_name=$(echo "$config" | jq -r '.name')
        
        log_info "Setting up repositories for $account..."
        
        if [[ -d "$account_dir" ]]; then
            setup_aws "$account_dir"
            
            # Setup git and dependencies for existing repos
            find "$account_dir" -type d -name ".git" -exec dirname {} \; | while read -r repo_dir; do
                setup_git_config "$repo_dir" "$git_email" "$git_name"
                install_project_dependencies "$repo_dir"
            done
            
            # Setup Python projects
            find "$account_dir" -type f \( -name "pyproject.toml" -o -name "requirements.txt" \) -exec dirname {} \; | while read -r python_dir; do
                log_info "Found Python project in: $python_dir"
                setup_python_venv "$python_dir"
            done
        fi
    done
}

install_project_dependencies() {
    local project_dir="$1"
    cd "$project_dir" || return 1
    
    log_info "Checking for dependencies in $project_dir"
    
    if [[ -f "package.json" ]]; then
        install_node_dependencies
    fi
    
    if [[ -f "pyproject.toml" ]] || [[ -f "requirements.txt" ]]; then
        setup_python_venv "$project_dir"
    fi
    
    if [[ -f "Gemfile" ]]; then
        install_ruby_dependencies
    fi
    
    cd - > /dev/null
    log_success "Dependency installation completed for $project_dir"
}
