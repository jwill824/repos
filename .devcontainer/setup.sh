#!/bin/bash

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
    validate_requirements
    setup_environment
    setup_bashrc
    setup_workspace
    create_account_directories
    setup_vscode_workspace
    setup_account_repositories
    setup_dotfiles_test_environment
    
    log_success "Workspace setup complete!"
}

# Run main function
main