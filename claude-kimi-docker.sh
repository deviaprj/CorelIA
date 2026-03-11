#!/bin/bash

# Script Docker pour Claude Code avec Kimi K2.5 Cloud
# Version corrigée avec installation npm

set -e

MODEL_NAME="kimi-k2.5:cloud"
IMAGE_NAME="claude-code-kimi"

echo "🚀 Préparation de Claude Code avec $MODEL_NAME"
echo ""

# Création du Dockerfile corrigé
cat > Dockerfile.claude <<'EOF'
FROM node:20-slim

# Installation des dépendances système
RUN apt-get update && apt-get install -y \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*

# Installation de Claude Code via npm (MÉTHODE CORRIGÉE)
RUN npm install -g @anthropic-ai/claude-code

# Vérification que claude est bien installé
RUN which claude || (echo "❌ Échec installation claude" && exit 1)

# Répertoire de travail
WORKDIR /workspace

# Script d'entrée
COPY entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
EOF

# Création du script d'entrée
cat > entrypoint.sh <<'EOF'
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
EOF

chmod +x entrypoint.sh

# Nettoyage de l'ancienne image si elle existe
echo "🧹 Nettoyage de l'ancienne image..."
docker rmi $IMAGE_NAME 2>/dev/null || true

# Construction de la nouvelle image
echo "🏗️  Construction de la nouvelle image Docker..."
docker build -t $IMAGE_NAME -f Dockerfile.claude .

# Lancement du conteneur
echo "🚀 Lancement de Claude Code..."
echo "📁 Dossier monté: $(pwd)"
echo ""

docker run -it --rm \
    -v $(pwd):/workspace \
    -e OLLAMA_API_KEY="$OLLAMA_API_KEY" \
    --name "claude-$(date +%s)" \
    $IMAGE_NAME

# Nettoyage des fichiers temporaires
echo "🧹 Nettoyage des fichiers temporaires..."
rm -f Dockerfile.claude entrypoint.sh
echo "✅ Terminé"