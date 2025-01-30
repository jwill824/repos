#!/bin/bash

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

install_aws_cli() {
    if ! command -v aws &> /dev/null; then
        log_info "Installing AWS CLI..."
        local temp_dir=$(mktemp -d)
        cd "$temp_dir"
        
        local arch=$(uname -m)
        local aws_cli_url="https://awscli.amazonaws.com/awscli-exe-linux-${arch}.zip"
        
        if curl -fsSL "$aws_cli_url" -o "awscliv2.zip"; then
            unzip -q awscliv2.zip
            sudo ./aws/install
            cd - > /dev/null
            rm -rf "$temp_dir"
        else
            log_error "Failed to download AWS CLI installer"
            return 1
        fi
    fi
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
