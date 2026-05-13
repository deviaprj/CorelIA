# README Développeur — AironBot

> Guide de setup, d'architecture et de contribution pour l'équipe technique.

---

## 1. STACK COMPLET

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Flutter App   │────▶│  FastAPI Backend│────▶│  IA Providers   │
│  (Android/iOS/  │     │  (Python 3.12+) │     │ DeepSeek/Ollama │
│   Chrome Ext)   │◄────│  + Firebase     │◄────│  OpenRouter     │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

### Frontend
- **Flutter 3.24+** — Dart >= 3.0.0
- **Riverpod 2.x** — State management (MVVM)
- **go_router 13.x** — Navigation
- **Dio 5.x** — HTTP client (intercepteurs JWT, retry, cache)
- **Firebase** — Auth, Firestore, Cloud Functions, FCM

### Backend
- **FastAPI 0.110+** — Framework API Python
- **Uvicorn** — Serveur ASGI
- **httpx** — Client HTTP async
- **Pydantic Settings** — Configuration par variables d'environnement
- **slowapi** — Rate limiting
- **redis** — Backend rate limiting distribué
- **duckduckgo-search** — Recherche web gratuite
- **firebase-admin** — Vérification JWT Firebase

---

## 2. SETUP LOCAL

### 2.1 Flutter

```bash
# 1. Dépendances
flutter pub get

# 2. Variables d'environnement
cp .env.example .env
# Éditer .env avec vos clés API

# 3. Lancer en mode dev (mobile)
flutter run --dart-define-from-file=.env

# 4. Lancer en mode extension
bash scripts/build_extension.sh
```

### 2.2 Backend FastAPI

```bash
cd backend

# 1. Virtualenv (Python 3.12+)
python -m venv venv
source venv/bin/activate  # Windows : venv\Scripts\activate

# 2. Dépendances
pip install -r requirements.txt

# 3. Variables d'environnement
cp .env.example .env
# Éditer .env avec vos clés API

# 4. Lancer le serveur (reload auto)
uvicorn main:app --reload --host 0.0.0.0 --port 8000

# 5. Tests
pytest tests/ -v
```

### 2.3 Docker (optionnel)

```bash
docker-compose up --build
# Le backend sera disponible sur http://localhost:8000
```

---

## 3. ARCHITECTURE

### 3.1 Règles de routage IA (Backend)

Le backend `agents/chat_router.py` applique le fallback suivant :

1. **Ollama local/cloud** — si le modèle demandé commence par `ollama/`
2. **DeepSeek** — modèle par défaut gratuit
3. **OpenRouter** — fallback Pro (Mistral, Llama, etc.)

Le client Flutter peut forcer un provider via le champ `model` :
- `"ollama/llama3.2"` → Ollama
- `"deepseek-chat"` → DeepSeek
- `"mistralai/mistral-large"` → OpenRouter

### 3.2 Sécurité des clés API

| Où ? | Quoi ? | Comment ? |
|---|---|---|
| `backend/.env` | Toutes les clés API | Variables d'environnement, jamais commitées |
| `lib/core/constants.dart` | Clés compilées (fallback) | `--dart-define-from-file=.env`, utilisées uniquement si backend KO |
| Client Flutter | Aucune clé exposée | JWT Firebase pour auth backend |

### 3.3 Auth JWT

Le backend vérifie le `Authorization: Bearer <token>` via `firebase-admin`.
Le token est récupéré côté Flutter par `FirebaseAuth.instance.currentUser?.getIdToken()`.

---

## 4. FONCTIONNALITÉS CLÉS

### 4.1 Recherche Web

**Endpoint backend** : `GET /search?q=...&lang=fr`

**Flow** :
1. Utilisateur active l'icône 🔍 dans le chat.
2. Le backend injecte les résultats de recherche dans le contexte système du LLM.
3. Le LLM répond en citant les sources.

**Coût** :
- DuckDuckGo : gratuit (rate-limité).
- SerpAPI : ~$50/mois pour 50k requêtes (fallback configuré).

