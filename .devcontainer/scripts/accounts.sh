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
                setup_local_git_config "$repo_dir" "$git_email" "$git_name" "$account"
                install_project_dependencies "$repo_dir"
            done

            # Setup Python projects
            find "$account_dir" -type f \( -name "pyproject.toml" -o -name "requirements.txt" \) -exec dirname {} \; | while read -r python_dir; do
                log_info "Found Python project in: $python_dir"
                setup_python_venv "$python_dir"
            done

            # Setup git for directories containing .sln files
            find "$account_dir" -type f -name "*.sln" -exec dirname {} \; | while read -r sln_dir; do
                setup_local_git_config "$sln_dir" "$git_email" "$git_name" "$account"
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

get_python_version() {
    local project_dir="$1"
    local pyproject_file="$project_dir/pyproject.toml"
    local default_version=$(pyenv latest --known 3)

    if [[ ! -f "$pyproject_file" ]]; then
        echo "$default_version"
        return
    fi

    # Try to parse python version from pyproject.toml
    local python_version
    if python_version=$(grep -A5 '^\[tool\.poetry\]' "$pyproject_file" | grep 'python' | sed -E 's/.*"^\^?([0-9]+\.[0-9]+(\.[0-9]+)?)"$/\1/'); then
        # Check if we have a compatible installed version
        local installed_version=$(pyenv versions --bare | grep "^$python_version" | sort -V | tail -n1)
        if [[ -n "$installed_version" ]]; then
            echo "$installed_version"
        else
            echo "$python_version"
        fi
    else
        echo "$default_version"
    fi
}

setup_python_venv() {
    local project_dir="$1"

    # Skip if inside virtual environment
    if [[ "$project_dir" == *"/.venv/"* ]]; then
        return 0
    fi

    # Find nearest pyproject.toml or requirements.txt
    local current_dir="$project_dir"
    while [[ "$current_dir" != "/" ]]; do
        if [[ -f "$current_dir/pyproject.toml" ]] || [[ -f "$current_dir/requirements.txt" ]]; then
            project_dir="$current_dir"
            break
        fi
        current_dir="$(dirname "$current_dir")"
    done

    if [[ "$project_dir" == "/" ]]; then
        log_error "Could not find Python project files in parent directories"
        return 1
    fi

    cd "$project_dir" || return 1
    log_info "Setting up Python environment in $project_dir"

    # Fix pyenv permissions
    sudo chown -R "$(whoami)" /usr/local/pyenv
    sudo chmod -R u+w /usr/local/pyenv

    # Get Python version from pyproject.toml or use latest
    local python_version
    if [[ -f "pyproject.toml" ]]; then
        python_version=$(get_python_version "$project_dir")
    else
        python_version=$(pyenv latest --known 3)
    fi
    log_info "Using Python version: $python_version"

    # Update .python-version file
    echo "$python_version" > .python-version

    # Install Python version if needed
    if ! pyenv versions --bare | grep -q "^$python_version$"; then
        log_info "Installing Python $python_version..."
        pyenv install -s "$python_version"
    fi

    # Create virtualenv
    local venv_name=$(basename "$project_dir")
    eval "$(pyenv init -)"
    eval "$(pyenv virtualenv-init -)"

    # Delete existing virtualenv if it exists
    pyenv virtualenv-delete -f "$venv_name" 2>/dev/null || true

    # Create new virtualenv and set it as local
    pyenv virtualenv "$python_version" "$venv_name"
    pyenv local "$venv_name"

    # Activate virtualenv
    pyenv activate "$venv_name"

    # Upgrade pip
    pip install --upgrade pip

    # Install dependencies
    if [[ -f "requirements.txt" ]]; then
        pip install -r requirements.txt
    elif [[ -f "pyproject.toml" ]]; then
        if grep -q "poetry" pyproject.toml; then
            pip install poetry
            poetry install
        else
            pip install -e .
        fi
    fi

    # Create activation script
    local activate_script="$project_dir/activate_venv.sh"
    cat > "$activate_script" << EOF
#!/bin/bash
eval "\$(pyenv init -)"
eval "\$(pyenv virtualenv-init -)"
pyenv activate $venv_name
EOF
    chmod +x "$activate_script"

    # Deactivate virtualenv
    pyenv deactivate

    cd - > /dev/null
}

