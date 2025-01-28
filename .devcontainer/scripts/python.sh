#!/bin/bash

setup_python_venv() {
    local project_dir="$1"
    
    # Skip if inside virtual environment
    if [[ "$project_dir" == *"/.venv/"* ]]; then
        return 0
    fi
    
    # Find nearest pyproject.toml
    local current_dir="$project_dir"
    while [[ "$current_dir" != "/" ]]; do
        if [[ -f "$current_dir/pyproject.toml" ]]; then
            project_dir="$current_dir"
            break
        fi
        current_dir="$(dirname "$current_dir")"
    done
    
    if [[ "$project_dir" == "/" ]]; then
        log_error "Could not find pyproject.toml in parent directories"
        return 1
    fi
    
    cd "$project_dir" || return 1
    log_info "Setting up Python environment in $project_dir"
    
    # Install build dependencies
    if ! install_system_dependencies \
        build-essential libssl-dev zlib1g-dev libbz2-dev \
        libreadline-dev libsqlite3-dev curl python3-pip \
        postgresql postgresql-contrib libpq-dev python3-dev; then
        log_warning "Failed to install some build dependencies"
    fi
    
    install_pyenv
    install_poetry
    
    # Create activation script
    local activate_script="$project_dir/activate_venv.sh"
    cat > "$activate_script" << EOF
#!/bin/bash
source \$(poetry env info --path)/bin/activate
EOF
    chmod +x "$activate_script"
    
    cd - > /dev/null
}

install_pyenv() {
    if [[ ! -d "$WORKSPACE_ROOT/.pyenv" ]] || ! command -v pyenv &> /dev/null; then
        log_info "Installing pyenv..."
        [[ -d "$WORKSPACE_ROOT/.pyenv" ]] && rm -rf "$WORKSPACE_ROOT/.pyenv"
        
        curl -L https://pyenv.run | bash
        
        export PYENV_ROOT="$WORKSPACE_ROOT/.pyenv"
        export PATH="$PYENV_ROOT/bin:$PATH"
        eval "$(pyenv init -)"
        
        if ! grep -q "pyenv init" ~/.bashrc; then
            echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.bashrc
            echo 'export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.bashrc
            echo 'eval "$(pyenv init -)"' >> ~/.bashrc
        fi
        
        local python_versions=("3.9.18" "3.12.1")
        for version in "${python_versions[@]}"; do
            pyenv install "$version" || log_warning "Failed to install Python $version"
        done
    fi
}

install_poetry() {
    if ! command -v poetry &> /dev/null; then
        log_info "Installing Poetry..."
        curl -sSL https://install.python-poetry.org | POETRY_HOME="$HOME/.local" python3 -
        export PATH="$HOME/.local/bin:$PATH"
        poetry config virtualenvs.in-project true
    fi
}
