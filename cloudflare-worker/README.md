# AironBot Cloudflare Worker — API REST

Backend sécurisé du chatbot AironBot, déployé sur Cloudflare Workers.
Route tout le trafic IA via un proxy unique avec rate limiting, sanitization et fallback automatique.

## Architecture

```
Client Flutter / Extension Chrome
        │
        │  POST /chat     (SSE streaming, auth Bearer)
        │  GET  /search    (DuckDuckGo)
        │  GET  /scrape    (HTMLRewriter)
        │  GET  /health    (health check)
        ▼
┌──────────────────────────────┐
│   Cloudflare Worker          │
│   api.aironbot.app           │
│                              │
│  ┌────────────────────────┐  │
│  │ Rate Limiting          │  │  100 req/min/IP (/chat)
│  │ Input Sanitization     │  │  30 req/min/IP  (/scrape)
│  │ Prompt Injection       │  │
│  │ XSS Protection         │  │
│  └────────────────────────┘  │
│                              │
│  ┌────────────────────────┐  │
│  │ LLM Proxy              │  │
│  │ 1. Workers AI (free)   │  │  @cf/meta/llama-3-8b-instruct
│  │ 2. DeepSeek V4 Flash   │  │  deepseek-v4-flash
│  │ 3. OpenRouter          │  │  Fallback ultime
│  └────────────────────────┘  │
└──────────────────────────────┘
```

## Sécurité

| Protection | Implémentation |
|-----------|---------------|
| Rate limiting | 100 req/min/IP sur `/chat` (Cloudflare WAF + in-code fallback) |
| Prompt injection | Détection OWASP LLM Top 10 (jailbreak, role-play, token smuggling) |
| XSS | Échappement HTML de toutes les sorties utilisateur |
| API auth | Vérification par clé secrète en temps constant (Bearer token) |
| CORS | Restreint aux origines connues (extension Chrome, domaine principal) |
| SSL/TLS | Mode "Complet (strict)" activé automatiquement par Cloudflare |

## Endpoints

| Méthode | Route | Description | Auth |
|---------|-------|-------------|------|
| `GET` | `/health` | Health check | Non |
| `POST` | `/chat` | Chat streaming (SSE) | Oui (`Bearer <API_SECRET_KEY>`) |
| `GET` | `/search?q=...` | Recherche DuckDuckGo | Non |
| `GET` | `/scrape?url=...&selectors=...` | Extraction contenu web | Non |
| `GET` | `/search_smart?q=...` | Recherche unifiée (compat Flutter) | Non |

### POST /chat

```bash
curl -X POST https://api.aironbot.app/chat \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_SECRET_KEY" \
  -H "Accept: text/event-stream" \
  -d '{
    "messages": [{"role": "user", "content": "Bonjour !"}],
    "stream": true,
    "temperature": 0.7,
    "max_tokens": 4096
  }'
```

Réponse SSE :
```
data: {"content": "Bonjour"}
data: {"content": " !"}
data: {"content": " Comment"}
data: {"content": " puis"}
data: {"content": "-je"}
data: {"content": " vous"}
data: {"content": " aider"}
data: {"content": " ?"}
data: [DONE]
```

## Développement local

### Prérequis

- Node.js 20+
- Compte Cloudflare avec Workers activé
- Wrangler CLI : `npm install -g wrangler`

### Installation

```bash
cd cloudflare-worker
npm install
```

### Démarrer en local

```bash
# Lancer le worker (port 8787 par défaut)
npm run dev

# Lancer avec l'environnement staging
npm run dev:staging
```

### Définir les secrets

```bash
# Déployer les clés API comme secrets Cloudflare
npx wrangler secret put DEEPSEEK_API_KEY
# → coller: sk-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

npx wrangler secret put OPENROUTER_API_KEY
# → coller: sk-or-xxxxxxxxxxxxxxxxxxxxxxxxxx

npx wrangler secret put API_SECRET_KEY
# → coller: une valeur aléatoire forte (openssl rand -hex 32)
```

