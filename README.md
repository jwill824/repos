# VS Code Ultimate Dev Setup

## Pre-requisites

- VS Code
- Docker Desktop

## How this works

1. Dotfiles clones this repo to your chosen location
2. Open VSCode and `Open Workspace from file...` OR
3. Open your terminal and the following command:

    ```bash
    code ~/Developer/repos/Repos.code-workspace
    ```

## Git Commit Hook Setup

The repository includes an AI-powered commit message generator that uses Anthropic's Claude API. To set it up:

1. Get an API key from [Anthropic](https://console.anthropic.com/)
2. Configure the API key (choose one method):

   ```bash
   # Option 1: Set in git config (recommended)
   git config --global ai.apikey "your-api-key"
   
   # Option 2: Set as environment variable
   export ANTHROPIC_API_KEY="your-api-key"
   ```

The hook will automatically generate commit messages based on your changes.

