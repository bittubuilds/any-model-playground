#!/usr/bin/env bash
# Idempotent Ollama bootstrap for GitHub Codespaces (or any container without systemd).
# - installs Ollama if the binary is missing
# - starts `ollama serve` in the background on 0.0.0.0:11434 with CORS open
# - pulls the model named by $OLLAMA_MODEL if it is not there yet
#
# Override the model, e.g.:
#   OLLAMA_MODEL=eriktonon/qwen3.8-uncensored:9b bash scripts/start-ollama.sh
set -uo pipefail

MODEL="${OLLAMA_MODEL:-s1gnature/gemma4-uncensored-mtp:e2b-q4_k_m}"

export OLLAMA_HOST="0.0.0.0:11434"
export OLLAMA_ORIGINS="*"
export OLLAMA_CONTEXT_LENGTH="${OLLAMA_CONTEXT_LENGTH:-8192}"
export OLLAMA_KEEP_ALIVE="-1"

log() { echo "[ollama-setup] $*"; }

# 0. installer dependencies (the official installer needs zstd to unpack)
if ! command -v ollama >/dev/null 2>&1 && ! command -v zstd >/dev/null 2>&1; then
  log "installing zstd (required by the ollama installer)..."
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -qq >/dev/null 2>&1 || true
    sudo apt-get install -y -qq zstd >/dev/null 2>&1 || log "zstd install failed, trying anyway"
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y -q zstd >/dev/null 2>&1 || log "zstd install failed, trying anyway"
  fi
fi

# 1. binary
if ! command -v ollama >/dev/null 2>&1; then
  log "installing ollama..."
  if curl -fsSL https://ollama.com/install.sh -o /tmp/ollama-install.sh; then
    sh /tmp/ollama-install.sh >/tmp/ollama-install.log 2>&1 \
      || log "installer exited non-zero (normal in a systemd-less container)"
  else
    log "could not download the installer"
  fi
fi

if ! command -v ollama >/dev/null 2>&1; then
  log "FATAL: ollama binary still missing. See /tmp/ollama-install.log"
  if ! command -v zstd >/dev/null 2>&1; then
    log "hint: the installer needs zstd. Install it and re-run:"
    log "  sudo apt-get update && sudo apt-get install -y zstd"
  fi
  exit 1
fi

# 2. server
if ! pgrep -f "ollama serve" >/dev/null 2>&1; then
  log "starting ollama serve on 0.0.0.0:11434 (log: /tmp/ollama.log)"
  nohup ollama serve >/tmp/ollama.log 2>&1 &
fi

for _ in $(seq 1 60); do
  curl -sf http://127.0.0.1:11434/api/tags >/dev/null 2>&1 && break
  sleep 1
done

if ! curl -sf http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  log "FATAL: API did not come up. Check /tmp/ollama.log"
  exit 1
fi
log "api up"

# 3. serve the playground on port 8000 straight away (so the page is up even while the model downloads)
if command -v python3 >/dev/null 2>&1 && ! pgrep -f "http[.]server 8000" >/dev/null 2>&1; then
  ( cd "$(dirname "$0")/.." && nohup python3 -m http.server 8000 >/tmp/site.log 2>&1 & )
  log "playground served on port 8000 (log: /tmp/site.log)"
fi

# 4. model
REPO_PART="${MODEL%%:*}"
if ollama list 2>/dev/null | grep -q "$REPO_PART"; then
  log "$MODEL already pulled"
else
  log "pulling $MODEL (first run only, this takes a few minutes)"
  if ! ollama pull "$MODEL"; then
    log "FATAL: pull failed for $MODEL"
    exit 1
  fi
fi

echo
log "ready"
ollama list
echo
log "Open the playground on the forwarded port 8000 (Ports tab -> 8000 -> Open in Browser)."
log "It picks up this codespace's Ollama URL automatically. Manual base URL:"
if [ -n "${CODESPACE_NAME:-}" ]; then
  log "  https://${CODESPACE_NAME}-11434.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-app.github.dev}/v1"
  log "  https://${CODESPACE_NAME}-8000.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-app.github.dev}"
else
  log "  http://localhost:11434/v1   (or your forwarded https URL + /v1)"
fi
log "Model field: $MODEL"
