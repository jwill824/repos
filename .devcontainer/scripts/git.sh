#!/bin/bash

setup_global_git_config() {
    local git_email=$1
    local git_name=$2
    git config --global user.email "$git_email"
    git config --global user.name "$git_name"

    # Configure credential helper to store credentials
    git config --global credential.helper store
    git config --global credential.useHttpPath true
    
    # Let VS Code's credential helper handle default authentication
    git config --global credential.https://github.com.username "$git_email"

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

    # Setup hooks
    local hooks_dir="$repo_root/.git/hooks"
    mkdir -p "$hooks_dir"
    for hook in commit-msg pre-push prepare-commit-msg; do
        cp "$HOOKS_DIR/$hook" "$hooks_dir/"
        chmod 755 "$hooks_dir/$hook"
    done
    
    # Enable path-specific credentials
    git -C "$repo_root" config --local credential.useHttpPath true
    
    # Configure repository-specific credentials
    configure_git_auth "$repo_root" "$account"
    
    log_success "Git config set up for $repo_root"
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
    local remote_url=$(git -C "$repo_root" config --get remote.origin.url)
    if [[ -z "$remote_url" ]]; then
        return
    fi

    # Get account's git config
    local git_config=$(jq -r ".$account.git // empty" "$DEVCONTAINER_DIR/repo_config.json")
    if [[ -z "$git_config" ]]; then
        return
    fi

    # Ensure credential helper is set for the repository
    git -C "$repo_root" config --local credential.helper store
    git -C "$repo_root" config --local credential.useHttpPath true

    # Configure based on provider
    if [[ "$remote_url" =~ .*visualstudio.com.* ]] || [[ "$remote_url" =~ .*azure.com.* ]]; then
        local domain=$(echo "$git_config" | jq -r '.azure.domain')
        local username=$(echo "$git_config" | jq -r '.azure.username')
        if [[ -n "$username" ]] && [[ -n "$domain" ]]; then
            git -C "$repo_root" config --local "credential.https://${domain}.helper" store
            git -C "$repo_root" config --local "credential.https://${domain}.username" "$username"
        fi
    elif [[ "$remote_url" =~ .*github.com.* ]]; then
        local github_config=$(echo "$git_config" | jq -r '.github')
        local username=$(echo "$github_config" | jq -r '.username')
        local org=$(echo "$remote_url" | sed -E 's#https://github.com/([^/]+)/.*#\1#')
        
        if [[ -n "$username" ]]; then
            git -C "$repo_root" config --local "credential.https://github.com.helper" store
            git -C "$repo_root" config --local "credential.https://github.com/$org.helper" store
            git -C "$repo_root" config --local "credential.https://github.com/$org.username" "$username"
        fi
    elif [[ "$remote_url" =~ .*bitbucket.org.* ]]; then
        local bitbucket_config=$(echo "$git_config" | jq -r '.bitbucket')
        local username=$(echo "$bitbucket_config" | jq -r '.username')
        local team=$(echo "$remote_url" | sed -E 's#https://[^@]*@?bitbucket.org/([^/]+)/.*#\1#')
        
        if [[ -n "$username" ]]; then
            # Update remote URL to include username if not present
            if [[ ! "$remote_url" =~ .*@bitbucket.org.* ]]; then
                local new_url="https://${username}@bitbucket.org/${team}/${remote_url##*/}"
                git -C "$repo_root" config remote.origin.url "$new_url"
            fi
            
            git -C "$repo_root" config --local "credential.https://bitbucket.org.helper" store
            git -C "$repo_root" config --local "credential.https://bitbucket.org/$team.helper" store
            git -C "$repo_root" config --local "credential.https://bitbucket.org.username" "$username"
            git -C "$repo_root" config --local "credential.https://bitbucket.org/$team.username" "$username"
        fi
    fi
    
    log_success "Configured git credentials for $repo_root"
}
