#!/bin/bash
# ============================================================================
# CorelIA Cloud — Setup script pour VPS Hetzner existant
# ============================================================================
# Usage:
#   Depuis ta machine locale :
#     ssh -i ~/.ssh/id_ed25519_hetzner corelia@167.233.100.132
#   Puis sur le serveur :
#     bash <(curl -s https://raw.githubusercontent.com/zentic/CorelIA/main/scripts/server_init.sh)
#
#   OU copie ce script sur le serveur :
#     scp -i ~/.ssh/id_ed25519_hetzner scripts/server_init.sh corelia@167.233.100.132:/tmp/
#     ssh -i ~/.ssh/id_ed25519_hetzner corelia@167.233.100.132 "bash /tmp/server_init.sh"
# ============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*"; }
info() { echo -e "${BLUE}[i]${NC} $*"; }

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       CorelIA Cloud — Installation VPS Hetzner               ║"
echo "║       Serveur: 167.233.100.132 | 24 GB RAM                   ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ── Check root ───────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
   err "Ce script doit être exécuté en root (sudo)."
   exit 1
fi

# ── 1. System Update ─────────────────────────────────────────────────────
log "Mise à jour du système..."
apt-get update -qq && apt-get upgrade -y -qq
log "Système à jour."

# ── 2. Install Docker ────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
    log "Installation Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    log "Docker installé."
else
    log "Docker déjà installé ($(docker --version))."
fi

# ── 3. Install Docker Compose plugin ─────────────────────────────────────
if ! docker compose version &>/dev/null; then
    log "Installation Docker Compose plugin..."
    apt-get install -y docker-compose-plugin
    log "Docker Compose installé."
else
    log "Docker Compose déjà présent ($(docker compose version))."
fi

# ── 4. Create corelia user (if not exists) ───────────────────────────────
if ! id -u corelia &>/dev/null; then
    log "Création utilisateur corelia..."
    useradd -m -s /bin/bash -G docker,sudo corelia
    echo "corelia ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/corelia
    mkdir -p /home/corelia/.ssh
    chmod 700 /home/corelia/.ssh
    chown -R corelia:corelia /home/corelia/.ssh
    log "Utilisateur corelia créé."
else
    log "Utilisateur corelia existe déjà."
    usermod -aG docker corelia 2>/dev/null || true
fi

# ── 5. Configure Firewall ────────────────────────────────────────────────
log "Configuration firewall..."
ufw --force reset > /dev/null 2>&1 || true
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'
echo "y" | ufw enable
log "Firewall configuré (SSH, HTTP, HTTPS)."

# ── 6. Setup fail2ban ────────────────────────────────────────────────────
log "Configuration fail2ban..."
apt-get install -y -qq fail2ban
cat > /etc/fail2ban/jail.local << 'EOF'
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
findtime = 600
EOF
systemctl enable fail2ban
systemctl restart fail2ban
log "fail2ban configuré."

# ── 7. Setup swap (4GB) ──────────────────────────────────────────────────
if ! swapon --show | grep -q swapfile; then
    log "Création swap 4GB..."
    fallocate -l 4G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    log "Swap créé."
else
    log "Swap déjà présent."
fi

# ── 8. Clone/Pull CorelIA repo ───────────────────────────────────────────
REPO_DIR="/opt/corelia"
if [[ -d "$REPO_DIR/.git" ]]; then
    log "Mise à jour du repo CorelIA..."
    cd "$REPO_DIR"
    git pull origin main || git pull origin master || true
else
    log "Clone du repo CorelIA..."
    mkdir -p /opt
    # Essaie plusieurs URLs
    git clone https://github.com/zentic/CorelIA.git "$REPO_DIR" 2>/dev/null || \
    git clone git@github.com:zentic/CorelIA.git "$REPO_DIR" 2>/dev/null || \
    warn "Impossible de cloner le repo. Clone-le manuellement dans /opt/corelia"
fi
chown -R corelia:corelia "$REPO_DIR" 2>/dev/null || true

# ── 9. Create .env from template ─────────────────────────────────────────
if [[ ! -f "$REPO_DIR/.env" ]]; then
    log "Création .env template..."
    cat > "$REPO_DIR/.env" << 'ENVEOF'
# CorelIA Production Environment
APP_ENV=production
DEBUG=false

