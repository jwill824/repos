#!/bin/bash

setup_aws() {
    local account_dir="$1"
    local account_name="$(basename "$account_dir")"
    
    # Only configure AWS for LeadingEdje workspace
    if [[ "$account_name" != "leadingedje" ]]; then
        return 0
    fi
    
    log_info "Setting up AWS configuration for LeadingEdje workspace..."

    # Create workspace-specific AWS directories
    local aws_dir="$account_dir/.aws"
    local saml2aws_config="$account_dir/.saml2aws"
    
    rm -rf "$aws_dir"
    rm -f "$saml2aws_config"
    mkdir -p "$aws_dir"

    install_aws_cli
    install_saml2aws

    # Configure AWS configs
    configure_aws_files "$aws_dir" "$saml2aws_config" "$account_dir"
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

    # AWS CLI config
    cat > "$aws_dir/config" << EOF
[profile development]
region = us-east-2
role_arn       = arn:aws:iam::702328517568:role/DevOpsRole
output = json
source_profile = le-sso
EOF

    # SAML2AWS config
    cat > "$saml2aws_config" << EOF
[default]
app_id                  = 305541016011
url                     = https://accounts.google.com/o/saml2/initsso?idpid=C035husfp&spid=305541016011
username                = jeff.williams@leadingedje.com
provider                = GoogleApps
mfa                     = Auto
skip_verify             = false
timeout                 = 0
aws_urn                 = urn:amazon:webservices
aws_session_duration    = 43200
aws_profile            = le-sso
region                  = us-east-2
EOF

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
}
