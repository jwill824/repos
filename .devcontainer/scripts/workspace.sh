#!/bin/bash

setup_workspace() {
    log_info "Setting up workspace..."

    # Install cz-git as dev dependency and update package.json
    npm install -D cz-git

    # Add commitizen config to package.json if not present
    if ! jq -e '.config.commitizen' "$WORKSPACE_ROOT/package.json" > /dev/null; then
        jq '. * {
            "config": {
                "commitizen": {
                    "path": "node_modules/cz-git"
                }
            }
        }' "$WORKSPACE_ROOT/package.json" > "$WORKSPACE_ROOT/package.json.tmp" && mv "$WORKSPACE_ROOT/package.json.tmp" "$WORKSPACE_ROOT/package.json"
    fi

    # Set up git hooks for workspace root
    setup_pre_commit "$WORKSPACE_ROOT"

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
            },
            "powershell.cwd": "root"
        }
    }' > "$workspace_file"

    log_success "Updated VS Code workspace file with enhanced configuration"
}
