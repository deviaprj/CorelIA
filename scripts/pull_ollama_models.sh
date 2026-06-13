#!/bin/bash
# ============================================================================
# pull_ollama_models.sh — Télécharge les modèles légers dans Ollama
# ============================================================================
# Modèles sélectionnés pour CPU (pas besoin de GPU) :
#   - llama3.2:1b     (1.3 GB) — Meta, bon pour tâches générales
#   - qwen2.5:1.5b    (1.0 GB) — Alibaba, excellent en code
#   - gemma3:1b       (0.8 GB) — Google, rapide et efficace
#   - deepseek-r1:1.5b (1.1 GB) — DeepSeek, raisonnement
#   - phi4-mini:3.8b  (2.3 GB) — Microsoft, très bon rapport qualité/taille
#
# Total: ~6.5 GB — parfait pour 24 GB RAM
# ============================================================================

set -euo pipefail

OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:11434}"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $*"; }
info() { echo -e "${BLUE}[i]${NC} $*"; }

echo ""
echo "🤖 Pull des modèles Ollama..."
echo ""

# ── Via docker exec (si dans container) ──────────────────────────────────
if docker ps --format '{{.Names}}' | grep -q corelia-ollama; then
    OLLAMA_CMD="docker exec corelia-ollama ollama"
    info "Ollama détecté dans Docker → $OLLAMA_CMD"
else
    OLLAMA_CMD="ollama"
    info "Ollama local → $OLLAMA_CMD"
fi

# ── Modèles à puller ─────────────────────────────────────────────────────
MODELS=(
    "qwen2.5:1.5b"
    "llama3.2:1b"
    "gemma3:1b"
    "deepseek-r1:1.5b"
)

for model in "${MODELS[@]}"; do
    info "Pull $model..."
    if $OLLAMA_CMD pull "$model"; then
        log "$model ✓"
    else
        echo "   ⚠ Échec pour $model, on continue..."
    fi
done

echo ""
log "Modèles disponibles :"
$OLLAMA_CMD list
echo ""
echo "📊 Espace disque :"
df -h / | tail -1
