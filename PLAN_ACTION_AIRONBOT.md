# PLAN D'ACTION — Transformation vers AironBot

> Date : 2026-04-24
> Statut : Phase 2 — Approuvé pour exécution

---

## 1. CHOIX TECHNOLOGIQUES

### 1.1 Frontend Mobile — Garder Flutter (pas React Native)
| Critère | Flutter | React Native |
|---|---|---|
| Code partagé extension Chrome | ✅ 95% | ❌ ~60% |
| Performance TTS/STT native | ✅ Excellente | ⚠️ Bridge overhead |
| Équipe / codebase existante | ✅ Déjà en place | ❌ Refactor total |
| Tailles binaires | ⚠️ ~15-20 MB | ✅ ~8-12 MB |

**Décision :** Conserver **Flutter 3.24+**. Le coût de migration vers React Native dépasse largement le bénéfice.

### 1.2 Backend — Ajouter Python FastAPI (pas Node.js pur)
| Critère | Firebase Functions (Node/TS) | Python FastAPI + Firebase |
|---|---|---|
| Proxy IA sécurisé | ⚠️ Limité (cold start, timeout 60s) | ✅ Parfait (streaming SSE long) |
| Tool use / RAG / Recherche web | ⚠️ Lourd en Node | ✅ Écosystème Python (LangChain, DuckDuckGo, SerpAPI) |
| Multi-agent orchestration | ❌ Complexe | ✅ CrewAI / Autogen / custom |
| Coût scaling | ⚠️ Firebase scale = coût exponentiel | ✅ Conteneurisable (Cloud Run / VPS) |
| Temps de développement | ✅ Court | ⚠️ Setup initial |

**Décision :**
- **Garder** Firebase Functions pour l'existant (auth, quotas, webhooks Stripe).
- **Ajouter** un backend **Python FastAPI** dédié à l'orchestration IA, la recherche web, le RAG et le proxy sécurisé des APIs.
- **Communication** : Flutter ↔ FastAPI via REST/SSE + Auth Firebase JWT.

### 1.3 Packages Flutter à ajouter
```yaml
dependencies:
  # --- Réseau & Cache ---
  dio: ^5.7.0                    # HTTP avancé (intercepteurs, retry, cache)
  retrofit: ^4.4.0               # Génération de clients API typés
  connectivity_plus: ^6.1.0      # État réseau
  cached_network_image: ^3.4.0   # Cache images (avatars, previews web)

  # --- Voix avancée ---
  record: ^5.2.0                 # Enregistrement audio WAV/PCM (meilleur que speech_to_text pour streaming)
  just_audio: ^0.9.42            # Lecture audio avancée (streaming, interruption)
  permission_handler: ^11.3.0    # Permissions micro

  # --- State & DI améliorés ---
  freezed_annotation: ^2.4.4     # Immutable data classes + Union types
  json_annotation: ^4.9.0        # Sérialisation JSON
  riverpod_annotation: ^2.3.5  # Génération de providers Riverpod

  # --- UI / UX ---
  shimmer: ^3.0.0                # Skeleton loaders
  flutter_slidable: ^3.1.0     # Swipe actions conversations
  url_launcher: ^6.3.0           # Ouvrir liens recherche web

  # --- Sécurité ---
  crypto: ^3.0.5                 # HMAC, hashing

  # --- Local Ollama ---
  # dio suffit pour appels localhost:11434

dev_dependencies:
  build_runner: ^2.4.13
  freezed: ^2.5.7
  json_serializable: ^6.9.0
  retrofit_generator: ^9.1.0
  riverpod_generator: ^2.4.0
  mocktail: ^1.0.4               # Mocking moderne (remplace mockito)
```

**Packages à supprimer / remplacer :**
- `http` → remplacé par `dio` (wrapper plus puissant).
- Garder `speech_to_text` et `flutter_tts` pour le MVP voix, mais étendre avec `record` + `just_audio` pour le mode avancé.

### 1.4 TTS / STT Solutions — 100% Gratuit & Local
| Approche | Avantage | Inconvénient | Choix |
|---|---|---|---|
| **Locale Flutter** (`speech_to_text` + `flutter_tts`) | Offline, rapide, 0€ | Qualité médiocre, langues limitées | ✅ Mode rapide & fallback |
| **Ollama Local** (Whisper via Ollama + Piper/Coqui TTS via Ollama) | Haute qualité, privacy totale, 0€ coût API | Nécessite un serveur Ollama local | ✅ Mode Pro (auto-hébergé) |
| **Hybride** | Dégradation progressive | Complexité | ✅ Cible finale |