setup_aws() {
    local account_dir="$1"
    local account_name="$(basename "$account_dir")"

    # Get AWS config for account
    local aws_config=$(jq -r ".$account_name.aws // empty" "$DEVCONTAINER_DIR/repo_config.json")
    if [[ -z "$aws_config" ]] || [[ "$(echo "$aws_config" | jq -r '.enabled')" != "true" ]]; then
        return 0
    fi

    log_info "Setting up AWS configuration for $account_name workspace..."

    # Use predefined paths from devcontainer.json
    local aws_dir="${AWS_CONFIG_DIR:-"$account_dir/.aws"}"
    local saml2aws_config="${SAML2AWS_CONFIG:-"$account_dir/.saml2aws"}"

    rm -rf "$aws_dir"
    rm -f "$saml2aws_config"
    mkdir -p "$aws_dir"

    # Install required tools
    if [[ "$(echo "$aws_config" | jq -r '.saml.enabled')" == "true" ]]; then
        install_saml2aws
    fi

    # Configure AWS files
    configure_aws_files "$aws_dir" "$saml2aws_config" "$account_dir" "$aws_config"
}

install_saml2aws() {
    if ! command -v saml2aws &> /dev/null; then
        log_info "Installing saml2aws..."
        CURRENT_VERSION=$(curl -Ls https://api.github.com/repos/Versent/saml2aws/releases/latest | grep 'tag_name' | cut -d'v' -f2 | cut -d'"' -f1)
        wget -q "https://github.com/Versent/saml2aws/releases/download/v${CURRENT_VERSION}/saml2aws_${CURRENT_VERSION}_linux_amd64.tar.gz"
        tar -xzf "saml2aws_${CURRENT_VERSION}_linux_amd64.tar.gz" -C /tmp
        sudo mv /tmp/saml2aws /usr/local/bin/
        sudo chmod u+x /usr/local/bin/saml2aws
        rm -f "saml2aws_${CURRENT_VERSION}_linux_amd64.tar.gz"
        rm -rf /tmp/*.md
    fi
}

configure_aws_files() {
    local aws_dir="$1"
    local saml2aws_config="$2"
    local account_dir="$3"
    local aws_config="$4"

    # Generate AWS CLI config - fixed format
    for profile in $(echo "$aws_config" | jq -r '.profiles | keys[]'); do
        local profile_config=$(echo "$aws_config" | jq -r ".profiles.${profile}")
        {
            echo "[profile ${profile}]"
            echo "$profile_config" | jq -r 'to_entries | .[] | "\(.key) = \(.value)"'
            echo ""
        } >> "$aws_dir/config"
    done

    # Generate SAML2AWS config if enabled
    if [[ "$(echo "$aws_config" | jq -r '.saml.enabled')" == "true" ]]; then
        local saml_config=$(echo "$aws_config" | jq -r '.saml')
        echo "[default]" > "$saml2aws_config"
        jq -r 'to_entries[] | select(.key != "enabled") | "\(.key) = \(.value)"' <<< "$saml_config" >> "$saml2aws_config"
    fi

    # Workspace environment
    local workspace_env="$account_dir/.workspace_env"
    cat > "$workspace_env" << EOF
# AWS Configuration for LeadingEdje workspace
export AWS_SHARED_CREDENTIALS_FILE="${aws_dir}/credentials"
export AWS_CONFIG_FILE="${aws_dir}/config"
export SAML2AWS_CONFIGFILE="${saml2aws_config}"
export AWS_DEFAULT_REGION=us-east-2
EOF

    # Add to bashrc if not present
    if ! grep -q "source.*$workspace_env" ~/.bashrc; then
        echo "
# Source LeadingEdje workspace environment
if [[ \"\$PWD\" == \"$account_dir\"* ]] && [[ -f \"$workspace_env\" ]]; then
    source \"$workspace_env\"
fi" >> ~/.bashrc
    fi

    log_success "AWS configuration completed for $account_dir"
}
