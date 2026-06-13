#!/bin/bash
# ============================================================================
# CorelIA Cloud — Installation outils IA additionnels
# ============================================================================
# Ce script AJOUTE des outils au VPS existant (ne réinstalle pas Docker)
# - CodeWhale CLI (npm)       → agent en ligne de commande
# - Claude Code (Anthropic)   → compatible API OpenRouter/Ollama
# - Codex CLI (OpenAI)        → compatible API DeepSeek
# - Outils dev (Node, Python, pnpm, uv)
# - Penpot (design collaboratif)
# ============================================================================
# Usage: ssh root@167.233.100.132 "bash -s" < scripts/install_ai_tools.sh
# ============================================================================

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
info() { echo -e "${BLUE}[i]${NC} $*"; }

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     CorelIA Cloud — Outils IA additionnels                   ║"
echo "╚══════════════════════════════════════════════════════════════╝"

# ── 1. Node.js LTS ───────────────────────────────────────────────────────
if ! command -v node &>/dev/null; then
    log "Installation Node.js 22 LTS..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    apt-get install -y nodejs
    log "Node.js $(node --version)"
else
    log "Node.js déjà installé ($(node --version))"
fi

# ── 2. Python + pip ─────────────────────────────────────────────────────
log "Vérification Python..."
apt-get install -y python3 python3-pip python3-venv python3-dev -qq
log "Python $(python3 --version)"

# ── 3. pnpm ─────────────────────────────────────────────────────────────
if ! command -v pnpm &>/dev/null; then
    npm install -g pnpm
    log "pnpm installé"
fi

# ── 4. uv (Python package manager) ──────────────────────────────────────
if ! command -v uv &>/dev/null; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.cargo/bin:$PATH"
    log "uv installé"
fi

# ── 5. CodeWhale CLI ────────────────────────────────────────────────────
log "Installation CodeWhale CLI..."
npm install -g codewhale 2>/dev/null || warn "CodeWhale CLI non trouvé sur npm — skip"
command -v codewhale && log "CodeWhale CLI: $(codewhale --version 2>/dev/null || echo 'ok')" || true

# ── 6. Claude Code ──────────────────────────────────────────────────────
log "Installation Claude Code..."
npm install -g @anthropic-ai/claude-code 2>/dev/null || warn "Claude Code non trouvé sur npm — skip"
command -v claude && log "Claude Code installé" || true

# ── 7. Codex CLI ────────────────────────────────────────────────────────
log "Installation Codex CLI..."
npm install -g @openai/codex-cli 2>/dev/null || warn "Codex CLI non trouvé sur npm — skip"
command -v codex && log "Codex CLI installé" || true

# ── 8. Outils dev ───────────────────────────────────────────────────────
log "Installation outils de développement..."
npm install -g typescript eslint prettier nodemon pm2 2>/dev/null || true

# ── 9. Configuration API ────────────────────────────────────────────────
log "Configuration des variables d'environnement API..."
cat > /root/.ai-env << 'EOF'
# ── DeepSeek API (utilisé par CodeWhale, CorelIA, Codex compatible) ──
export DEEPSEEK_API_KEY="${DEEPSEEK_API_KEY:-sk-your-deepseek-key-here}"
export OPENAI_API_KEY="${DEEPSEEK_API_KEY:-sk-your-deepseek-key-here}"
export OPENAI_BASE_URL="https://api.deepseek.com/v1"

# ── OpenRouter API (utilisé par Claude Code, CorelIA Pro) ──
export OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-sk-or-v1-your-openrouter-key-here}"

# ── Ollama local ──
export OLLAMA_HOST="http://localhost:11434"
EOF
grep -q "ai-env" /root/.bashrc || echo "source /root/.ai-env" >> /root/.bashrc
source /root/.ai-env
log "Variables d'environnement configurées"

# ── 10. GitHub CLI ──────────────────────────────────────────────────────
if ! command -v gh &>/dev/null; then
    log "Installation GitHub CLI..."
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    apt-get update -qq && apt-get install -y gh
    log "GitHub CLI installé"
fi

# ── 11. Penpot (Design tool) ────────────────────────────────────────────
log "Configuration Penpot..."
mkdir -p /opt/penpot
cat > /opt/penpot/docker-compose.yaml << 'PENPOT'
version: "3.5"
services:
  penpot-frontend:
    image: penpotapp/frontend:latest
    ports:
      - "8080:80"
    restart: unless-stopped
  penpot-backend:
    image: penpotapp/backend:latest
    restart: unless-stopped
    environment:
      PENPOT_FLAGS: enable-registration
  penpot-exporter:
    image: penpotapp/exporter:latest
    restart: unless-stopped
PENPOT
log "Penpot configuré dans /opt/penpot/"

# ── 12. Script de diagnostic ─────────────────────────────────────────────
cat > /root/doctor.sh << 'DOC'
#!/bin/bash
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              CorelIA Cloud — Diagnostic                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "🐳 Docker:      $(docker --version 2>/dev/null || echo '❌')"
echo "📦 Compose:     $(docker compose version 2>/dev/null || echo '❌')"
echo "🟢 Node.js:     $(node --version 2>/dev/null || echo '❌')"
echo "🐍 Python:      $(python3 --version 2>/dev/null || echo '❌')"
echo "📦 pnpm:        $(pnpm --version 2>/dev/null || echo '❌')"
echo ""
echo "🤖 Agents IA:"
echo "  • CodeWhale CLI:  $(command -v codewhale >/dev/null && echo '✅' || echo '❌')"
echo "  • Claude Code:    $(command -v claude >/dev/null && echo '✅' || echo '❌')"
echo "  • Codex:          $(command -v codex >/dev/null && echo '✅' || echo '❌')"
echo ""
echo "🌐 Services CorelIA:"
docker compose -f /root/corelia/docker-compose.yml ps 2>/dev/null || echo "  (stack non démarrée)"
echo ""
echo "📊 Disques:"
df -h / /opt 2>/dev/null
echo ""
echo "🔑 API configurées:"
echo "  • DEEPSEEK_API_KEY:    ${DEEPSEEK_API_KEY:0:10}..."
echo "  • OPENROUTER_API_KEY:  ${OPENROUTER_API_KEY:0:10}..."
DOC
chmod +x /root/doctor.sh
log "Script diagnostic créé: /root/doctor.sh"

# ── Résumé ───────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           ✅ OUTILS INSTALLÉS                                ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  CodeWhale CLI    → codewhale                               ║"
echo "║  Claude Code      → claude                                  ║"
echo "║  Codex CLI        → codex                                   ║"
echo "║  Node.js + pnpm   → node, pnpm                              ║"
echo "║  Python + uv      → python3, uv                             ║"
echo "║  Penpot           → /opt/penpot (port 8080)                 ║"
echo "║  GitHub CLI       → gh                                      ║"
echo "║                                                              ║"
echo "║  Diagnostic       → /root/doctor.sh                         ║"
echo "║  API config       → /root/.ai-env                           ║"
echo "╚══════════════════════════════════════════════════════════════╝"
