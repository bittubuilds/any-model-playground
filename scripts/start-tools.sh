#!/usr/bin/env bash
# Starts the keyless web-tools service (search + page reading) next to Ollama.
set -u
cd /workspaces/any-model-playground 2>/dev/null || exit 0
pkill -f tools_server.py 2>/dev/null || true
nohup python3 tools_server.py 8765 > /tmp/tools.log 2>&1 &
sleep 1
echo "tools service on 8765"
