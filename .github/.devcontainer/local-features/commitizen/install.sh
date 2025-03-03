#!/bin/sh
set -e

echo "Installing Commitizen and related tools..."
npm install -g commitizen
npm install -g @commitlint/cli
npm install -g @commitlint/config-conventional