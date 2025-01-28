#!/bin/bash

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
