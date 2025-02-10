#!/bin/bash

# Logging
log_info() { echo "ℹ️ $*"; }
log_success() { echo "✓ $*"; }
log_warning() { echo "⚠️ $*"; }
log_error() { echo "❌ $*" >&2; }

# Constants
export WORKSPACE_ROOT="/workspaces/repos"
export DEVCONTAINER_DIR="$WORKSPACE_ROOT/.devcontainer"
export SCRIPTS_DIR="$DEVCONTAINER_DIR/scripts"
export HOOKS_DIR="$DEVCONTAINER_DIR/hooks"

# Source all script files
for script in "$SCRIPTS_DIR"/*.sh; do
    source "$script"
done

# Main execution
main() {
    setup_workspace
    create_account_directories
    setup_vscode_workspace
    setup_account_repositories
    
    log_success "Workspace setup complete!"
}

# Run main function
main