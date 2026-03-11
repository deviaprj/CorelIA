#!/bin/bash

# Forcer les variables d'environnement
export ANTHROPIC_BASE_URL="https://api.ollama.com/v1"
export ANTHROPIC_AUTH_TOKEN="$OLLAMA_API_KEY"
export ANTHROPIC_API_KEY=""
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export CLAUDE_CODE_USE_BEDROCK="false"
export CLAUDE_CODE_USE_VERTEX="false"

# Créer un fichier de config factice pour éviter le menu
mkdir -p /root/.config/claude-code
cat > /root/.config/claude-code/config.json <<CONFIG
{
  "provider": "custom",
  "apiUrl": "https://api.ollama.com/v1",
  "model": "kimi-k2.5:cloud",
  "disableTelemetry": true
}
CONFIG

echo "========================================="
echo "Claude Code avec Kimi K2.5 Cloud (Ollama)"
echo "========================================="
echo "API URL: $ANTHROPIC_BASE_URL"
echo "Modèle: kimi-k2.5:cloud"
echo "Token: ${OLLAMA_API_KEY:0:10}..."
echo ""

# Lancer Claude sans passer par le menu
exec claude --model kimi-k2.5:cloud --dangerously-skip-permissions --non-interactive "$@"