**Décision :**
- **Mode gratuit** : `speech_to_text` + `flutter_tts` (existant).
- **Mode Pro** : Backend proxy vers **Ollama local** (modèles `whisper` pour STT, `piper` pour TTS). Aucun service vocal payant. Si Ollama est injoignable, fallback immédiat vers les packages Flutter natifs.

### 1.5 Recherche Web
| Service | Coût | Qualité | Choix |
|---|---|---|---|
| **SerpAPI** | ~$50/mois (50k requêtes) | Excellente (Google, Bing, etc.) | ✅ Backend proxy |
| **DuckDuckGo (`duckduckgo-search` Python)** | Gratuit | Moyenne, rate-limitée | ✅ Fallback gratuit |
| **Tavily AI** | ~$0.025/requête | Optimisé LLM (résumé inclus) | ✅ Option Pro |

**Décision :**
- Backend Python avec **`duckduckgo-search`** comme fallback gratuit.
- **SerpAPI** ou **Tavily** comme source premium (configurable via env).

### 1.6 Ollama vs DeepSeek — Stratégie Dual-Engine
| Rôle | Moteur | Fallback |
|---|---|---|
| **Gratuit / Rapide** | Ollama local (`llama3.2`, `phi4`) | DeepSeek API |
| **Standard** | DeepSeek-V3 | OpenRouter (Mistral) |
| **Pro / Complexe** | OpenRouter (Claude, GPT-4, Mistral Large) | DeepSeek-V3 |
| **Filtre / Modération** | Ollama local (`phi4-mini`) | Aucun (cloud) |

---

## 2. ARCHITECTURE CIBLE

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              FLUTTER APP                                 │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────┐   │
│  │  Auth    │ │  Chat    │ │  Voice   │ │  Search  │ │ Monetization │   │
│  │ (Riverpod│ │ (Riverpod│ │ (Riverpod│ │ (Riverpod│ │ (Riverpod)   │   │
│  │ Notifier)│ │ Notifier)│ │ Notifier)│ │ Notifier)│ │              │   │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘ └──────┬───────┘   │
│       │            │            │            │              │           │
│  ┌────┴────────────┴────────────┴────────────┴──────────────┴───────┐   │
│  │                    API Client (Dio + Retrofit)                  │   │
│  │         JWT Firebase Auth │ Retry │ Cache │ Certificate Pin     │   │
│  └────────────────────────────────────┬───────────────────────────────┘   │
└───────────────────────────────────────┼───────────────────────────────────┘
                                      │ HTTPS / SSE
┌───────────────────────────────────────┼───────────────────────────────────┐
│                         BACKEND FASTAPI                               │   │
│  ┌────────────────────────────────────┴───────────────────────────────┐   │   │
│  │                     API Gateway (Auth JWT)                        │   │   │
│  └────┬──────────────┬──────────────┬──────────────┬───────────────┘   │   │
│       │              │              │              │                   │   │
│  ┌────┴─────┐  ┌────┴─────┐  ┌────┴─────┐  ┌────┴─────┐             │   │
│  │  Agent   │  │  Agent   │  │  Agent   │  │  Agent   │             │   │
│  │  Chat    │  │  Search  │  │  Voice   │  │  RAG     │             │   │
│  │  Router  │  │  Engine  │  │  Proxy   │  │  Indexer │             │   │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘             │   │
│       │             │             │             │                  │   │
│  ┌────┴─────────────┴─────────────┴─────────────┴──────┐            │   │
│  │              Orchestrateur Multi-Agents              │            │   │
│  │    (DeepSeek ↔ Ollama ↔ OpenRouter fallback)       │            │   │
│  └────────────────────────┬───────────────────────────────┘            │   │
│                           │                                          │   │
│       ┌───────────────────┼───────────────────┐                         │   │
│       ▼                   ▼                   ▼                     │   │
│  ┌─────────┐       ┌──────────┐       ┌─────────────┐              │   │
│  │DeepSeek │       │ Ollama   │       │ OpenRouter  │              │   │
│  │  API    │◄─────►│ (local/  │       │  (Pro)      │              │   │
│  │         │       │  remote) │       │             │              │   │
│  └─────────┘       └──────────┘       └─────────────┘              │   │
│                                                                     │   │
│  ┌─────────────────────────────────────────────────────────────┐   │   │
│  │  Services tiers : SerpAPI / Tavily │ DuckDuckGo │ Ollama Voice │   │   │
│  └─────────────────────────────────────────────────────────────┘   │   │
└─────────────────────────────────────────────────────────────────────┘   │
                                                                         │
