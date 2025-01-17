#!/bin/bash

# Constants
readonly WORKSPACE_ROOT="/workspaces/repos"
readonly DEVCONTAINER_DIR="$WORKSPACE_ROOT/.devcontainer"
readonly VENV_PATH="$WORKSPACE_ROOT/.venv"

# Configuration files
readonly CONFIG_FILES=(
    "$DEVCONTAINER_DIR/repo_config.json"
    "$DEVCONTAINER_DIR/commit-msg"
    "$DEVCONTAINER_DIR/pre-push"
    "$DEVCONTAINER_DIR/prepare-commit-msg"
)

# Environment files
readonly ENV_FILE="$DEVCONTAINER_DIR/.env"
readonly ENV_EXAMPLE="$DEVCONTAINER_DIR/.env.example"

# Error handling
set -euo pipefail

# Logging functions
log_info() { echo "ℹ️ $*"; }
log_success() { echo "✓ $*"; }
log_warning() { echo "⚠️ $*"; }
log_error() { echo "❌ $*" >&2; }

validate_requirements() {
    log_info "Validating required files and commands..."
    
    # Check required files
    for file in "${CONFIG_FILES[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_error "Required file not found: $file"
            exit 1
        fi
    done
    
    # Check required commands (only the ones needed before installation steps)
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

install_system_dependencies() {
    local packages=("$@")
    local temp_file=$(mktemp)
    
    log_info "Installing packages: ${packages[*]}"
    
    # Run apt-get commands with proper error handling
    {
        if ! DEBIAN_FRONTEND=noninteractive sudo apt-get update -qq; then
            log_error "Failed to update package lists"
            return 1
        fi
        
        if ! DEBIAN_FRONTEND=noninteractive sudo apt-get install -y "${packages[@]}"; then
            log_error "Failed to install packages: ${packages[*]}"
            return 1
        fi
    } > "$temp_file" 2>&1
    
    local result=$?
    
    if [[ $result -ne 0 ]]; then
        log_error "Package installation failed. Last output:"
        tail -n 10 "$temp_file"
        rm -f "$temp_file"
        return $result
    fi
    
    rm -f "$temp_file"
    return 0
}

install_project_dependencies() {
    local project_dir="$1"
    cd "$project_dir" || return 1
    
    log_info "Checking for dependencies in $project_dir"
    
    # Node.js dependencies with testing setup
    if [[ -f "package.json" ]]; then
        log_info "Installing Node.js dependencies..."
        local has_testing_deps=false
        
        # Check if package.json contains testing-related dependencies
        if grep -q "\"playwright\"" "package.json"; then
            has_testing_deps=true
            if [[ "$has_testing_deps" == true ]]; then
                log_info "Installing system dependencies for testing..."
                if ! install_system_dependencies \
                    libgbm-dev \
                    libatk1.0-0 \
                    libatk-bridge2.0-0 \
                    libcups2 \
                    libdrm2 \
                    libxkbcommon0 \
                    libxcomposite1 \
                    libxdamage1 \
                    libxfixes3 \
                    libxrandr2 \
                    libgbm1 \
                    libasound2 \
                    chromium \
                    fonts-liberation \
                    libappindicator3-1 \
                    libnss3 \
                    libxss1 \
                    lsb-release \
                    xdg-utils; then
                    log_warning "Failed to install some system dependencies. Continuing with setup..."
                fi
            fi
        fi
        
        # Install dependencies
        if [[ -f "yarn.lock" ]]; then
            yarn install || log_warning "Yarn install failed in $project_dir"
            [[ "$has_testing_deps" == true ]] && yarn playwright install chromium
        else
            npm install || log_warning "NPM install failed in $project_dir"
            [[ "$has_testing_deps" == true ]] && npx playwright install chromium
        fi
    fi
    
    # Python dependencies with virtual environment
    if [[ -f "pyproject.toml" ]] || [[ -f "requirements.txt" ]]; then
        setup_python_venv "$project_dir"
    fi
    
    # Ruby dependencies with local gems
    if [[ -f "Gemfile" ]]; then
        log_info "Installing Ruby dependencies..."
        
        # Install Ruby system dependencies if needed
        if ! command -v ruby &> /dev/null || ! command -v gem &> /dev/null; then
            log_info "Installing Ruby system dependencies..."
            install_system_dependencies ruby-full build-essential zlib1g-dev
            
            # Configure gem installation path
            if ! grep -q "export GEM_HOME=\"\$HOME/.gems\"" ~/.bashrc; then
                echo '# Install Ruby Gems to ~/.gems' >> ~/.bashrc
                echo 'export GEM_HOME="$HOME/.gems"' >> ~/.bashrc
                echo 'export PATH="$HOME/.gems/bin:$PATH"' >> ~/.bashrc
            fi
            
            # Load the new environment variables
            export GEM_HOME="$HOME/.gems"
            export PATH="$HOME/.gems/bin:$PATH"
            
            # Create the gems directory if it doesn't exist
            mkdir -p "$HOME/.gems"
            
            # Install bundler
            gem install bundler
        fi
        
        # Configure bundler for local installation
        bundle config set --local path 'vendor/bundle'
        
        # Install project dependencies
        bundle install || log_warning "Bundle install failed in $project_dir"
    fi
    
    cd - > /dev/null
    log_success "Dependency installation completed for $project_dir"
}

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

setup_git_config() {
    local repo_root=$1
    local git_email=$2
    local git_name=$3
    
    git config --global --add safe.directory "$repo_root"
    git -C "$repo_root" config user.email "$git_email"
    git -C "$repo_root" config user.name "$git_name"

    # Setup hooks
    local hooks_dir="$repo_root/.git/hooks"
    mkdir -p "$hooks_dir"
    
    for hook in commit-msg pre-push prepare-commit-msg; do
        cp "$DEVCONTAINER_DIR/$hook" "$hooks_dir/"
        chmod 755 "$hooks_dir/$hook"
    done
    
    log_success "Git config and hooks set up for $repo_root"
}

setup_workspace() {
    log_info "Setting up workspace..."
    
    # Create commitlint config if it doesn't exist
    if [[ ! -f "$WORKSPACE_ROOT/commitlint.config.js" ]]; then
        cat > "$WORKSPACE_ROOT/commitlint.config.js" << 'EOF'
module.exports = {
    extends: ['@commitlint/config-conventional'],
};
EOF
    fi
    
    # Install commitlint if needed
    if ! command -v commitlint &> /dev/null; then
        npm install -g @commitlint/cli @commitlint/config-conventional
    fi
    
    # Set up git alias
    git config --global alias.new "!bash $WORKSPACE_ROOT/git-new-branch.sh"
    
    # Setup global git config from default settings
    git config --global --add safe.directory $WORKSPACE_ROOT
    local default_config=$(jq -r '.default' "$DEVCONTAINER_DIR/repo_config.json")
    git config --global user.email "$(echo "$default_config" | jq -r '.email')"
    git config --global user.name "$(echo "$default_config" | jq -r '.name')"

    # Install GitHub CLI with better error handling and background processing
    if ! command -v gh &> /dev/null; then
        log_info "Installing GitHub CLI..."
        {
            # Create a temporary file to store the installation output
            local temp_file=$(mktemp)
            
            # Run the installation in the background and redirect output
            {
                type -p curl >/dev/null || (sudo apt-get update && sudo apt-get install curl -y)
                curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
                sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
                sudo apt-get update -qq
                DEBIAN_FRONTEND=noninteractive sudo apt-get install -y gh
            } > "$temp_file" 2>&1 &
            
            # Store the background process ID
            local install_pid=$!
            
            # Wait for the installation to complete with a timeout
            local timeout=300  # 5 minutes timeout
            local counter=0
            while kill -0 $install_pid 2>/dev/null; do
                sleep 1
                ((counter++))
                if ((counter >= timeout)); then
                    kill $install_pid 2>/dev/null
                    log_warning "GitHub CLI installation timed out after ${timeout} seconds"
                    break
                fi
            done
            
            # Clean up
            rm -f "$temp_file"
        } || log_warning "GitHub CLI installation failed, but continuing with setup"
    fi
    
    log_success "Workspace setup completed"
}

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

setup_vscode_workspace() {
    log_info "Setting up VS Code workspace..."
    local workspace_file="$WORKSPACE_ROOT/Repos.code-workspace"
    
    local folders_json=$(jq -r '
        [
            {
                name: "root",
                path: "."
            },
            (
                keys[] | 
                select(. != "default") | 
                {
                    name: .,
                    path: (. | "./\(.)"),
                }
            )
        ]
    ' "$DEVCONTAINER_DIR/repo_config.json")
    
    jq -n --argjson folders "$folders_json" '
    {
        folders: $folders,
        settings: {
            "github.copilot.advanced": {
                "workspaceKindPriority": (
                    $folders | to_entries | map({
                        key: .value.name,
                        value: (.key + 1)
                    }) | from_entries
                )
            }
        }
    }' > "$workspace_file"
    
    log_success "Updated VS Code workspace file with enhanced configuration"
}

setup_python_venv() {
    local project_dir="$1"
    
    # Skip if this is inside a virtual environment
    if [[ "$project_dir" == *"/.venv/"* ]]; then
        return 0
    fi
    
    # Find the nearest directory containing pyproject.toml
    local current_dir="$project_dir"
    while [[ "$current_dir" != "/" ]]; do
        if [[ -f "$current_dir/pyproject.toml" ]]; then
            project_dir="$current_dir"
            break
        fi
        current_dir="$(dirname "$current_dir")"
    done
    
    # Ensure we're not in root directory
    if [[ "$project_dir" == "/" ]]; then
        log_error "Could not find pyproject.toml in parent directories"
        return 1
    fi
    
    cd "$project_dir" || return 1
    log_info "Setting up Python environment in $project_dir"
    
    # Install system dependencies required for building Python packages
    log_info "Installing Python build dependencies..."
    if ! install_system_dependencies \
        python3-dev \
        python3-pip \
        python3-venv \
        build-essential \
        libyaml-dev \
        libffi-dev \
        pkg-config; then
        log_warning "Failed to install some build dependencies"
    fi
    
    # Install poetry if not present
    if ! command -v poetry &> /dev/null; then
        log_info "Installing Poetry..."
        curl -sSL https://install.python-poetry.org | python3 -
        export PATH="/root/.local/bin:$HOME/.local/bin:$PATH"
    fi
    
    # Configure poetry to create virtual environments in the project directory
    poetry config virtualenvs.in-project true
    
    # Install dependencies with poetry
    if [[ -f "pyproject.toml" ]]; then
        log_info "Installing project dependencies with Poetry..."
        if ! poetry env use python3.9 2>/dev/null; then
            log_warning "Python 3.9 not available, falling back to system Python"
            poetry env use python3
        fi
        
        # Install dependencies (without timeout)
        PYTHON_KEYRING_BACKEND=keyring.backends.null.Keyring poetry install --no-interaction || \
            log_warning "Poetry install failed in $project_dir"
        
        # Create an activation script
        local activate_script="$project_dir/activate_venv.sh"
        cat > "$activate_script" << EOF
#!/bin/bash
poetry shell
echo "Activated virtual environment for $(basename "$project_dir")"
EOF
        chmod +x "$activate_script"
        
        log_info "Created activation script: $activate_script"
        log_info "To activate this venv, run: source $activate_script"
    fi
    
    cd - > /dev/null
}

setup_aws() {
    local account_dir="$1"
    local account_name="$(basename "$account_dir")"
    
    # Only configure AWS for LeadingEdje workspace
    if [[ "$account_name" != "leadingedje" ]]; then
        return 0
    fi
    
    log_info "Setting up AWS configuration for LeadingEdje workspace..."

    # Create workspace-specific AWS directory and saml2aws config
    local aws_dir="$account_dir/.aws"
    local saml2aws_config="$account_dir/.saml2aws"
    
    rm -rf "$aws_dir"
    rm -f "$saml2aws_config"
    mkdir -p "$aws_dir"

    # Install AWS CLI v2 using architecture-aware approach
    if ! command -v aws &> /dev/null; then
        log_info "Installing AWS CLI..."
        
        local temp_dir=$(mktemp -d)
        cd "$temp_dir"
        
        # Detect architecture
        local arch=$(uname -m)
        local aws_cli_url
        case $arch in
            "x86_64")
                aws_cli_url="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
                ;;
            "aarch64")
                aws_cli_url="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip"
                ;;
            *)
                log_error "Unsupported architecture: $arch"
                return 1
                ;;
        esac
        
        # Download and install AWS CLI v2
        if curl -fsSL "$aws_cli_url" -o "awscliv2.zip"; then
            unzip -q awscliv2.zip
            sudo ./aws/install
            
            # Cleanup
            cd - > /dev/null
            rm -rf "$temp_dir"
            
            if [[ -x "/usr/local/bin/aws" ]]; then
                log_success "AWS CLI installed successfully for $arch architecture"
            else
                log_error "AWS CLI installation failed"
                return 1
            fi
        else
            log_error "Failed to download AWS CLI installer"
            return 1
        fi
    fi
    
    # Install saml2aws if not present
    if ! command -v saml2aws &> /dev/null; then
        log_info "Installing saml2aws..."
        CURRENT_VERSION=$(curl -Ls https://api.github.com/repos/Versent/saml2aws/releases/latest | grep 'tag_name' | cut -d'v' -f2 | cut -d'"' -f1)
        wget -q https://github.com/Versent/saml2aws/releases/download/v${CURRENT_VERSION}/saml2aws_${CURRENT_VERSION}_linux_amd64.tar.gz
        tar -xzf saml2aws_${CURRENT_VERSION}_linux_amd64.tar.gz -C /tmp
        sudo mv /tmp/saml2aws /usr/local/bin/
        sudo chmod u+x /usr/local/bin/saml2aws
        rm -f saml2aws_${CURRENT_VERSION}_linux_amd64.tar.gz
        rm -rf /tmp/*.md
    fi

    # Configure AWS CLI default settings
    cat > "$aws_dir/config" << EOF
[profile development]
region = us-east-2
role_arn       = arn:aws:iam::702328517568:role/DevOpsRole
output = json
source_profile = le-sso
EOF

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
aws_profile             = le-sso
region                  = us-east-2
EOF

    # Update workspace environment with xvfb wrapper
    local workspace_env="$account_dir/.workspace_env"
    cat > "$workspace_env" << 'EOF'
# AWS Configuration for LeadingEdje workspace
export AWS_SHARED_CREDENTIALS_FILE="$aws_dir/credentials"
export SAML2AWS_CONFIGFILE="$saml2aws_config"
export AWS_PROFILE=default
export AWS_DEFAULT_REGION=us-east-2
EOF

    #TODO: Add AWS CLI completion script
    #TODO: Add saml2aws completion script
    #TODO: Add AWS CLI and saml2aws aliases
    #TODO: Install stackmanager for AWS CloudFormation

    # Source workspace environment in bashrc if not already present
    if ! grep -q "source.*$workspace_env" ~/.bashrc; then
        echo "
# Source LeadingEdje workspace environment
if [[ \"\$PWD\" == \"$account_dir\"* ]] && [[ -f \"$workspace_env\" ]]; then
    source \"$workspace_env\"
fi" >> ~/.bashrc
    fi

    log_success "AWS configuration set up for LeadingEdje workspace"
    log_info "To use AWS CLI and saml2aws:"
    log_info "1. cd into ${account_dir}"
    log_info "2. source .workspace_env"
    log_info "3. aws_login           # Login to AWS"
    log_info "4. aws_roles          # List available roles"
    log_info "5. aws_switch PROFILE  # Switch between profiles"
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
        
        # Setup git config and install dependencies for any existing repositories
        if [[ -d "$account_dir" ]]; then
            setup_aws "$account_dir"
            
            # First, handle git repositories
            find "$account_dir" -type d -name ".git" -exec dirname {} \; | while read -r repo_dir; do
                setup_git_config "$repo_dir" "$git_email" "$git_name"
                install_project_dependencies "$repo_dir"
            done
            
            # Then, recursively search for Python projects
            find "$account_dir" -type f \( -name "pyproject.toml" -o -name "requirements.txt" \) -exec dirname {} \; | while read -r python_dir; do
                log_info "Found Python project in: $python_dir"
                setup_python_venv "$python_dir"
            done
        fi
    done
}

main() {
    validate_requirements
    setup_environment
    setup_bashrc
    setup_workspace
    create_account_directories
    setup_vscode_workspace
    setup_account_repositories
    
    log_success "Workspace setup complete!"
}

main "$@"