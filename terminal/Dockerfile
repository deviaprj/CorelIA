# ============================================================================
# Terminal Web CorelIA — ttyd + Claude Code + Codewhale + tmux
# ============================================================================
# Image personnalisée avec tous les outils de développement pré-installés.
# Les configs utilisateur (SSH, git, Claude) sont montées par volumes.
# ============================================================================

FROM tsl0922/ttyd:latest AS base

# ── Installation des dépendances système ─────────────────────────────────
RUN apt-get update -qq && apt-get install -y -qq \
    curl \
    git \
    tmux \
    ca-certificates \
    gnupg \
    && rm -rf /var/lib/apt/lists/*

# ── Node.js 22 LTS ───────────────────────────────────────────────────────
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y -qq nodejs \
    && rm -rf /var/lib/apt/lists/*

# ── Création du user corelia (UID libre) ─────────────────────────────────
RUN groupadd corelia \
    && useradd -m -g corelia -s /bin/bash -d /home/corelia corelia \
    && echo "corelia:corelia" | chpasswd \
    && mkdir -p /home/corelia/.ssh /home/corelia/.claude \
    && chown -R corelia:corelia /home/corelia

# ── Installation des outils globaux (Claude Code + Codewhale) ────────────
RUN npm install -g @anthropic-ai/claude-code codewhale \
    && chmod -R a+r /usr/lib/node_modules/

# ── Bash config pour corelia ─────────────────────────────────────────────
COPY --chown=corelia:corelia bashrc.corelia /home/corelia/.bashrc

# ── Entrypoint ───────────────────────────────────────────────────────────
# On garde ttyd comme binaire principal avec l'option -W (writable)
# pour permettre les modifications de fichiers
ENV TTYD_USER=corelia
ENV TTYD_PASS=changeme

# Utilisation d'un script shell pour interpolation des variables d'environnement
COPY start-ttyd.sh /app/start-ttyd.sh
RUN chmod +x /app/start-ttyd.sh

ENTRYPOINT ["/app/start-ttyd.sh"]