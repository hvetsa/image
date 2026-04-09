#!/bin/bash
set -euo pipefail

# ─── SSH Key Setup ──────────────────────────────────────────────────────────
# Copy SSH private key from mounted secure zone (if available)
if [[ -f ${SSH_PRIVATE_KEY_PATH:-} ]]; then
    mkdir -p /root/.ssh
    cp ${SSH_PRIVATE_KEY_PATH} /root/.ssh/id_rsa
    chmod 600 /root/.ssh/id_rsa
    # Generate public key if not present
    if [[ ! -f /root/.ssh/id_rsa.pub ]]; then
        ssh-keygen -y -f /root/.ssh/id_rsa > /root/.ssh/id_rsa.pub
    fi
    # Ensure SSH config allows the key
    echo 'IdentityFile ~/.ssh/id_rsa' >> /root/.ssh/config
    chmod 600 /root/.ssh/config
fi

# ─── Secrets Environment ────────────────────────────────────────────────────
# Source secrets file from mounted secure zone (if available)
if [[ -f ${SECRETS_FILE_PATH:-} ]]; then
    set -a  # Export all variables
    source ${SECRETS_FILE_PATH}
    set +a
fi

# ─── Git Configuration ──────────────────────────────────────────────────────
# Set git user config (override build defaults if needed)
if [[ -n "${GIT_AUTHOR_NAME:-}" ]]; then
    git config --global user.name "$GIT_AUTHOR_NAME"
else
    git config --global user.name "Hari Vetsa"
fi

if [[ -n "${GIT_AUTHOR_EMAIL:-}" ]]; then
    git config --global user.email "$GIT_AUTHOR_EMAIL"
else
    git config --global user.email "hvetsa@yahoo.com"
fi

# Make all directories safe for git operations
git config --global --add safe.directory '*'

# Link SSH Files to Home Directory (if not already linked)
if [[ ! -L $HOME/.ssh/id_rsa && -f /root/.ssh/id_rsa ]]; then
    mkdir -p $HOME/.ssh
    ln -s /Users/hvetsa/.ssh/id_rsa $HOME/.ssh/id_rsa
fi

# Restore sessions for AI tools (if session files are available in secure zone)
for ai in gemini claude copilot; do
    (cd $HOME/ && rm -rf .${ai} && tar xf /Users/hvetsa/Documents/DockerSubSystem/secure_zone/${ai}session.tar)
done



# ─── Execute Command ────────────────────────────────────────────────────────
# Execute the provided command (default to bash)
exec "$@"