# AI Providers (À REMPLIR avec tes vraies clés !)
DEEPSEEK_API_KEY=sk-your-deepseek-key-here
OPENROUTER_API_KEY=sk-or-v1-your-openrouter-key-here

# Backend
BACKEND_URL=https://api.zentic.fr
API_SECRET_KEY=311788a14ea7b929c5280f074a8b33ecafe361de59e3ab673c5194d9516470ea
REDIS_URL=redis://redis:6379/0
RATE_LIMIT=100/minute
CORS_ORIGINS=https://zentic.fr,https://api.zentic.fr,chrome-extension://*

# Cloudflare Tunnel (optionnel)
CF_TUNNEL_TOKEN=

# HuggingFace (pour Unsloth)
HF_TOKEN=

# WebUI
WEBUI_SECRET_KEY=change-me-to-a-random-string
ENVEOF
    warn ".env créé avec des valeurs par défaut — VÉRIFIE les clés API !"
else
    log ".env existe déjà."
fi

# ── 10. Docker daemon config ─────────────────────────────────────────────
log "Configuration Docker..."
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "metrics-addr": "127.0.0.1:9323",
  "experimental": false
}
EOF
systemctl restart docker

# ── 11. Pull Ollama models (légers, optimisés CPU) ───────────────────────
log "Pull des modèles Ollama légers..."
if docker ps --format '{{.Names}}' | grep -q corelia-ollama; then
    info "Ollama déjà en cours d'exécution, pull des modèles..."
    docker exec corelia-ollama ollama pull llama3.2:1b &
    docker exec corelia-ollama ollama pull qwen2.5:0.5b &
    docker exec corelia-ollama ollama pull gemma3:1b &
    wait
    log "Modèles Ollama pullés."
else
    info "Ollama pas encore lancé — les modèles seront pullés au premier docker compose up"
fi

# ── 12. Start CorelIA stack ──────────────────────────────────────────────
log "Démarrage de la stack CorelIA..."
cd "$REPO_DIR"

# Pull images first
docker compose pull 2>/dev/null || true

# Start core services
docker compose up -d redis traefik backend ollama codewhale-agent 2>&1 | tail -5

# ── 13. systemd service for auto-start ───────────────────────────────────
log "Création service systemd..."
cat > /etc/systemd/system/corelia.service << 'EOF'
[Unit]
Description=CorelIA Docker Stack
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/corelia
ExecStart=/usr/bin/docker compose up -d --remove-orphans
ExecStop=/usr/bin/docker compose down
ExecReload=/usr/bin/docker compose up -d --remove-orphans
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable corelia.service

# ── 14. MOTD ─────────────────────────────────────────────────────────────
cat > /etc/motd << 'MOTD'

╔══════════════════════════════════════════════════════════════╗
║           CorelIA Cloud — api.zentic.fr                      ║
╠══════════════════════════════════════════════════════════════╣
║  Serveur : 167.233.100.132 | 24 GB RAM | Falkenstein        ║
║  Services :                                                  ║
║    Backend      → https://api.zentic.fr                      ║
║    Agent        → https://agent.zentic.fr                    ║
║    Ollama       → http://localhost:11434                     ║
║    Open WebUI   → https://chat.zentic.fr                     ║
║                                                              ║
║  Commandes utiles :                                          ║
║    docker compose -f /opt/corelia/docker-compose.yml ps      ║
║    docker compose -f /opt/corelia/docker-compose.yml logs -f ║
║    systemctl status corelia                                  ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝

MOTD

# ── 15. Résumé ───────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           ✅ INSTALLATION TERMINÉE                           ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║                                                              ║"
echo "║  Services démarrés : redis, traefik, backend, ollama, agent  ║"
echo "║                                                              ║"
echo "║  Vérification :                                              ║"
echo "║    docker compose -f /opt/corelia/docker-compose.yml ps      ║"
echo "║    curl http://localhost:8000/health                         ║"
echo "║    curl http://localhost:8001/health                         ║"
echo "║                                                              ║"
echo "║  ⚠  PENSE À configurer le DNS :                             ║"
echo "║    api.zentic.fr     → 167.233.100.132                       ║"
echo "║    agent.zentic.fr   → 167.233.100.132                       ║"
echo "║    chat.zentic.fr    → 167.233.100.132                       ║"
echo "║    ollama.zentic.fr  → 167.233.100.132                       ║"
echo "║                                                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
