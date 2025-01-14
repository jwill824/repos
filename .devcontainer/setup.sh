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

    # Install gh cli
    # https://github.com/cli/cli/blob/trunk/docs/install_linux.md
    (type -p wget >/dev/null || (sudo apt update && sudo apt-get install wget -y)) \
        && sudo mkdir -p -m 755 /etc/apt/keyrings \
            && out=$(mktemp) && wget -nv -O$out https://cli.github.com/packages/githubcli-archive-keyring.gpg \
            && cat $out | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
        && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
        && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
        && sudo apt update \
        && sudo apt install gh -y

    
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
    
    # Get all account names (excluding 'default') and create folders array
    local folders_json=$(jq -r '
        [
            {path: "."},
            (
                keys[] | 
                select(. != "default") | 
                {path: .}
            )
        ]
    ' "$DEVCONTAINER_DIR/repo_config.json")
    
    # Create workspace file with dynamic folders
    jq -n --argjson folders "$folders_json" '{
        folders: $folders,
        settings: {}
    }' > "$workspace_file"
    
    log_success "Updated VS Code workspace file"
}

setup_python_environment() {
    log_info "Setting up Python environment..."
    
    python -m venv "$VENV_PATH"
    source "$VENV_PATH/bin/activate"
    
    pip install --upgrade pip
    pip install pytest black flake8 aiohttp
    
    log_success "Python environment configured"
}

setup_ruby_environment() {
    log_info "Setting up Ruby environment..."

    # Update package list
    sudo apt-get update

    # Install Ruby and development tools
    sudo apt-get install -y ruby-full build-essential zlib1g-dev

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

    # Install Jekyll and Bundler without sudo
    gem install jekyll bundler

    log_success "Ruby environment configured"
}

setup_testing_environment() {
    log_info "Setting up testing environment..."

    # Install system dependencies for Playwright/Chrome
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

    # Install Node.js testing dependencies
    npm install -g \
        @testing-library/jest-dom \
        @testing-library/dom \
        jest \
        jest-environment-jsdom \
        lighthouse \
        pixelmatch \
        playwright \
        pngjs

    # Install Playwright browsers
    npx playwright install chromium

    # Install additional Ruby gems for testing
    gem install \
        html-proofer \
        webrick \
        nokogiri

    log_success "Testing environment set up successfully"
}

setup_resume_project() {
    log_info "Setting up resume project..."
    
    local project_dir="$WORKSPACE_ROOT/personal/resume"
    
    # Create test directories if they don't exist
    mkdir -p "$project_dir/tests/results"
    
    # Install project-specific dependencies
    if [[ -f "$project_dir/package.json" ]]; then
        (cd "$project_dir" && npm install)
    fi
    
    # Install Ruby dependencies
    if [[ -f "$project_dir/Gemfile" ]]; then
        (cd "$project_dir" && bundle install)
    fi
    
    log_success "Resume project setup complete"
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
        
        # Setup git config for any existing repositories
        if [[ -d "$account_dir" ]]; then
            find "$account_dir" -type d -name ".git" -exec dirname {} \; | while read -r repo_dir; do
                setup_git_config "$repo_dir" "$git_email" "$git_name"
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
    setup_python_environment
    setup_ruby_environment
    setup_testing_environment
    setup_resume_project
    setup_account_repositories
    
    log_success "Workspace setup complete!"
    log_info "You can now use 'git new' to create a new branch following the conventional commit pattern."
}

main "$@"