┌─────────────────────────────────────────────────────────────────────────┘
│                    FIREBASE (conservé)                                   │
│  Auth │ Firestore │ Cloud Functions (quotas, webhooks) │ FCM            │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 3. DÉCOMPOSITION EN MODULES (2 Sprints)

### Sprint 1 — Fondations & Sécurité (Semaine 1-2)
| ID | Module | Description | Livrable |
|---|---|---|---|
| S1-M1 | **Backend FastAPI** | Setup projet Python, structure agents, proxy IA sécurisé | `backend/` |
| S1-M2 | **Refonte API Client** | Remplacer `http` par `dio`, ajouter intercepteurs JWT, retry, cache | `lib/core/api/` |
| S1-M3 | **Sécurisation** | Retirer clés API du client, proxy backend, fix bypass debug paywall, cert pinning | `backend/`, `lib/` |
| S1-M4 | **Ollama Local** | Détection réseau, appels `localhost:11434`, fallback cloud | `lib/features/chat/data/ollama_client.dart` |
| S1-M5 | **Router IA** | Chaînage fallback : Ollama → DeepSeek → OpenRouter | `backend/agents/chat_router.py` |
| S1-M6 | **Recherche Web** | Endpoint backend `/search` (DuckDuckGo + SerpAPI fallback) | `backend/agents/search_engine.py` |
| S1-M7 | **Tool Use** | Function calling basique (recherche web, météo, datetime) | `backend/agents/tools.py` |

### Sprint 2 — Voix, UX, Monétisation (Semaine 3-4)
| ID | Module | Description | Livrable |
|---|---|---|---|
| S2-M1 | **Voix Avancée** | `record` + `just_audio`, proxy Ollama local pour STT/TTS, fallback `speech_to_text`/`flutter_tts` | `lib/features/voice/` |
| S2-M2 | **Chat Streaming V2** | Gestion d'erreurs granulaire, reconnexion auto, historique infini paginé | `lib/features/chat/presentation/` |
| S2-M3 | **Monétisation V2** | Deep links parrainage, système de crédits, bandeau GDPR, analytics | `lib/features/monetization/` |
| S2-M4 | **RAG Projects** | Indexation sémantique des projects (embeddings) via backend | `backend/agents/rag_indexer.py` |
| S2-M5 | **Extension Chrome V2** | Sync cross-device améliorée, side-panel enrichi | `web/` |
| S2-M6 | **Tests & CI** | Tests E2E voix, load tests backend, GitHub Actions build backend | `.github/workflows/` |

---

## 4. STRATÉGIE OLLAMA / DEEPSEEK — DÉTAIL

### 4.1 Ollama — Mode d'emploi
```
Utilisateur mobile (WiFi local)
    │
    ├──► Ollama détecté sur 192.168.1.x:11434 ?
    │       ├──► Oui → Utiliser Ollama (llama3.2, mistral, phi4)
    │       │         Latence : ~50-200ms (local)
    │       │         Coût : 0€
    │       │
    │       └──► Non → Proxy backend FastAPI
    │                 └──► Ollama Pro (cloud hébergé) si configuré
    │                 └──► Sinon fallback DeepSeek
```

**Configuration `.env` :**
```bash
# Ollama
OLLAMA_LOCAL_URL=http://localhost:11434
OLLAMA_CLOUD_URL=https://ollama.aironbot.app  # Optionnel : instance cloud dédiée
OLLAMA_CLOUD_API_KEY=ollama_cloud_key_xxx

# DeepSeek
DEEPSEEK_API_KEY=sk-xxx

# OpenRouter (Pro)
OPENROUTER_API_KEY=sk-or-xxx
```