Pour l'environnement staging :
```bash
npx wrangler secret put DEEPSEEK_API_KEY --env staging
npx wrangler secret put OPENROUTER_API_KEY --env staging
npx wrangler secret put API_SECRET_KEY --env staging
```

### Vérifier les logs

```bash
npm run tail
```

## Déploiement

### Manuel

```bash
# Déployer en production
npm run deploy

# Déployer en staging
npm run deploy:staging
```

### Automatique (CI/CD)

Le workflow GitHub Actions `.github/workflows/deploy-worker.yml` déploie automatiquement :
- À chaque push sur `main`
- Manuellement via `workflow_dispatch`

**Secrets GitHub requis :**
- `CLOUDFLARE_API_TOKEN` — Token API Cloudflare avec permissions Workers
- `CLOUDFLARE_ACCOUNT_ID` — ID du compte Cloudflare
- `CF_ZONE_ID` — ID de la zone DNS `aironbot.app`

### Après le premier déploiement

1. Vérifier que le Worker répond : `curl https://api.aironbot.app/health`
2. Configurer le DNS : ajouter un enregistrement CNAME `api.aironbot.app` → Worker
3. Activer SSL/TLS "Complet (strict)" dans le dashboard Cloudflare
4. Configurer le client Flutter avec les mêmes `BACKEND_URL` et `API_SECRET_KEY`

## Intégration avec le client Flutter

### Flux de données

```
Flutter App (.env)
  ├── BACKEND_URL=https://api.aironbot.app
  ├── API_SECRET_KEY=<même valeur que dans le Worker>
  └── DEEPSEEK_API_KEY / OPENROUTER_API_KEY (fallback dev uniquement)

Flutter App → POST /chat (Bearer API_SECRET_KEY) → Worker → LLM
Flutter App → GET  /search?q=...                    → Worker → DuckDuckGo
Flutter App → GET  /scrape?url=...                  → Worker → HTMLRewriter
```

### Mode développement local (sans Worker)

Si vous commentez `BACKEND_URL` et `API_SECRET_KEY` dans `.env`, le client Flutter
utilisera automatiquement le fallback direct vers DeepSeek/OpenRouter avec les
clés API embarquées. Ce mode est utile pour le développement local mais ne doit
**jamais** être utilisé en production.

### Variables d'environnement Flutter

```bash
flutter build apk --release \
  --dart-define=BACKEND_URL=https://api.aironbot.app \
  --dart-define=API_SECRET_KEY=... \
  --dart-define=DEEPSEEK_API_KEY=... \
  --dart-define=OPENROUTER_API_KEY=...
```

## Limites du Worker vs Backend Python

| Fonctionnalité | Cloudflare Worker | Backend Python |
|----------------|-------------------|----------------|
| Chat SSE streaming | ✅ | ✅ |
| Scraping HTML | ✅ (HTMLRewriter) | ✅ (BeautifulSoup) |
| Recherche DuckDuckGo | ✅ | ✅ |
| Rate limiting | ✅ (built-in WAF) | ✅ (Redis+slowapi) |
| Extraction média (yt-dlp) | ❌ | ✅ |
| Crawling récursif (BFS) | ❌ | ✅ |
| Reconnaissance image (vision) | ⚠️ (via API externe) | ✅ (DeepSeek Vision) |

> Pour les fonctionnalités marquées ❌, le backend Python peut être déployé en parallèle
> comme service complémentaire (non requis pour le fonctionnement de base).

## Structure du projet

```
cloudflare-worker/
├── wrangler.jsonc          # Configuration Worker (routes, rate limits, AI binding)
├── package.json            # Dépendances (Hono, Wrangler, Typescript)
├── tsconfig.json           # Configuration TypeScript
├── src/
│   ├── index.ts            # Routeur Hono (/chat, /search, /scrape, /health)
│   ├── llm.ts              # Proxy LLM (Workers AI → DeepSeek → OpenRouter)
│   ├── scrape.ts           # Scraping léger avec HTMLRewriter
│   ├── sanitize.ts         # Validation et assainissement (injection, XSS)
│   └── rate_limit.ts       # Rate limiting in-memory (complément au WAF)
└── README.md
```
