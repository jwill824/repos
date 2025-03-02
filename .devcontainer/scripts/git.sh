#!/bin/bash

setup_global_git_config() {
    local git_email=$1
    local git_name=$2
    git config --global user.email "$git_email"
    git config --global user.name "$git_name"
    log_success "Global git config set up"
}

setup_local_git_config() {
    local repo_root=$1
    local git_email=$2
    local git_name=$3
    local account=$4

    # Basic git config
    git config --global --add safe.directory "$repo_root"
    git -C "$repo_root" config --local user.email "$git_email"
    git -C "$repo_root" config --local user.name "$git_name"

    # Setup pre-commit configuration
    setup_pre_commit "$repo_root"

    # Enable path-specific credentials
    git -C "$repo_root" config --local credential.useHttpPath true

    # Configure repository-specific credentials
    configure_git_auth "$repo_root" "$account"

    log_success "Git config set up for $repo_root"
}

generate_pre_commit_config() {
    local hooks_dir=$1
    local config=""

    # Start with standard hooks
    config=$(cat <<-EOF
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: debug-statements
      - id: double-quote-string-fixer
      - id: name-tests-test
      - id: requirements-txt-fixer
  - repo: local
    hooks:
EOF
)

    # Find all hook files and sort them
    for hook_file in "$hooks_dir"/pre-*-*; do
        if [ -f "$hook_file" ]; then
            # Extract full hook type (including 'pre-') and name
            filename=$(basename "$hook_file")
            hook_type=$(echo "$filename" | cut -d'-' -f1,2)
            hook_name=$(echo "$filename" | cut -d'-' -f3-)

            # Generate hook configuration
            config+=$(cat <<-EOF

      - id: $hook_name
        name: $hook_name
        entry: $hook_file
        language: script
        stages: [$hook_type]
        pass_filenames: false
EOF
)
        fi
    done

    echo "$config"
}

setup_pre_commit() {
    local repo_root=$1
    local hooks_dir="$DEVCONTAINER_DIR/hooks"
    local repo_config_file="$repo_root/.pre-commit-config.yaml"

    # Generate pre-commit config
    generate_pre_commit_config "$hooks_dir" > "$repo_config_file"

    # Add .pre-commit-config.yaml to .gitignore if not already present
    if ! grep -q "^\.pre-commit-config\.yaml$" "$repo_root/.gitignore" 2>/dev/null; then
        echo ".pre-commit-config.yaml" >> "$repo_root/.gitignore"
    fi

    # Get unique hook types from filenames
    local hook_types
    hook_types=$(find "$hooks_dir" -name "pre-*-*" -type f -exec basename {} \; | cut -d'-' -f1,2 | sort -u)

    # Install each hook type
    for hook_type in "${hook_types[@]}"; do
        cd "$repo_root" && pre-commit install --hook-type "$hook_type"
    done

    log_success "Pre-commit hooks configured for $repo_root"
}

configure_git_line_endings() {
    local repo_root=$1
    local line_ending=$2
    git -C "$repo_root" config core.autocrlf "$line_ending"
    log_success "Configured line endings ($line_ending) for $repo_root"
}

configure_git_auth() {
    local repo_root=$1
    local account=$2
    local remote_url
    remote_url=$(git -C "$repo_root" config --get remote.origin.url)
    if [[ -z "$remote_url" ]]; then
        return
    fi

    # Use Git Credential Manager for the repository
    git -C "$repo_root" config --local credential.helper manager

    # Get account's git config
    local git_config
    git_config=$(jq -r ".$account.git // empty" "$DEVCONTAINER_DIR/repo_config.json")
    if [[ -z "$git_config" ]]; then
        return
    fi

    # Ensure credential helper is set for the repository
    git -C "$repo_root" config --local credential.helper manager
    git -C "$repo_root" config --local credential.useHttpPath true

    # Configure based on provider
    if [[ "$remote_url" =~ .*visualstudio.com.* ]] || [[ "$remote_url" =~ .*azure.com.* ]]; then
        local domain
        local username
        domain=$(echo "$git_config" | jq -r '.azure.domain')
        username=$(echo "$git_config" | jq -r '.azure.username')
        if [[ -n "$username" ]] && [[ -n "$domain" ]]; then
            git -C "$repo_root" config --local "credential.https://${domain}.helper" manager
            git -C "$repo_root" config --local "credential.https://${domain}.username" "$username"
        fi
    elif [[ "$remote_url" =~ .*github.com.* ]]; then
        local github_config
        local username
        local org

        github_config=$(echo "$git_config" | jq -r '.github')
        username=$(echo "$github_config" | jq -r '.username')
        org=$(echo "$remote_url" | sed -E 's#https://github.com/([^/]+)/.*#\1#')

        if [[ -n "$username" ]]; then
            # Remove any existing credential configurations
            git -C "$repo_root" config --local --unset-all "credential.https://github.com.username" || true

            # Set new credential configurations
            git -C "$repo_root" config --local "credential.https://github.com.helper" manager
            git -C "$repo_root" config --local "credential.https://github.com.username" "$username"

            # Ensure the remote URL is clean
            if [[ "$remote_url" =~ .*@github.com.* ]]; then
                local new_url="https://github.com/${org}/${remote_url##*/}"
                git -C "$repo_root" config remote.origin.url "$new_url"
            fi
        fi
    elif [[ "$remote_url" =~ .*bitbucket.org.* ]]; then
        local bitbucket_config
        local username
        local team

        bitbucket_config=$(echo "$git_config" | jq -r '.bitbucket')
        username=$(echo "$bitbucket_config" | jq -r '.username')
        team=$(echo "$remote_url" | sed -E 's#https://[^@]*@?bitbucket.org/([^/]+)/.*#\1#')

        if [[ -n "$username" ]]; then
            # Update remote URL to include username if not present
            if [[ ! "$remote_url" =~ .*@bitbucket.org.* ]]; then
                local new_url="https://${username}@bitbucket.org/${team}/${remote_url##*/}"
                git -C "$repo_root" config remote.origin.url "$new_url"
            fi

            git -C "$repo_root" config --local "credential.https://bitbucket.org.helper" manager
            git -C "$repo_root" config --local "credential.https://bitbucket.org/$team.helper" manager
            git -C "$repo_root" config --local "credential.https://bitbucket.org.username" "$username"
            git -C "$repo_root" config --local "credential.https://bitbucket.org/$team.username" "$username"
        fi
    fi

    log_success "Configured git credentials for $repo_root"
}
