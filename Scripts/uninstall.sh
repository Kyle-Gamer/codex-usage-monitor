#!/bin/zsh
set -euo pipefail

INSTALL_PATH="$HOME/Applications/Codex Usage Monitor.app"

if [[ -d "$INSTALL_PATH" ]]; then
    rm -rf "$INSTALL_PATH"
    echo "Removed: $INSTALL_PATH"
else
    echo "Not installed: $INSTALL_PATH"
fi