### 4.2 Ollama Local

**Détection auto** :
- Android emulator → `http://10.0.2.2:11434`
- iOS simulator → `http://localhost:11434`
- Réseau local → scan rapide sur sous-réseau courant

**Configuration manuelle** :
Paramètres → Serveur Ollama local → saisir l'URL.

### 4.3 Voix Avancée

**Packages** :
- `record` — Enregistrement WAV 16kHz (qualité STT)
- `just_audio` — Lecture streaming avec interruption

**Mode Pro (Ollama local)** :
- STT : proxy backend vers Ollama local (modèle `whisper` ou tout modèle STT compatible Ollama). Aucune clé API externe.
- TTS : proxy backend vers Ollama local (modèle `piper` ou tout modèle TTS compatible Ollama). Aucune clé API externe.
- **Fallback** : si Ollama est injoignable, l'application bascule automatiquement sur `speech_to_text` (STT) et `flutter_tts` (TTS) qui sont 100% offline et gratuits.

---

## 5. DÉVELOPPEMENT

### 5.1 Ajouter un nouveau provider IA

1. **Backend** : ajouter `_stream_monprovider()` dans `backend/agents/chat_router.py`.
2. **Backend** : ajouter le provider dans `_chat_with_fallback()`.
3. **Flutter** : ajouter la clé dans `core/constants.dart` (fallback direct uniquement).
4. **Flutter** : tester avec `ChatApiService.fallbackStream()`.

### 5.2 Ajouter un outil (Tool Use)

1. **Backend** : ajouter la fonction dans `backend/agents/tools.py`.
2. **Backend** : ajouter la définition JSON Schema dans `get_tool_definitions()`.
3. **Backend** : dispatcher dans `execute_tool()`.
4. **Flutter** : activer `useSearch: true` dans `ChatRequest` pour envoyer le flag `tools`.

### 5.3 Tests

```bash
# Flutter
flutter test
flutter test integration_test/

# Backend
cd backend && pytest tests/ -v --cov=.
```

---

## 6. DÉPLOIEMENT

### 6.1 Backend

Recommandé : **Google Cloud Run** ou **Railway**.

```bash
# Build Docker
docker build -t aironbot-backend .

# Push & deploy
# (voir documentation Cloud Run ou Railway)
```

**Variables requises en production** :
```env
DEEPSEEK_API_KEY=sk-xxx
OPENROUTER_API_KEY=sk-or-xxx
OLLAMA_CLOUD_URL=https://ollama.aironbot.app
OLLAMA_CLOUD_API_KEY=xxx
SERPAPI_KEY=xxx
FIREBASE_PROJECT_ID=aironbot-prod
REDIS_URL=redis://... # Upstash ou Redis Cloud
APP_ENV=production
```

### 6.2 Flutter

```bash
# Android
flutter build apk --release --dart-define-from-file=.env
flutter build appbundle --release --dart-define-from-file=.env

# iOS
flutter build ios --release --dart-define-from-file=.env

# Extension Chrome
bash scripts/build_extension.sh
```

---

## 7. DÉPANNAGE

| Problème | Cause probable | Solution |
|---|---|---|
| `Backend indisponible` | Serveur local éteint ou URL mal configurée | Vérifier `BACKEND_URL` dans `.env` |
| `Ollama non détecté` | Ollama non lancé ou firewall | Lancer `ollama serve`, vérifier ports |
| `Quota exceeded` | Limite 20/jour atteinte | Passer Pro ou attendre minuit UTC |
| `Firebase Auth 401` | Token expiré | Relancer l'app ou `await user.getIdToken(true)` |
| `Pub non affichée` | Plateforme non mobile | AdMob = mobile uniquement |
| `Bypass paywall debug` | `DEBUG_FORCE_PRO` activé | Désactiver la variable d'environnement |

---

*Pour toute question, consulter `CLAUDE.md` ou ouvrir une issue.*
