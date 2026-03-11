#!/bin/bash

# Script ultra-simplifié pour Claude Code avec Kimi K2.5 Cloud
# Version qui ignore le menu de configuration

set -e

IMAGE_NAME="claude-code-kimi-simple"

# Dockerfile minimal
cat > Dockerfile.simple <<'EOF'
FROM node:20-slim

RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
RUN npm install -g @anthropic-ai/claude-code

WORKDIR /workspace

COPY run.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/run.sh

CMD ["/usr/local/bin/run.sh"]
EOF

# Script de lancement qui force la config
cat > run.sh <<'EOF'
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
EOF

chmod +x run.sh

# Construction
echo "🏗️  Construction de l'image..."
docker build -t $IMAGE_NAME -f Dockerfile.simple .

# Lancement
echo "🚀 Lancement..."
docker run -it --rm \
    -v $(pwd):/workspace \
    -e OLLAMA_API_KEY="$OLLAMA_API_KEY" \
    $IMAGE_NAME

# Nettoyage
rm -f Dockerfile.simple run.sh