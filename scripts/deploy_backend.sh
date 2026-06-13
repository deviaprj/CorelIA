#!/bin/bash
# ============================================================================
# deploy_backend.sh — Déploiement CorelIA vers Hetzner VPS
# ============================================================================
# Usage:
#   bash scripts/deploy_backend.sh [--full] [--agent] [--ollama]
#
#   --full    : Déploie toute la stack (backend + agent + ollama)
#   --agent   : Déploie seulement le CodeWhale Agent
#   --ollama  : Pull les modèles Ollama après déploiement
#   (sans flag): Déploie seulement le backend
#
# Prérequis :
#   - Clé SSH configurée : ~/.ssh/id_ed25519
#   - Serveur accessible : 167.233.100.132
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# ── Configuration ────────────────────────────────────────────────────────
REMOTE_HOST="${REMOTE_HOST:-167.233.100.132}"
REMOTE_USER="${REMOTE_USER:-corelia}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no"
REMOTE_DIR="/opt/corelia"

MODE="${1:-backend}"

# ── Couleurs ─────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
info() { echo -e "${BLUE}[i]${NC} $*"; }

# ── Vérification SSH ─────────────────────────────────────────────────────
echo "🔑 Vérification connexion SSH..."
if ! ssh $SSH_OPTS "$REMOTE_USER@$REMOTE_HOST" "echo OK" &>/dev/null; then
    echo "❌ Connexion SSH échouée vers $REMOTE_USER@$REMOTE_HOST"
    echo "   Vérifie : ssh $SSH_OPTS $REMOTE_USER@$REMOTE_HOST"
    exit 1
fi
log "SSH OK → $REMOTE_USER@$REMOTE_HOST"

# ── Gestion des secrets (.env) ───────────────────────────────────────────
info "Vérification des variables d'environnement..."
# Construire la liste des vars requises
REQUIRED_ENV_VARS=(
    "DEEPSEEK_API_KEY"
    "OPENROUTER_API_KEY"
)

MISSING_VARS=()
for var in "${REQUIRED_ENV_VARS[@]}"; do
    if [ -z "${!var:-}" ]; then
        MISSING_VARS+=("$var")
    fi
done

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
    # Essayer de charger depuis .env local
    if [ -f "$PROJECT_DIR/.env" ]; then
        info "Chargement depuis .env local..."
        set -a
        source "$PROJECT_DIR/.env"
        set +a
        # Revérifier
        MISSING_VARS=()
        for var in "${REQUIRED_ENV_VARS[@]}"; do
            if [ -z "${!var:-}" ]; then
                MISSING_VARS+=("$var")
            fi
        done
    fi

    if [ ${#MISSING_VARS[@]} -gt 0 ]; then
        warn "Variables manquantes : ${MISSING_VARS[*]}"
        warn "Le déploiement continue mais certains services seront dégradés."
        warn "Définis-les via export ou .env avant de relancer."
    fi
fi

# Générer le .env pour le serveur (ne jamais exposer les valeurs dans les logs)
if [ -f "$PROJECT_DIR/.env" ]; then
    info "Transfert du .env vers le serveur..."
    scp $SSH_OPTS "$PROJECT_DIR/.env" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/.env"
    log ".env transféré avec succès."
else
    warn "Aucun fichier .env local trouvé. Les services utiliseront leurs vars d'env."
fi

# ── Sync du code ─────────────────────────────────────────────────────────
info "Synchronisation du code vers $REMOTE_DIR..."
rsync -avz --delete \
    --exclude='.git' \
    --exclude='build' \
    --exclude='.dart_tool' \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    --exclude='.flutter-plugins*' \
    --exclude='android/' \
    --exclude='ios/' \
    --exclude='linux/' \
    --exclude='node_modules' \
    -e "ssh $SSH_OPTS" \
    "$PROJECT_DIR/" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/"
log "Code synchronisé."

# ── Déploiement ──────────────────────────────────────────────────────────
case "$MODE" in
    --full)
        info "Déploiement COMPLET (toute la stack)..."
        ssh $SSH_OPTS "$REMOTE_USER@$REMOTE_HOST" "
            cd $REMOTE_DIR
            docker compose pull
            docker compose build backend codewhale-agent
            docker compose up -d --remove-orphans
            echo '✅ Stack complète déployée.'
            docker compose ps
        "
        ;;
    --agent)
        info "Déploiement CodeWhale Agent uniquement..."
        ssh $SSH_OPTS "$REMOTE_USER@$REMOTE_HOST" "
            cd $REMOTE_DIR
            docker compose build codewhale-agent
            docker compose up -d --remove-orphans codewhale-agent
            echo '✅ Agent déployé.'
        "
        ;;
    --ollama)
        info "Pull des modèles Ollama..."
        ssh $SSH_OPTS "$REMOTE_USER@$REMOTE_HOST" "
            cd $REMOTE_DIR
            bash scripts/pull_ollama_models.sh
        "
        ;;
    *)
        info "Déploiement backend..."
        ssh $SSH_OPTS "$REMOTE_USER@$REMOTE_HOST" "
            cd $REMOTE_DIR
            docker compose build backend
            docker compose up -d --remove-orphans backend
            echo '✅ Backend déployé.'
        "
        ;;
esac

echo ""
echo "🌐 URLs :"
echo "   Backend : https://api.zentic.fr/health"
echo "   Agent   : https://agent.zentic.fr/health"
echo "   Ollama  : http://$REMOTE_HOST:11434"
