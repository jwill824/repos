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
    git config --global alias.new "!bash $HOOKS_DIR/git-new-branch.sh"
    
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
