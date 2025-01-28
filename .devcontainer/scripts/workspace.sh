#!/bin/bash

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
    
    # Install GitHub CLI with better error handling
    if ! command -v gh &> /dev/null; then
        install_github_cli
    fi
    
    log_success "Workspace setup completed"
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

install_github_cli() {
    log_info "Installing GitHub CLI..."
    local temp_file=$(mktemp)
    
    {
        type -p curl >/dev/null || (sudo apt-get update && sudo apt-get install curl -y)
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
        sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
        sudo apt-get update -qq
        DEBIAN_FRONTEND=noninteractive sudo apt-get install -y gh
    } > "$temp_file" 2>&1 || log_warning "GitHub CLI installation failed, but continuing with setup"
    
    rm -f "$temp_file"
}