### 4.2 Chaînage Fallback (Backend)
```python
# backend/agents/chat_router.py
class ChatRouter:
    async def stream_response(self, request: ChatRequest):
        # 1. Essayer Ollama local (si utilisateur a fourni une URL)
        if request.ollama_url:
            try:
                return await ollama_client.stream(request)
            except Exception:
                pass  # Fallback

        # 2. Essayer Ollama cloud (Pro)
        if config.ollama_cloud_key:
            try:
                return await ollama_cloud_client.stream(request)
            except Exception:
                pass

        # 3. Essayer DeepSeek
        try:
            return await deepseek_client.stream(request)
        except Exception:
            pass

        # 4. Fallback ultime : OpenRouter (Pro) ou erreur explicite
        return await openrouter_client.stream(request)
```

### 4.3 Recherche Web Injectée
```
Utilisateur : "Quel temps fait-il à Paris ?"
    │
    ├──► ChatRouter détecte intent "météo" (tool use)
    ├──► Appel Search Engine → DuckDuckGo / météo API
    ├──► Résultat JSON injecté dans le contexte système
    └──► LLM répond avec données fraîches
```

---

## 5. SÉCURITÉ — PLAN DE DURCISSEMENT

| Mesure | Implémentation | Fichier(s) |
|---|---|---|
| **Clés API hors client** | Toutes les clés restent dans `backend/.env` | `backend/.env` |
| **Auth JWT** | FastAPI vérifie le token Firebase Auth | `backend/core/auth.py` |
| **Rate Limiting** | `slowapi` (Redis-backed) sur `/chat`, `/search` | `backend/main.py` |
| **Input Validation** | Pydantic v2 + sanitization HTML | `backend/schemas/` |
| **Certificate Pinning** | Pin du certificat backend dans `dio` | `lib/core/api/dio_client.dart` |
| **Paywall Debug Fix** | Retirer `!kReleaseMode` bypass | `lib/features/monetization/...` |
| **Audit Logs** | Log toutes les requêtes IA (anonymisé) | `backend/core/logging.py` |
| **CORS strict** | Origines autorisées uniquement | `backend/main.py` |

---

## 6. INFRASTRUCTURE DÉPLOIEMENT BACKEND

```yaml
# docker-compose.yml (local dev)
version: '3.9'
services:
  api:
    build: ./backend
    ports:
      - "8000:8000"
    environment:
      - DEEPSEEK_API_KEY=${DEEPSEEK_API_KEY}
      - OPENROUTER_API_KEY=${OPENROUTER_API_KEY}
      - SERPAPI_KEY=${SERPAPI_KEY}
    volumes:
      - ./backend/.env:/app/.env:ro

  # Optionnel : Redis pour rate limiting
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
```

**Production :**
- Cloud Run (GCP) ou Railway pour FastAPI.
- Cloudflare Tunnel ou reverse proxy Nginx pour HTTPS.
- Redis Cloud ou Upstash pour rate limiting distribué.

---

## 7. MÉTRIQUES DE SUCCÈS

| Métrique | Cible | Comment mesurer |
|---|---|---|
| Latence moyenne chat | < 800ms (first token) | Backend logs |
| Disponibilité IA | > 99.5% | Fallback rate monitoring |
| Couverture tests | > 80% | `flutter test --coverage` + `pytest --cov` |
| Temps réponse voix | < 2s (STT + TTS) | Mesures côté backend |
| Revenu utilisateur (ARPU) | +30% vs actuel | RevenueCat + Stripe analytics |
| Score Lighthouse extension | > 90 | Chrome DevTools |

---

## 8. RISQUES & MITIGATIONS

| Risque | Probabilité | Impact | Mitigation |
|---|---|---|---|
| DeepSeek API indisponible | Moyenne | Élevé | Fallback Ollama + OpenRouter chaîné |
| Ollama local non détecté | Élevée | Moyen | UX claire : "Serveur Ollama non trouvé, bascule cloud" |
| Latence backend Python | Moyenne | Moyen | Uvicorn + async, cache Redis, géolocalisation edge |
| Coût SerpAPI | Moyenne | Faible | Fallback DuckDuckGo gratuit |
| Rejet App Store (monétisation) | Faible | Élevé | Respecter guidelines Apple (restore purchases, pas de bypass) |

---

*Plan validé — Passage à la Phase 3 : Exécution autonome.*
