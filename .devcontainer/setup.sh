#!/bin/bash

# Function to add a directory as safe
add_safe_directory() {
    git config --global --add safe.directory "$1"
    echo "Added safe directory: $1"
}

# File to store repository paths
repo_list_file="/workspaces/repos/.devcontainer/repo_list.json"

# Configuration file for repository accounts
repo_config_file="/workspaces/repos/.devcontainer/repo_config.json"

# Git hook files
commit_msg_hook="/workspaces/repos/.devcontainer/commit-msg"
pre_push_hook="/workspaces/repos/.devcontainer/pre-push"

# Check if required files exist
for file in "$repo_config_file" "$commit_msg_hook" "$pre_push_hook"; do
    if [ ! -f "$file" ]; then
        echo "Error: Required file not found: $file"
        exit 1
    fi
done

# Initialize the JSON array for repo list
echo "[" > "$repo_list_file"

# Create a shared commitlint config file in the workspace root
cat << 'EOF' > /workspaces/repos/commitlint.config.js
module.exports = {
  extends: ['@commitlint/config-conventional'],
  // Add any custom rules here
};
EOF

# Install commitlint globally if not already installed
if ! command -v commitlint &> /dev/null; then
    npm install -g @commitlint/cli @commitlint/config-conventional
fi

# Create a script for the new branch command
cat << 'EOF' > /workspaces/repos/git-new-branch.sh
#!/bin/bash
echo "Select branch type:"
echo "1) feature"
echo "2) fix"
echo "3) docs"
echo "4) style"
echo "5) refactor"
echo "6) test"
echo "7) chore"
read -p "Enter the number of your choice: " choice

case $choice in
    1) type="feature" ;;
    2) type="fix" ;;
    3) type="docs" ;;
    4) type="style" ;;
    5) type="refactor" ;;
    6) type="test" ;;
    7) type="chore" ;;
    *) echo "Invalid choice. Exiting."; exit 1 ;;
esac

read -p "Enter a brief description (use-hyphens-for-spaces): " description

branch_name="${type}/${description}"
git checkout -b "$branch_name"
git push -u origin "$branch_name"
echo "Created, pushed, and set upstream for branch: $branch_name"
EOF

chmod +x /workspaces/repos/git-new-branch.sh

# Set up the git alias for the new branch command
git config --global alias.new '!bash /workspaces/repos/git-new-branch.sh'

# Function to set up global git config
setup_global_git_config() {
    local default_email=$(jq -r '.default.email' "$repo_config_file")
    local default_name=$(jq -r '.default.name' "$repo_config_file")

    git config --global user.email "$default_email"
    git config --global user.name "$default_name"
    echo "Set up global git config with email: $default_email and name: $default_name"
}

# Function to set up a repository
setup_repo() {
    local repo_root=$1
    local git_email=$2
    local git_name=$3

    echo "Setting up repository: $repo_root"
    
    add_safe_directory "$repo_root"
    
    # Set git config for this repository
    git -C "$repo_root" config user.email "$git_email"
    git -C "$repo_root" config user.name "$git_name"

    # Copy git hooks
    mkdir -p "$repo_root/.git/hooks"
    echo "Copying commit-msg hook from $commit_msg_hook to $repo_root/.git/hooks/commit-msg"
    cp "$commit_msg_hook" "$repo_root/.git/hooks/commit-msg"
    echo "Copying pre-push hook from $pre_push_hook to $repo_root/.git/hooks/pre-push"
    cp "$pre_push_hook" "$repo_root/.git/hooks/pre-push"
    chmod 755 "$repo_root/.git/hooks/commit-msg" "$repo_root/.git/hooks/pre-push"
    
    echo "Verifying hooks and permissions:"
    ls -l "$repo_root/.git/hooks"
    
    echo "Content of commit-msg hook:"
    cat "$repo_root/.git/hooks/commit-msg"
    
    echo "Git config and hooks set up for $repo_root"

    # Append the repo path to the JSON array
    echo "  \"$repo_root\"," >> "$repo_list_file"
}

# Function to update VS Code workspace file
update_vscode_workspace() {
    local workspace_file="/workspaces/repos/Repos.code-workspace"
    local workspace_content=$(jq -n \
        --arg folders "$(jq -n \
            --arg root "." \
            --arg crown "crown" \
            --arg leadingedje "leadingedje" \
            --arg personal "personal" \
            '[
                {"path": $root},
                {"path": $crown},
                {"path": $leadingedje},
                {"path": $personal}
            ]'
        )" \
        '{
            "folders": $folders | fromjson,
            "settings": {}
        }'
    )

    echo "$workspace_content" > "$workspace_file"
    echo "Updated VS Code workspace file"
}

# Function to set up repositories for a subdirectory
setup_subdirectory() {
    local subdir=$1
    local config=$(jq -r ".$subdir" "$repo_config_file")
    
    if [ "$config" == "null" ]; then
        echo "Error: Configuration not found for subdirectory: $subdir"
        return 1
    fi
    
    local git_email=$(echo "$config" | jq -r '.email')
    local git_name=$(echo "$config" | jq -r '.name')

    echo "Setting up repositories in $subdir"
    
    # Find all directories in the subdirectory
    find "/workspaces/repos/$subdir" -type d | while read dir; do
        # Check if this directory is a Git repository
        if [ -d "$dir/.git" ]; then
            setup_repo "$dir" "$git_email" "$git_name"
        fi
    done
}

# Read subdirectories from config file and set up repositories
jq -r 'keys[]' "$repo_config_file" | while read subdir; do
    setup_subdirectory "$subdir"
done

# Remove the last comma and close the JSON array
sed -i '$ s/,$//' "$repo_list_file"
echo "]" >> "$repo_list_file"

# Print all safe directories for verification
echo "All safe directories:"
git config --global --get-all safe.directory

echo "Repository paths have been saved to $repo_list_file"

# Call the function to update VS Code workspace
update_vscode_workspace

# Set up global git config
setup_global_git_config

# Read subdirectories from config file and set up repositories
jq -r 'keys[] | select(. != "default")' "$repo_config_file" | while read subdir; do
    setup_subdirectory "$subdir"
done

# Set up Python virtual environment in a writable location
VENV_PATH="/workspaces/repos/.venv"
python -m venv $VENV_PATH
source $VENV_PATH/bin/activate

# Install any Python packages you commonly use
pip install --upgrade pip
pip install pytest black flake8

echo "Workspace setup complete!"
echo "You can now use 'git new' to create a new branch following the conventional commit pattern."