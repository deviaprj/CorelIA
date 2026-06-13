# Déploiement CorelIA — Guide Ops

> Date : 2026-06-13  
> Cible : Hetzner VPS `167.233.100.132` (`corelia` user)  
> Stack : Caddy (TLS) + Backend FastAPI + CodeWhale Agent + Redis + Ollama (optionnel) + ttyd

---

## ✅ Prérequis (vérifiés)

| Prérequis | Statut |
|-----------|--------|
| Clé SSH `~/.ssh/id_ed25519_hetzner` | ✅ Existe (`corelia@zentic.fr`) |
| Fichier `.env` complet | ✅ Mis à jour (CORS, RATE_LIMIT, WEBUI_SECRET_KEY) |
| `docker-compose.yml` syntaxe valide | ✅ 10 services reconnus |
| `scripts/deploy_backend.sh` | ✅ Exécutable |
| `backend/Dockerfile` + `codewhale-agent/Dockerfile` | ✅ Prêts |

---

## 🚀 Commande de déploiement

Exécute cette commande **depuis ta machine locale** (pas depuis le VPS) :

```bash
bash scripts/deploy_backend.sh --full
```

**Ce que ça fait :**
1. Vérifie la connexion SSH vers `corelia@167.233.100.132`
2. Synchronise le code via `rsync` (exclut `.git/`, `build/`, `android/`, `ios/`, etc.)
3. Transfère le `.env`
4. Build les images Docker (`backend`, `codewhale-agent`)
5. Démarre toute la stack (`docker compose up -d`)

---

## 🔧 Pré-requis DNS (action manuelle Cloudflare)

Avant que les URLs fonctionnent, ajoute ces records **A** dans ton dashboard Cloudflare :

| Sous-domaine | IP cible | Proxy Cloudflare | Commentaire |
|--------------|----------|------------------|-------------|
| `api.zentic.fr` | `167.233.100.132` | 🟠 OFF (WebSocket SSE) | Backend FastAPI |
| `agent.zentic.fr` | `167.233.100.132` | 🟠 OFF (WebSocket SSE) | CodeWhale Agent |
| `chat.zentic.fr` | `167.233.100.132` | 🟢 ON | Open WebUI (facultatif) |
| `terminal.zentic.fr` | `167.233.100.132` | 🟠 OFF (WebSocket) | ttyd |

> **Pourquoi OFF pour api/agent/terminal ?**  
> Cloudflare proxy interrompt les streams SSE et les WebSockets. Caddy gère déjà le TLS via Let's Encrypt.

---

## 🧪 Validation post-déploiement

Après le déploiement, exécute ces commandes **sur le VPS** pour vérifier :

```bash
ssh corelia@167.233.100.132
cd /opt/corelia

# 1. Vérifier que tous les conteneurs tournent
docker compose ps

# 2. Healthcheck backend
curl -s http://localhost:8000/health | python3 -m json.tool

# 3. Healthcheck CodeWhale Agent
curl -s http://localhost:8001/health | python3 -m json.tool

# 4. Redis
docker compose exec redis redis-cli ping

# 5. Logs backend (en cas d'erreur)
docker compose logs --tail=50 backend

# 6. Test endpoint search
curl -s "http://localhost:8000/search?q=test" | python3 -m json.tool

# 7. Test endpoint scrape
curl -s "http://localhost:8000/scrape?url=https://example.com" | python3 -m json.tool
```

---

## 🆘 Troubleshooting

### "Connexion SSH échouée"
```bash
# Vérifier la clé
ssh -i ~/.ssh/id_ed25519_hetzner -o StrictHostKeyChecking=no corelia@167.233.100.132 "echo OK"
# Si KO → vérifier que la clé publique est dans ~/.ssh/authorized_keys sur le VPS
```

### "Backend unhealthy"
```bash
# Vérifier les logs
docker compose logs backend --tail=100

# Causes fréquentes :
# - Redis non démarré (backend dépend de redis healthy)
# - .env mal transféré (vérifie : cat /opt/corelia/.env)
# - Port 8000 déjà utilisé (vérifie : docker compose ps)
```

### "Caddy ne sert pas les sous-domaines"
```bash
# Vérifier que Caddy a bien rechargé sa config
docker compose logs caddy --tail=50

# Vérifier les certificats Let's Encrypt (peut prendre 30-60s au premier démarrage)
docker compose exec caddy cat /data/caddy/certificates/local/...
```

---

## 📋 Checklist finale

- [ ] `bash scripts/deploy_backend.sh --full` exécuté depuis la machine locale
- [ ] Records DNS Cloudflare ajoutés (api, agent, chat, terminal)
- [ ] `https://api.zentic.fr/health` répond `{"status": "ok"}`
- [ ] `https://agent.zentic.fr/health` répond `{"status": "ok"}`
- [ ] Redis répond `PONG`
- [ ] Logs backend sans erreur critique

---

*Généré le 2026-06-13 — session de déploiement CorelIA*
