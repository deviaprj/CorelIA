#!/bin/bash
# deploy_backend.sh — Deploy AironBot backend to production
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKEND_DIR="$PROJECT_DIR/backend"

echo "🚀 Déploiement du backend AironBot"
echo "==================================="

# Configuration (override via env vars)
REMOTE_HOST="${REMOTE_HOST:-api.aironbot.app}"
REMOTE_USER="${REMOTE_USER:-root}"
DOCKER_IMAGE="${DOCKER_IMAGE:-aironbot-backend}"
DOCKER_TAG="${DOCKER_TAG:-latest}"

echo "📦 Build Docker image..."
cd "$BACKEND_DIR"
docker build -t "$DOCKER_IMAGE:$DOCKER_TAG" .

echo "🐳 Sauvegarde image..."
docker save "$DOCKER_IMAGE:$DOCKER_TAG" | gzip > /tmp/aironbot-backend.tar.gz

echo "📤 Transfert vers $REMOTE_HOST..."
scp /tmp/aironbot-backend.tar.gz "$REMOTE_USER@$REMOTE_HOST:/tmp/"
scp "$BACKEND_DIR/../.env" "$REMOTE_USER@$REMOTE_HOST:/opt/aironbot/.env"

echo "🔧 Déploiement sur le serveur..."
ssh "$REMOTE_USER@$REMOTE_HOST" '
  set -e
  cd /opt/aironbot
  docker load < /tmp/aironbot-backend.tar.gz
  docker compose down || true
  docker compose up -d
  docker system prune -f
'

echo "✅ Déploiement terminé !"
echo "🌐 URL : https://$REMOTE_HOST"
echo "📋 Health check : curl https://$REMOTE_HOST/health"
