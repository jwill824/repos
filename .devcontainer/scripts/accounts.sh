#!/bin/bash

create_account_directories() {
    log_info "Creating account directories..."

    # Get all account names (excluding 'default')
    local accounts
    accounts=$(jq -r 'keys[] | select(. != "default")' "$DEVCONTAINER_DIR/repo_config.json")

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
        local account_dir
        local config
        local git_email
        local git_name

        account_dir="$WORKSPACE_ROOT/$account"
        config=$(jq -r ".$account" "$DEVCONTAINER_DIR/repo_config.json")
        git_email=$(echo "$config" | jq -r '.git.user.email')
        git_name=$(echo "$config" | jq -r '.git.user.name')

        log_info "Setting up repositories for $account..."

        if [[ -d "$account_dir" ]]; then
            setup_aws "$account_dir"

            # Setup git and dependencies for existing repos
            find "$account_dir" -type d -name ".git" -exec dirname {} \; | while read -r repo_dir; do
                setup_local_git_config "$repo_dir" "$git_email" "$git_name" "$account"
                install_project_dependencies "$repo_dir"
            done

            # Setup Python projects
            find "$account_dir" -type f \( -name "pyproject.toml" -o -name "requirements.txt" \) \
                -not -path "*/\.*/*" \
                -not -path "*/vendor/*" \
                -not -path "*/node_modules/*" \
                -exec dirname {} \; | while read -r python_dir; do
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

    cd - > /dev/null || exit
    log_success "Dependency installation completed for $project_dir"
}

get_python_version() {
    local project_dir="$1"
    local pyproject_file="$project_dir/pyproject.toml"
    local default_version
    default_version=$(pyenv latest --known 3)

    if [[ ! -f "$pyproject_file" ]]; then
        echo "$default_version"
        return
    fi

    local version=""
    if command -v toml >/dev/null 2>&1; then
        version=$(toml get "$pyproject_file" "tool.poetry.dependencies.python" 2>/dev/null | tr -d '"^=' || echo "")
    else
        version=$(grep -A5 '^\[tool\.poetry\.dependencies\]' "$pyproject_file" | grep '^python = ' | cut -d'"' -f2 | tr -d '^=' || echo "")
    fi

    if [[ -n "$version" ]]; then
        echo "$version"
    else
        echo "$default_version"
    fi
}

