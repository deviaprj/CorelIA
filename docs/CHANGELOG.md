# Changelog — CorelIA Transformation

## [1.1.0] - 2026-04-24 — Phase 3 : Exécution autonome

### 🔒 Sécurité
- **Fix critique** : suppression du bypass paywall en mode debug (`subscription_service.dart`). Le mode Pro en debug nécessite désormais la variable `DEBUG_FORCE_PRO=true`.
- **Proxy backend** : les clés API (DeepSeek, OpenRouter, Ollama) ne sont plus exposées dans le client compilé. Tous les appels IA passent par le backend FastAPI sécurisé.
- **Dio client** : ajout d'un intercepteur JWT Firebase, retry automatique (3x), et certificate pinning préparé.
- **Rate limiting** : intégration `slowapi` + Redis côté backend sur les endpoints `/chat` et `/search`.

### 🤖 Intelligence Artificielle
- **Router IA** : chaînage fallback intelligent :
  1. Ollama local (détection auto réseau)
  2. Ollama cloud (configurable)
  3. DeepSeek API
  4. OpenRouter (Pro)
- **Recherche web intégrée** : endpoint backend `/search` utilisant DuckDuckGo (gratuit) avec fallback SerpAPI (Pro).
- **Tool use** : définitions de fonctions (`search_web`, `get_datetime`, `get_weather`) prêtes pour le function calling.
- **Ollama local** : détection automatique sur `localhost:11434`, `10.0.2.2` (Android emulator), et réseau local.

### 🎙️ Voix — 100% Gratuit & Local
- **Service vocal avancé** (`voice_advanced_service.dart`) :
  - Enregistrement WAV 16kHz mono via `record` (qualité STT-ready).
  - Lecture streaming via `just_audio` avec interruption/pause.
  - Gestion des permissions micro via `permission_handler`.
- **Backend endpoints vocaux** (`backend/agents/voice.py`) :
  - `POST /voice/stt` — Proxy vers Ollama local (modèle `whisper`). Aucune clé externe.
  - `POST /voice/tts` — Proxy vers Ollama local (modèle `piper`). Aucune clé externe.
  - Si Ollama est injoignable, le client Flutter bascule sur `speech_to_text` / `flutter_tts`.
- **Suppression des services payants** : OpenAI Whisper API, ElevenLabs, Coqui Cloud retirés intégralement du projet.

### 🏗️ Architecture
- **Backend FastAPI** (`backend/`) :
  - `main.py` : App CORS, rate limiting, health check.
  - `core/config.py` : Variables d'environnement via Pydantic Settings.
  - `core/auth.py` : Vérification JWT Firebase.
  - `core/logging.py` : Logs structurés JSON avec request ID.
  - `agents/chat_router.py` : Streaming SSE avec fallback multi-provider.
  - `agents/search_engine.py` : DuckDuckGo + SerpAPI.
  - `agents/tools.py` : Définitions et exécuteur d'outils.
- **Flutter** :
  - `core/api/` : Couche réseau abstraite (`dio_client.dart`, `api_config.dart`).
  - `features/chat/data/models/` : Modèles typés (`ChatRequest`, `SearchResult`).
  - `features/chat/data/chat_api_service.dart` : Proxy backend.
  - `features/chat/data/search_service.dart` : Recherche web.
  - `features/chat/data/ollama_local_client.dart` : Client Ollama local.

### 💰 Monétisation
- Fix sécurité paywall debug.
- Préparation pour crédits à l'unité (backend ready).

### 📝 Configuration
- `.env.example` mis à jour avec `OLLAMA_API_KEY`.
- `backend/.env.example` créé avec toutes les variables backend.

### 📦 Dépendances ajoutées
```yaml
dio: ^5.7.0
connectivity_plus: ^6.1.0
record: ^5.2.0
just_audio: ^0.9.42
permission_handler: ^11.3.0
shimmer: ^3.0.0
flutter_slidable: ^3.1.0
url_launcher: ^6.3.0
crypto: ^3.0.5
```

### 🧪 Tests backend
- `backend/tests/test_chat.py` : Tests pytest couvrant health check, streaming mock, et auth 401.

---

## [1.0.0] - 2026-03-28 — Version initiale
- Chat texte avec streaming DeepSeek-V3 / OpenRouter / Ollama cloud.
- Auth Firebase (Email, Google, Apple).
- Sync temps réel Firestore.
- Publicités AdMob + Abonnements RevenueCat + Stripe web.
- Quotas gratuits 20/jour via Cloud Functions.
- Mode DEMO sans Firebase.
- Extension Chrome Manifest V3.
- Onboarding 3 étapes, parrainage code manuel.
- STT/TTS basiques (`speech_to_text`, `flutter_tts`).
