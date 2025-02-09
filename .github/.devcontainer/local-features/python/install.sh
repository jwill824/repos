#!/bin/bash

set -e

# Clean up
rm -rf /var/lib/apt/lists/*

# Install dependencies
apt-get update
apt-get install -y --no-install-recommends \
    make build-essential libssl-dev zlib1g-dev \
    libbz2-dev libreadline-dev libsqlite3-dev \
    libncursesw5-dev xz-utils tk-dev libxml2-dev \
    libxmlsec1-dev libffi-dev liblzma-dev curl git

# Parse input versions
IFS=',' read -ra PYTHON_VERSIONS <<< "${VERSION}"

# Install pyenv
export PYENV_ROOT="/usr/local/pyenv"
curl -L https://github.com/pyenv/pyenv-installer/raw/master/bin/pyenv-installer | bash

# Add pyenv to path
export PATH="${PYENV_ROOT}/bin:${PATH}"
eval "$(pyenv init -)"

# Install requested Python versions
for version in "${PYTHON_VERSIONS[@]}"; do
    pyenv install "${version}"
done

# Set global Python version to the last one in the list
pyenv global "${PYTHON_VERSIONS[-1]}"

# Install Poetry if requested
if [ "${INSTALLPOETRY}" = "true" ]; then
    export POETRY_HOME="/usr/local/poetry"
    curl -sSL https://install.python-poetry.org | python3 -
    poetry config virtualenvs.in-project true
fi

# Install additional tools
IFS=',' read -ra TOOLS <<< "${TOOLSTOINSTALL}"
for tool in "${TOOLS[@]}"; do
    pip install "${tool}"
done

# Add environment setup to bashrc and zshrc
echo 'export PYENV_ROOT="/usr/local/pyenv"' >> /etc/bash.bashrc
echo 'export PATH="$PYENV_ROOT/bin:$PATH"' >> /etc/bash.bashrc
echo 'eval "$(pyenv init -)"' >> /etc/bash.bashrc

if [ -f "/etc/zsh/zshrc" ]; then
    echo 'export PYENV_ROOT="/usr/local/pyenv"' >> /etc/zsh/zshrc
    echo 'export PATH="$PYENV_ROOT/bin:$PATH"' >> /etc/zsh/zshrc
    echo 'eval "$(pyenv init -)"' >> /etc/zsh/zshrc
fi

# Clean up
apt-get clean
rm -rf /var/lib/apt/lists/*
