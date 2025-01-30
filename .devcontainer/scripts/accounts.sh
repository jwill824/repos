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

    # Setup global git config
    setup_global_git_config "$(jq -r '.default.git.user.email' "$DEVCONTAINER_DIR/repo_config.json")" "$(jq -r '.default.git.user.name' "$DEVCONTAINER_DIR/repo_config.json")"
    
    # Process each account from config (excluding default)
    jq -r 'keys[] | select(. != "default")' "$DEVCONTAINER_DIR/repo_config.json" | while read -r account; do
        local account_dir="$WORKSPACE_ROOT/$account"
        local config=$(jq -r ".$account" "$DEVCONTAINER_DIR/repo_config.json")
        local git_email=$(echo "$config" | jq -r '.git.user.email')
        local git_name=$(echo "$config" | jq -r '.git.user.name')
        
        log_info "Setting up repositories for $account..."
        
        if [[ -d "$account_dir" ]]; then
            setup_aws "$account_dir"
            
            # Setup git and dependencies for existing repos
            find "$account_dir" -type d -name ".git" -exec dirname {} \; | while read -r repo_dir; do
                setup_local_git_config "$repo_dir" "$git_email" "$git_name"
                install_project_dependencies "$repo_dir"
            done
            
            # Setup Python projects
            find "$account_dir" -type f \( -name "pyproject.toml" -o -name "requirements.txt" \) -exec dirname {} \; | while read -r python_dir; do
                log_info "Found Python project in: $python_dir"
                setup_python_venv "$python_dir"
            done

            # Setup git for directories containing .sln files
            find "$account_dir" -type f -name "*.sln" -exec dirname {} \; | while read -r sln_dir; do
                setup_local_git_config "$sln_dir" "$git_email" "$git_name"
                configure_git_line_endings "$sln_dir" "true"
            done
        fi
    done
}

install_project_dependencies() {
    local project_dir="$1"
    cd "$project_dir" || return 1
    
    log_info "Checking for dependencies in $project_dir"
    
    if [[ -f "package.json" ]]; then
        npm install
    fi
    
    if [[ -f "pyproject.toml" ]] || [[ -f "requirements.txt" ]]; then
        setup_python_venv "$project_dir"
    fi
    
    if [[ -f "Gemfile" ]]; then
        bundle install
    fi
    
    cd - > /dev/null
    log_success "Dependency installation completed for $project_dir"
}
