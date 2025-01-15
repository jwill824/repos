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

install_project_dependencies() {
    local project_dir="$1"
    cd "$project_dir" || return 1
    
    log_info "Checking for dependencies in $project_dir"
    
    # Node.js dependencies with testing setup
    if [[ -f "package.json" ]]; then
        log_info "Installing Node.js dependencies..."
        local has_testing_deps=false
        
        # Check if package.json contains testing-related dependencies
        if grep -q "\"jest\"\|\"playwright\"\|\"puppeteer\"" "package.json"; then
            has_testing_deps=true
            # Install system dependencies for Playwright/Chrome if needed
            if [[ "$has_testing_deps" == true ]]; then
                log_info "Installing system dependencies for testing..."
                sudo apt-get update && sudo apt-get install -y \
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
                    xdg-utils
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
            sudo apt-get update
            sudo apt-get install -y ruby-full build-essential zlib1g-dev
        fi
        
        # Set local bundle config
        bundle config set --local path 'vendor/bundle'
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

    if ! command -v gh &> /dev/null; then
        log_info "Installing GitHub CLI..."
        {
            type -p curl >/dev/null || (sudo apt update && sudo apt install curl -y)
            curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
            && sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
            && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
            && sudo apt update \
            && sudo apt install gh -y
        } || log_warning "GitHub CLI installation failed, but continuing with setup"
    fi
    
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
    local venv_name=".venv"
    
    cd "$project_dir" || return 1
    log_info "Setting up Python virtual environment for $project_dir"
    
    # Create virtual environment if it doesn't exist
    if [[ ! -d "$venv_name" ]]; then
        python -m venv "$venv_name"
        log_success "Created virtual environment in $project_dir/$venv_name"
    fi
    
    # Activate virtual environment and install dependencies
    source "$venv_name/bin/activate"
    
    # Upgrade pip in the virtual environment
    pip install --upgrade pip
    
    # Install dependencies based on what files exist
    if [[ -f "pyproject.toml" ]]; then
        if ! command -v poetry &> /dev/null; then
            curl -sSL https://install.python-poetry.org | python3 -
        fi
        poetry install || log_warning "Poetry install failed in $project_dir"
    elif [[ -f "requirements.txt" ]]; then
        pip install -r requirements.txt || log_warning "Pip install failed in $project_dir"
    fi
    
    cd - > /dev/null
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
            find "$account_dir" -type d -name ".git" -exec dirname {} \; | while read -r repo_dir; do
                setup_git_config "$repo_dir" "$git_email" "$git_name"
                install_project_dependencies "$repo_dir"
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
    log_info "You can now use 'git new' to create a new branch following the conventional commit pattern."
}

main "$@"