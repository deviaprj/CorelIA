#!/bin/bash

# Configuration pour Ollama Cloud
export ANTHROPIC_BASE_URL="https://api.ollama.com/v1"
export ANTHROPIC_AUTH_TOKEN="$OLLAMA_API_KEY"
export ANTHROPIC_API_KEY=""
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1

echo "╔════════════════════════════════════════════════════════╗"
echo "║         Claude Code avec Kimi K2.5 Cloud               ║"
echo "╚════════════════════════════════════════════════════════╝"
echo "📁 Dossier de travail: /workspace"
echo "🔗 API Ollama: $ANTHROPIC_BASE_URL"
echo "🤖 Modèle: kimi-k2.5:cloud"
echo "🔑 Token: ${OLLAMA_API_KEY:0:10}... (configuré)"
echo ""

# Lancement de Claude
exec claude --model kimi-k2.5:cloud "$@"