setup_python_venv() {
    local project_dir="$1"

    # Skip if already in a virtual environment or if the path contains dependency directories
    if [[ "$VIRTUAL_ENV" != "" ]] || \
       [[ "$project_dir" == *"/.venv/"* ]] || \
       [[ "$project_dir" == */vendor/* ]] || \
       [[ "$project_dir" == */node_modules/* ]]; then
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

    # Get Python version and create venv
    python_version=$(get_python_version "$project_dir")
    log_info "Setting up Python environment with version $python_version"

    # Make sure Python version is installed
    pyenv install -s "$python_version"

    # Write clean version to file
    echo "$python_version" > .python-version

    # Create virtualenv
    local venv_name
    venv_name=$(basename "$project_dir")
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

    cd - > /dev/null || exit
}

setup_aws() {
    local account_dir="$1"
    local account_name
    account_name="$(basename "$account_dir")"

    # Get AWS config for account
    local aws_config
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
        local profile_config
        profile_config=$(echo "$aws_config" | jq -r ".profiles.${profile}")
        {
            echo "[profile ${profile}]"
            echo "$profile_config" | jq -r 'to_entries | .[] | "\(.key) = \(.value)"'
            echo ""
        } >> "$aws_dir/config"
    done

    # Generate SAML2AWS config if enabled
    if [[ "$(echo "$aws_config" | jq -r '.saml.enabled')" == "true" ]]; then
        local saml_config
        saml_config=$(echo "$aws_config" | jq -r '.saml')
        echo "[default]" > "$saml2aws_config"
        jq -r 'to_entries[] | select(.key != "enabled") | "\(.key) = \(.value)"' <<< "$saml_config" >> "$saml2aws_config"
    fi

    # Create or update the .envrc file with AWS-specific configuration
    update_envrc "$account_dir" "aws" "
# AWS Configuration
export AWS_SHARED_CREDENTIALS_FILE=\"${aws_dir}/credentials\"
export AWS_CONFIG_FILE=\"${aws_dir}/config\"
export SAML2AWS_CONFIGFILE=\"${saml2aws_config}\"
export AWS_DEFAULT_REGION=us-east-2"

    # Allow the .envrc file
    direnv allow "$account_dir"

    log_success "AWS configuration completed for $account_dir"
}

setup_sqlserver_auth() {
    log_info "Setting up SQL Server authentication..."

    # Check for SQL Server configurations more safely
    local accounts_with_sql
    accounts_with_sql=$(jq -r 'to_entries[] | select(.value.sqlserver.enabled == true) | .key' "$DEVCONTAINER_DIR/repo_config.json")

    if [[ -z "$accounts_with_sql" ]]; then
        log_info "No SQL Server configurations found"
        return 0
    fi

    # Install common dependencies - fix the apt sources conflict
    sudo rm -f /etc/apt/sources.list.d/azure-functions-core-tools.list
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
    curl -fsSL https://packages.microsoft.com/config/ubuntu/"$(lsb_release -rs)"/prod.list | sudo tee /etc/apt/sources.list.d/mssql-release.list

    sudo apt-get update && sudo apt-get install -y \
        curl \
        unixodbc-dev \
        azure-cli

    while IFS= read -r account; do
        local config
        config=$(jq -r ".$account.sqlserver // empty" "$DEVCONTAINER_DIR/repo_config.json")

        # Setup Windows Auth if configured
        if [[ $(echo "$config" | jq -r '.windows_auth // empty') != null ]]; then
            setup_windows_auth "$account" "$config"
        fi

        # Setup Entra Auth if configured
        if [[ $(echo "$config" | jq -r '.entra_auth // empty') != null ]]; then
            setup_entra_auth "$account" "$config"
        fi
    done <<< "$accounts_with_sql"

    log_success "SQL Server authentication setup completed"
}

setup_windows_auth() {
    local account="$1"
    local config="$2"

    # Install Kerberos
    sudo apt-get install -y \
        krb5-user \
        krb5-config \
        libpam-krb5

    local domain
    domain=$(echo "$config" | jq -r '.windows_auth.domain')
    local account_dir="$WORKSPACE_ROOT/$account"

    configure_kerberos "$account_dir" "$domain" "$config"
    configure_hosts "$config"

    # Add Kerberos configuration to .envrc
    update_envrc "$account_dir" "kerberos" "
# Kerberos Configuration
if [[ -f \"$account_dir/.krb5.conf\" ]]; then
    sudo cp \"$account_dir/.krb5.conf\" /etc/krb5.conf
fi"

    log_success "Windows authentication configured for $account_dir"
}

setup_entra_auth() {
    local account="$1"
    local config="$2"
    local account_dir="$WORKSPACE_ROOT/$account"

    # Create Azure auth config directory
    mkdir -p "$account_dir/.azure"

    # Generate settings file for VS Code SQL extension
    local settings_file="$account_dir/.vscode/settings.json"
    mkdir -p "$(dirname "$settings_file")"

    jq -n \
        --arg account "$account" \
        --arg mssql_settings "$(echo "$config" | jq -r '.entra_auth.servers[] | {
            "server": .host,
            "authentication": {
                "type": "azure-active-directory-default",
                "options": {
                    "clientId": .client_id,
                    "tenantId": .tenant_id
                }
            }
        }')" \
        '{
            "mssql.connections": [$mssql_settings]
        }' > "$settings_file"

    # Add Azure configuration to .envrc
    update_envrc "$account_dir" "azure" "
# Azure Configuration
if [[ -f \"$account_dir/.azure/config\" ]]; then
    az login --service-principal
fi"

    log_success "Entra authentication configured for $account_dir"
}

configure_kerberos() {
    local account_dir="$1"
    local domain="$2"
    local config="$3"

    # Ensure domain is uppercase for Kerberos
    domain=${domain^^}
    local krb5_conf="$account_dir/.krb5.conf"

    # Validate domain
    if [[ -z "$domain" ]] || [[ "$domain" == "NULL" ]]; then
        log_error "Invalid domain configuration for Kerberos"
        return 1
    fi

    # Create Kerberos config
    cat > "$krb5_conf" << EOF
[libdefaults]
    default_realm = ${domain}
    dns_lookup_realm = false
    dns_lookup_kdc = false
    rdns = false
    ticket_lifetime = 24h
    forwardable = true
    proxiable = true

[realms]
    ${domain} = {
EOF

    # Add each server as a KDC
    local servers
    servers=$(echo "$config" | jq -r '.windows_auth.servers[]? | .host' 2>/dev/null)
    if [[ -z "$servers" ]]; then
        # Fallback to main servers array if windows_auth.servers is not defined
        servers=$(echo "$config" | jq -r '.servers[]? | .host' 2>/dev/null)
    fi

    if [[ -n "$servers" ]]; then
        while IFS= read -r server; do
            echo "        kdc = ${server}" >> "$krb5_conf"
            echo "        admin_server = ${server}" >> "$krb5_conf"
        done <<< "$servers"
    else
        log_error "No servers configured for Kerberos"
        return 1
    fi

    # Complete the configuration
    cat >> "$krb5_conf" << EOF
    }

[domain_realm]
    .${domain,,} = ${domain}
    ${domain,,} = ${domain}
EOF

    log_success "Kerberos configuration created for $domain"
}

configure_hosts() {
    local config="$1"
    local hosts_entries=""

    # Generate hosts entries
    while IFS= read -r entry; do
        local host
        local ip
        host=$(echo "$entry" | jq -r '.host')
        ip=$(echo "$entry" | jq -r '.ip')
        hosts_entries+="$ip $host\n"
    done < <(echo "$config" | jq -c '.servers[]')

    # Add to /etc/hosts if not already present
    if [[ -n "$hosts_entries" ]]; then
        echo -e "$hosts_entries" | while read -r entry; do
            if ! grep -q "$entry" /etc/hosts; then
                echo "$entry" | sudo tee -a /etc/hosts > /dev/null
            fi
        done
    fi
}

# New helper function to manage .envrc contents
update_envrc() {
    local account_dir="$1"
    local section="$2"
    local content="$3"
    local envrc_file="$account_dir/.envrc"

    # Create .envrc if it doesn't exist
    if [[ ! -f "$envrc_file" ]]; then
        echo "# Environment configuration for $(basename "$account_dir")" > "$envrc_file"
        echo 'export ACCOUNT_DIR="$PWD"' >> "$envrc_file"
    fi

    # Remove existing section if present
    local start_marker="# BEGIN ${section} configuration"
    local end_marker="# END ${section} configuration"
    sed -i "/^${start_marker}$/,/^${end_marker}$/d" "$envrc_file"

    # Add new section
    cat >> "$envrc_file" << EOF

${start_marker}
${content}
${end_marker}
EOF

    # Ensure direnv hook is in zshrc
    if ! grep -q "eval \"\$(direnv hook zsh)\"" ~/.zshrc; then
        echo '
# Initialize direnv
eval "$(direnv hook zsh)"' >> ~/.zshrc
    fi

    # Allow the updated .envrc
    direnv allow "$account_dir"
}
