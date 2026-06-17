# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Corely is a cross-platform AI chat application (Flutter/Dart) targeting 1M+ users. It includes:
- **Mobile app**: Android/iOS with Firebase Auth, chat, voice input
- **Chrome Extension**: Same codebase, built with Flutter Web + Manifest V3
- **Backend** (optional cloud): Python FastAPI at `api.zentic.fr` with Redis rate limiting
- **Monetization**: AdMob ads (free tier), RevenueCat subscriptions (Pro tier)
- **AI**: DeepSeek-V4-Flash (free text), DeepSeek-Chat (vision fallback), OpenRouter (Pro: Mistral-Large, GPT-4o-mini)

### Contrainte d'autonomie (règle d'or)
L'APK Android et l'extension Chrome doivent être 100% autonomes. Aucun backend local requis. Toutes les fonctionnalités doivent fonctionner via services natifs, appels API directs, ou packages Dart/Flutter embarqués. Le backend cloud (`api.zentic.fr`) est un bonus, pas une dépendance.

## Architecture

**Pattern**: MVVM + Riverpod for state management

**Conditional Imports** (mobile vs web/extension):
Many services use conditional exports so the same codebase compiles for mobile and web:
```dart
// barrel file (e.g., dio_client.dart)
export 'dio_client_io.dart' if (dart.library.html) 'dio_client_web.dart';
```
Files with conditional exports:
- `lib/core/api/dio_client.dart` → `_io` (dart:io, cert pinning) / `_web` (no dart:io)
- `lib/features/chat/data/image_upload_service.dart` → `_io` (compress, camera) / `_web` (stub)
- `lib/features/chat/data/ollama_vision_service.dart` → `_io` (local Ollama) / `_web` (unavailable)
- `lib/features/monetization/ads/ad_service.dart` → `_mobile` (AdMob) / `_web` (no-op stub)
- `lib/features/monetization/ads/ad_banner_widget.dart` → `_mobile` (AdMob banner) / `_web` (SizedBox.shrink)
- `lib/features/monetization/subscription/subscription_service.dart` → `_mobile` (RevenueCat) / `_web` (no-op stub)
- `lib/features/monetization/subscription/paywall_screen.dart` → barrel `_mobile` (RevenueCat + fallback Stripe) / `_web` (Stripe checkout / fallback URL)
- `lib/features/referral/data/deep_link_service.dart` → `_io` (app_links) / `_web` (URL-based)

**Core Structure**:
```
lib/
├── main.dart                    # Entry point, Firebase/AdMob/RevenueCat init, CorelyApp
├── app/                         # Router (go_router) and theme
├── core/                        # Shared: providers, platform_service, secure_storage
│   ├── platform/platform_service.dart  # Detects mobile/extension/web, AppPlatform.name
│   ├── providers/
│   │   ├── app_providers.dart           # Theme, onboarding, search toggle
│   │   └── firebase_providers.dart      # Auth state, Firestore, Messaging
│   └── constants.dart                  # API URLs, model names, collections, String.fromEnvironment
├── features/
│   ├── auth/                    # FirebaseAuth + email/Google/Apple + mock auth
│   ├── chat/
│   │   ├── data/                # ai_client, search_service, oralize_service, travel_params_parser (ADR-029), web_search_trigger (ADR-030), search_intent_extractor, file/image upload, quotas
│   │   ├── domain/              # Message, Conversation models
│   │   └── presentation/        # ChatNotifier, voice services, UI screens
│   ├── projects/                # Pro feature: saved projects/folders
│   ├── monetization/            # Ads (AdMob) + subscriptions (RevenueCat)
│   ├── referral/                # Deep links + referral service
│   └── settings/               # Settings screen, systemPromptProvider
└── shared/                      # Widgets, extensions
```

**Backend** (`backend/`):
```
backend/
├── agents/
│   ├── chat_router.py           # AI stream routing (DeepSeek + OpenRouter + tools)
│   ├── search_engine.py         # DuckDuckGo + SerpAPI search + scrape_url()
│   ├── search_smart.py          # Unified smart search (intent + parallel scraping)
│   ├── download_service.py      # yt-dlp + page scraper for media extraction
│   └── crawl_service.py         # Recursive BFS crawler (HTTrack-style)
├── core/                        # Config, auth, logging
└── schemas/                     # Pydantic models
```

**Backend Security** (ADR-027 — Bloc 1):
- **Two-tier API auth** (`backend/core/auth.py`) : `CLIENT_API_KEY` (soft gate, APK-embedded via `--dart-define`, header `X-API-Key`, transition-open si vide) gates les routes APK-facing (`/scrape`, `/search_smart`, `/download_media`, `/crawl`, `/script/scrape`, `/script/api-fetch`, `/insights/ingest|trends|demographics`). `API_SECRET_KEY` (opérateur, fail-closed 403 si vide, JAMAIS dans l'APK) gates RCE/admin (`/script/exec`, `/config/diagnose|migrate`, `/agent/execute|status|result`, `/insights/audit`). Comparaison constant-time `hmac.compare_digest`. `/chat/completions` = Firebase JWT (`verify_firebase_token`), indépendant des deux clés.
- **SSRF** (`backend/core/net_guard.py`) : `assert_safe_url` (scheme {http,https} + blocklist loopback/private/cloud-metadata `169.254.169.254`) + `safe_get`/`safe_get_sync` (auto-redirect désactivé, re-validation per-hop `Location`, max 4 redirects). Câblé dans `search_engine`, `search_smart`, `download_service`, `crawl_service`, `script_executor`.
- **Sandbox scripts IA** (`backend/agents/script_executor.py`) : validateur AST `_ScriptValidator` (`_ALLOWED_MODULES`, `_DANGEROUS_NAMES`/`_DANGEROUS_ATTRS`), env minimal `_SANDBOX_ENV` (pas de clés API héritées), `tempfile.TemporaryDirectory` cwd, timeout 15s. `scrape_with_script`/`api_fetch_with_script` ont un pre-check `assert_safe_url`.
- **config_agent** : `asyncio.create_subprocess_exec` (argv, pas de shell) + `_validate_domain` strict → injection shell éliminée.
- **Conteneurs non-root** : backend uid 10001, codewhale uid 10002, `/workspace` chown pour héritage du named volume.
- **docker-compose** : `docker.sock` retiré (escalade root-equivalent), port Ollama 11434 non publié (endpoint LLM non auth était exposé à internet), `CORS_ORIGINS` serré (`allow_credentials = not wildcard`), clés two-tier en env.
- **⚠️ Changement de comportement** : `/script/exec` (RCE générique) n'est plus joignable depuis l'APK (opérateur-only) — le client renvoie un message clair "réservé à l'opérateur" sur 401/403. `/scrape-script` et `/api-fetch` restent accessibles (constrained à une URL + sandbox).
- **⚠️ Fuite `.env` APK** : `.env` retiré des `assets` (`pubspec.yaml`) — bundling shipait `API_SECRET_KEY` opérateur + `OPENROUTER_API_KEY` payant + Stripe webhook dans l'APK extractible. Clés client via `--dart-define` uniquement. `main.dart` garde `dotenv.load` en try/catch (asset absent = non-fatal). Build mobile : `flutter build apk --dart-define=BACKEND_URL=... --dart-define=CLIENT_API_KEY=... --dart-define=DEEPSEEK_API_KEY=... ...`
- **⚠️ Action VPS manuelle** : rotation de `API_SECRET_KEY` — une valeur réelle (`311788a1…`) était commitée dans `scripts/server_init.sh` (retirée du repo, génération aléatoire à la place). Si encore live sur le VPS `.env`, la tourner (`docker compose up -d --force-recreate backend codewhale-agent`). Git history la contient encore → `git filter-repo` si purge requise.

**Chrome Extension** (`web/`):
```
web/
├── manifest.json                # Manifest V3 — no "type": "module", CSP with worker-src blob:
├── background.js                # Service worker — context menu "Demander à Corely"
├── content_script.js            # Text selection capture on all pages
├── speech_bridge.js             # Web Speech API bridge (STT only, no TTS)
├── icons/                       # Extension icons (Corely "C" logo, purple #6C63FF)
└── index.html                   # Flutter Web bootstrap with CSS spinner
```

**Platform Detection** (`lib/core/platform/platform_service.dart`):
- Detects: mobile Android, mobile iOS, Chrome extension, web
- `AppPlatform.name` getter: returns 'android', 'ios', 'extension', 'web'
- Critical for conditional Firebase/AdMob/RevenueCat initialization

**State Management**:
- Riverpod providers in `lib/core/providers/app_providers.dart` (theme, onboarding, search toggle)
- Firebase providers in `lib/core/providers/firebase_providers.dart` (auth state, Firestore, Messaging)
- `systemPromptProvider` in `settings_screen.dart` (StateNotifier + SharedPreferences)

**Key Flows**:
1. App start → Firebase init (or DEMO mode on extension) → check onboarding → check auth → route to appropriate screen
2. Chat → Firestore repository → AI client (DeepSeek/OpenRouter) → quota check → response
3. Chat → system prompt injected as first system message → Corely personality
4. Chat → intent classification (`WebSearchTrigger.needsWebSearch()` — ADR-030) → web search only for factual/temporal queries
5. Voice dictation → SpeechToText → text input → ChatNotifier
6. Voice conversation loop → VoiceConversationNotifier (listening → thinking → speaking → idle → repeat)
7. Extension build → Flutter Web + base href patch + SW removal + manifest fix
8. Slash commands → `_handleSlashCommand()` → backend `/scrape`, `/download_media`, `/crawl` or extension DOM actions

## Commands

**Setup**:
```bash
flutter pub get
cp .env.example .env  # Fill in API keys
```

**Run**:
```bash
flutter run -d <device>
flutter run -d chrome
bash scripts/build_extension.sh   # → build/extension/
```

**Test**:
```bash
bash scripts/run_tests.sh all
flutter test path/to/test.dart
```

**Build**:
```bash
flutter build apk
flutter build ios
bash scripts/build_extension.sh   # → corely-extension.zip
```

**Lint**:
```bash
flutter analyze
```

## Environment Variables

Required in `.env` (never commit):
- `DEEPSEEK_API_KEY`, `OPENROUTER_API_KEY` — AI providers
- `ADMOB_*` — AdMob app/banner/interstitial/rewarded IDs
- `REVENUECAT_API_KEY_*` — iOS/Android subscription keys
- `STRIPE_*` — Web payment (extension)
- `APP_ENV` — development/production

**For Chrome extension builds**, API keys are embedded via `--dart-define`:
```bash
flutter build web --dart-define=DEEPSEEK_API_KEY=sk-xxx
# OPENROUTER_API_KEY n'est PAS embarqué (clé opérateur payante) — l'extension est
# toujours en mode DEMO (isPro=false), OpenRouter n'y est jamais appelé.
# build_extension.sh applique une whitelist client-safe (DEEPSEEK, ADMOB, REVENUECAT, APP_ENV).
```
`AppConstants._env()` checks `String.fromEnvironment` first, then falls back to `.env`.

## AI Models & Routing

**DeepSeek** (`lib/features/chat/data/ai_client.dart`):
- `deepseek-v4-flash` — texte (gratuit, par défaut)
- `deepseek-chat` — texte + vision (fallback image si pas OpenRouter)
- Paramètres : `stream`, `max_tokens`, `enable_search` (désactivé par défaut)
- Endpoint : `https://api.deepseek.com/v1/chat/completions`

**OpenRouter** (Pro, `lib/features/chat/data/ai_client.dart`):
- `mistralai/mistral-large-2407` — texte Pro
- `openai/gpt-4o-mini` — vision Pro
- Headers obligatoires : `HTTP-Referer`, `X-Title`

**ModelRouter** (`lib/features/chat/data/model_router.dart`):
- TaskType : general, reasoning, vision, document, code, longFile, vocal, vocalFast
- `classifyTask()` : détermine le type de tâche (message normal, code, document, vision, etc.)
- `resolveModel(taskType, {userOverride, isPro})` : résout le modèle via routing table + rate limit tracking
- **Tier-aware** : `isFree: true` sur les modèles DeepSeek direct API. Si `isPro == false`, les modèles OpenRouter payants (`isFree: false`) sont filtrés.
- `markRateLimited()` : cooldown automatique en cas de 429

**Routage des requêtes** (`_getDirectAiStream` dans `chat_notifier.dart`):
1. **modelOverride** (ex: `task:vocal`) → ModelRouter → chaîne spécifique
2. **Image détectée** (`content` est un `List`) → `_getVisionStream(history, isPro:)`
   - `deepseek-chat` (isFree) en priorité → OpenRouter GPT-4o-mini (Pro uniquement)
   - Sinon `AiException` avec message clair
3. Pro sans image → OpenRouter Mistral
4. Free sans image → DeepSeek V4 Flash (isFree)
5. **TTS tier-aware** : OpenRouter TTS (`/audio/speech`) uniquement si `isPro == true`, gratuit → flutter_tts natif

**System prompt** — Injecté en tête de chaque conversation:
- Par défaut: personnalité Corely (chaleureux, direct, tutoiement, français)
- Personnalisable via `systemPromptProvider` dans les paramètres
- Sauvegardé en SharedPreferences (`corely_system_prompt`)

**Format image** (`message.dart:toApiMap()`):
```json
{
  "role": "user",
  "content": [
    {"type": "text", "text": "..."},
    {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64,..."}}
  ]
}
```
- Texte placé AVANT l'image dans le tableau `content`
- Limite : 1 MB (raw bytes), vérification base64 < 1.5 MB
- MIME types supportés : JPEG, PNG, WebP, GIF, BMP

## Voice Mode Architecture (V16 — Tour-par-Tour Half-Duplex)

**Qualité TTS système (critique pour le rendu)** :
- Sur **Android** : paramètres → Accessibilité → Synthèse vocale → Moteur préféré → **Google Speech Services** (ou Samsung Neural si disponible). Éviter les moteurs basiques (pico TTS, eSpeak).
- Sur **iOS** : paramètres → Accessibilité → Contenu vocal → Voix → **Améliorée** (Enhanced) ou **Premium**. Activer "Haute qualité" si disponible.
- `TtsNaturalService` détecte automatiquement les voix "neural/premium/enhanced" via `getVoices()`. Si aucune n'est trouvée, un warning est loggé.
- Pour un rendu vraiment humain, utiliser **OpenRouter TTS** (`gpt-4o-mini-tts`) — c'est la chaîne primaire sur mobile quand `OPENROUTER_API_KEY` est renseignée.

**Deux modes distincts** :
1. **Dictée** (bouton micro dans `InputBar`) → `VoiceServiceNotifier.startListening()`
2. **Conversation vocale mains-libres** (toggle "Vocal ON/OFF" dans toolbar) → `VoiceConversationNotifier.startConversation()`

**VoiceServiceNotifier** (`lib/features/chat/presentation/voice_service.dart`):
- STT continu natif : `listenFor: 30min`, `pauseFor: null` en mode conversation
- Pas de VAD custom — `finalResult` natif du STT uniquement
- `SpeechFinalEvent` émis quand `result.finalResult == true`
- `setConversationMode(true/false)` : active/désactive le redémarrage auto du micro
- `onStatus: (status)` ne redémarre pas le micro en mode conversation (géré explicitement par `VoiceConversationNotifier`)
- Permission micro : cache `_microphonePermissionGranted`, reset dans `forceReset()`

**VoiceConversationNotifier** (`lib/features/chat/presentation/voice_conversation_service.dart`):
- Machine à états tour-par-tour : `listening → thinking → speaking → listening`
- **Half-duplex** : micro coupé AVANT le TTS (`stopListening()`), rouvert APRÈS (`startListening()`)
- **TTS bloc** : la réponse complète est parlée d'un bloc via `speakNaturally()` (pas de streaming par phrases)
- **Token de génération** (Bloc 2, ADR-028) : `_generation` (int) incrémenté à chaque frontière de tour (start/barge-in/stop/dispose). Chaque continuation async capture `gen` et **bail si `gen != _generation`** → un speak supplanté (barge-in/stop) ne rouvre jamais le micro ni n'écrase l'état du tour courant. `_resetTurnState()` (bump génération + clear `_isProcessingResponse`/`_lastProcessedTranscript`/`_lastRequestTime`/`_sttFailureCount`) appelé à start/stop/dispose (anti-pollution inter-sessions). Garde `_isProcessingResponse` lié à la génération : libéré dans `whenComplete` seulement si le tour qui l'a posé est toujours courant.
- **Barge-in par speech final** : `SpeechFinalEvent` détecté pendant `speaking` avec > 3 mots → `stopSpeaking()` + `_generation++` (invalide le tour en cours) + routage par intention (`BargeInIntentClassifier`) : `repeat` → `_respeakLastAssistant()` (relit le dernier message assistant), `topicChange` → nouveau message LLM préfixé, `stop` → `_returnToListening()` (coupe le TTS + repasse en écoute SANS round-trip LLM), `correction`/`none` → nouveau message LLM
- `_speakFullResponse(text, {generation})` : stop micro → TTS bloc → pause **1200ms** (réinit SpeechToText Android ~300-500ms + anti-echo résiduel) → **state = listening** + micro rouvert — mais uniquement si le tour n'a pas été supplanté (`gen == _generation`)
- **Max 3 échecs STT consécutifs → état `error`** (Bloc 2, ADR-028) : `voice_service.dart` expose `onSttError` (stream émis depuis `onError` STT native + catch de `_startSttListen`). `_onSttError` compte, **tente reprise** (redémarrage micro 400ms) si `state==listening`, bascule en `error` après 3 (anti-boucle). Reset du compteur sur un speech final exploitable. L'échec du démarrage initial reste géré par le check 500ms.
- Écoute event-driven : `_onSpeechFinal(transcript)` (native `finalResult` du STT), pas de VAD custom. Vérif micro démarré 500ms après `startListening()` → état `error` si indisponible.
- Dedup : `_lastProcessedTranscript` + `_lastProcessedTime` (null-check défensif) protègent contre les doublons de callback dans les 2s

**TTS** (`lib/features/chat/presentation/tts_natural_service.dart`):
- **Tier-aware** : OpenRouter TTS réservé aux Pro. `speakNaturally(text, {bool isPro = false})` — défaut **fail-safe** (gratuit par défaut ; il faut expliciter `isPro: true` pour l'OpenRouter payant). Utilisateurs gratuits → flutter_tts natif.
- **Oralize Pass (LLM)** : `OralizeService.oralize(text, {bool isPro = false})` appelle DeepSeek Flash pour convertir le markdown en texte oral naturel AVANT le TTS. **Réservé aux Pro** (`!isPro` court-circuite l'appel LLM → fallback `cleanMarkdown` gratuit). Remplace l'approche regex fragile de `cleanMarkdown`. Coût ~$0.00003/appel, latence ~0.5-1s, timeout 4s (half-duplex : ne bloque pas le tour). Cache LRU (touch sur hit). Fallback automatique vers `cleanMarkdown` si l'appel LLM échoue.
- **Primaire (mobile Pro)** : OpenRouter TTS (`/audio/speech`) — voix réalistes (nova, shimmer, alloy, echo, fable, onyx)
- **Fallback universel** : flutter_tts natif avec **sélection dynamique de voix** (`getVoices` → meilleure fr-FR neural/premium)
- **Préchauffage** : utterance vide dans `init()` pour réduire la latence de la première phrase
- **Speed adaptatif par émotion** : base `_speechRate = 0.42`, adapté via `emotionTtsConfigs` (neutral 0.52, joyful 0.58, sad 0.46). Court texte (<150 chars) : +5%, long texte : -5%.
- **Chunks intelligents** : max 300 caractères, découpe sur limites de phrases (`.!?`) > clauses (`,;`) > mots. **Jamais au milieu d'un mot.**
- **Pauses naturelles** : 60ms inter-phrase, 350ms inter-paragraphe (anti-robotique)
- OpenRouter TTS speed : 0.95, flutter_tts base pitch : 1.10
- Chaîne : gpt-4o-mini-tts → Orpheus 3B → kokoro-82m → flutter_tts (dernier recours)
- Cache TTS : `TtsCacheService` avec `putBytes()` pour audio OpenRouter
- `AudioPlayerFactory` : just_audio (mobile) / stub (web)
- Nettoyage markdown : `cleanMarkdown()` strippe sources, citations `[n]`, tableaux, blocs ` ```reasoning`, artefacts `* - _ | [ ] # >`
- `speakNaturally()` : parse émotion → cleanMarkdown → lit → attend la fin via `Completer`
- `TtsEmotion` → voix : neutral→nova, joyful→shimmer, serious→echo, excited→fable, sad→onyx

**Vocal LLM Routing** (`lib/features/chat/data/model_router.dart`):
- `ModelRouter` avec `TaskType` enum : general, reasoning, vision, document, code, longFile, vocal, vocalFast
- Chaîne vocale : arcee/trinity → neversleep/ring-2.6-1t → deepseek/deepseek-r1:free → openai/gpt-4o-mini
- Chaîne vocalFast : neversleep/ring-2.6-1t → arcee/trinity → deepseek/deepseek-r1:free → openai/gpt-4o-mini
- `RateLimitTracker` : cooldown map, `isCoolingDown()`, `setCooldown()`
- Paramètres vocaux LLM : temperature=0.95, top_p=0.95, frequency_penalty=0.2
- Prompt vocal jovial injecté quand `isVoiceConversation=true` : "MODE VOCAL ACTIF — Réponds comme un ami au téléphone"

**OpenRouter TTS** (`lib/features/chat/data/openrouter_tts_service.dart`):
- Appelle `/audio/speech` avec model gpt-4o-mini-tts → fallback kokoro-82m
- TtsVoice enum (nova, shimmer, alloy, echo, fable, onyx)
- Texte tronqué à 4096 chars, JSON escaping, `isAvailable` getter
- Retourne `Uint8List?` (MP3 bytes)

**Aurora Splash** (`lib/features/chat/presentation/aurora_splash.dart`):
- Overlay plein écran pendant le mode vocal mains-libres
- 15 particules animées avec couleur cyclique
- États : vert=micro (listening), bleu=thinking, orange=speaking, cyan=STT processing
- Affiche le transcript en temps réel pendant l'écoute

**Extension Chrome — Pont vocal** (`web/speech_bridge.js`):
- STT + TTS via `webkitSpeechRecognition` + `speechSynthesis`
- STT : multi-langue, continuous mode, retry x3
- TTS : mapping émotion → rate/pitch, sélection meilleure voix par langue (Google neural > native > any)
- Événements CustomEvent : `corely_speech_start/result/end/error`, `corely_tts_speak/stop/end/error`

## Attachment UX (pièces jointes)

**Flux** :
1. Pick image/fichier → stocké dans `_pendingAttachment` (état `_ChatScreenState`)
2. Chip affiché dans `InputBar` avec nom du fichier + bouton ✕
3. L'utilisateur tape sa question
4. Envoi → `SendCallback(text, imageBase64:, imageMimeType:, fileName:, fileContent:)`
5. Texte + pièce jointe partent ensemble en un seul message

**Classes** (`input_bar.dart`) :
- `AttachmentData` : `imageBase64`, `imageMimeType`, `fileName`, `fileContent`, `previewLabel`
- `SendCallback` = `void Function(String, {String? imageBase64, ...})`

**Fichiers supportés** : PDF, DOCX, XLSX, TXT, CSV, MD
- Extraction texte côté client (via `file_upload_service.dart`)
- Limites : 5 MB gratuit, 50 MB Pro
- Le contenu extrait est injecté comme message `system` dans l'historique

## Web Search

**Client** (`lib/features/chat/data/search_service.dart`):
- `SearchService` avec fallback : backend cloud → DuckDuckGo HTML scraping direct
- `formatForAi()` : injecte les résultats dans le contexte système (~4000 tokens / 16000 chars)
- `formatSourcesForUi()` / `formatSourcesAsList()` : affichage dans le chat

**Backend** (`backend/agents/search_engine.py`):
- `search_duckduckgo()` : via package Python `duckduckgo_search`
- `search_serpapi()` : fallback SerpAPI
- Intégré dans `chat_router.py` via tool calling (`search_web`, `get_datetime`, `get_weather`)

**Intégration chat** (`chat_notifier.dart` + `lib/features/chat/data/web_search_trigger.dart` — ADR-030) :
- `useSearch: false` par défaut (recherche désactivée)
- Classification d'intent `WebSearchTrigger.needsWebSearch()` : déclencheurs factuels/temporels, exclusions créatives/code (multilingue FR/EN/ES/DE/IT/PT)
- Extraction de requête `WebSearchTrigger.extractSearchQuery()` : supprime salutations, limite longueur (200 chars)
- Recherche déclenchée si `state.useSearch || WebSearchTrigger.needsWebSearch(userMsg.content)`
- `enable_search: false` dans l'appel DeepSeek (on contrôle la recherche nous-mêmes)
- Résultats injectés comme message système avant l'historique

**Cache** (`lib/features/chat/data/search_cache_service.dart`):
- LRU cache avec clés SHA-256, TTL 15 min
- Sauvegardé en SharedPreferences

## Enhanced Search (Recherche Enrichie)

**Architecture 3 niveaux** (`lib/features/chat/data/enhanced_search_service.dart`):
1. API dédiée (SerpAPI, OpenWeatherMap) si clé disponible
2. DuckDuckGo HTML scraping avec décodage URLs de redirection (`_decodeDdgUrl()`)
3. Liens directs toujours générés (Skyscanner, Google Flights, Kayak, Opodo, Booking, Airbnb)

**Types de recherche supportés** :
- **Vols** (`searchFlights()`) : extraction ville départ/arrivée + dates via `parseFlightParams()`
- **Hôtels** (`searchHotels()`) : extraction ville + dates check-in/check-out
- **Produits** (`searchProducts()`) : shopping via DuckDuckGo + Google Shopping lien direct
- **Météo** (`searchWeather()`) : géocodage ville → prévisions 5 jours

**Extraction de paramètres** (`lib/features/chat/data/travel_params_parser.dart` — source unique ADR-029) :
- `TravelParamsParser.parseFlightParams()` : 2-stage parsing (original → sanitize stop words → capitalize → retry)
- 4 patterns (A/B/C/D) : hyphenated/space-separated cities, text/numeric dates
- Regex mois **6 langues** (FR/EN/ES/DE/IT/PT) — surensemble des anciens chemins FR/EN
- `normalizeDate()` **sûr** (`int.parse` + try/catch → retourne la chaîne brute sur invalide)
- Stop words : union 46 (45 ChatNotifier + `'un'` SearchIntentExtractor)
- **Consommateurs** : `ChatNotifier` (sites d'appel + shims statiques rétro-compat) et `SearchIntentExtractor._extractFlightParams` (délègue + repli fuzzy `_extractCities`/`_extractDates`)
- **ATTENTION** : raw strings Dart (`r'...'`) n'interpolent PAS les variables → utiliser concaténation

**Injection contexte IA** (`_buildStream()`):
- `enhancedContext` passé comme paramètre, injecté comme message système AVANT l'historique
- Instruction explicite : "Ne dis JAMAIS que tu n'as pas accès aux systèmes de réservation"
- Pattern à suivre pour tout nouveau type : intent → extraction params → fallback → injection → markdown

## Scraping Intelligent (Session V14)

**Backend `/search_smart`** (`backend/agents/search_smart.py`):
1. **Intent classification** : LLM (DeepSeek/OpenRouter) classifie la requête utilisateur en intents : `flights`, `hotels`, `products`, `secondhand`, `restaurants`, `events`, `weather`, `general`
2. **Extraction de paramètres** : villes, dates, condition (reconditionné/occasion), prix max, tri
3. **Construction d'URLs** : comparateurs avec paramètres pré-remplis (Skyscanner, Booking, Back Market, etc.)
4. **Parallel scraping** : BeautifulSoup scrape chaque comparateur en parallèle (~5 sources max)
5. **Agrégation** : résultats structurés (`SmartSearchResult` type: price/card/link) retournés en JSON

## Universal Media Download (Session V17)

**Backend `/download_media`** (`backend/agents/download_service.py`):
- **yt-dlp extraction** : 1000+ sites (YouTube, Vimeo, TikTok, Twitch, etc.)
  - `extract_media(url)` → `type: video` avec `direct_url`, `formats[]`, `title`, `thumbnail`
  - `format_id` / `ext` / `quality` / `resolution` / `has_audio` / `has_video`
- **Page scraper fallback** : BeautifulSoup pour sites sans yt-dlp
  - `<video>` tags, `<source>`, `<iframe>` (YouTube/Vimeo)
  - OpenGraph meta (`og:video`), JSON-LD `VideoObject`
  - `<img>` tags, CSS backgrounds, gallery patterns
- **Usage** : `POST /download_media {url, media_type}`

**Flutter `SearchServiceGlobal.downloadMedia()`** :
- `dio.post()` avec 30s receive timeout
- Called from `_handleSlashDownload()` for video sites (YouTube, Vimeo, etc.)

## Recursive Crawler (Session V17)

**Backend `/crawl`** (`backend/agents/crawl_service.py`):
- **BFS crawling** : queue with `(url, depth)`, max_depth (default 2), max_pages (default 20)
- **Same-domain filter** : optional, enabled by default
- **Extracts per page** :
  - Videos : `<video>`, `<iframe>`, meta tags, JSON-LD, direct `.mp4`/`.webm` links
  - Images : `<img>`, CSS backgrounds, galleries
  - All anchor links for further crawling
- **Deduplication** : global by URL across all pages
- **Usage** : `POST /crawl {url, max_depth, max_pages, same_domain}`

**Flutter `/crawl` slash command** :
- `/_handleSlashCrawl()` → `SearchServiceGlobal.crawl()`
- Displays aggregated results : videos, images, errors
- Stores video links in `_lastLinksForDownload` for bulk `/download`

## Slash Commands Architecture

**29 commands** defined in `slash_commands.dart` :
- **Extension-only** : `scroll`, `open`, `click`, `fill`, `screenshot`, `back`, `forward`, `forms`, `tables`, `media`, `autofill`, `inspect`, `highlight`, `waitfor`, `monitor`, `translate`, `searchpage`
- **Universal (cross-platform)** : `download`, `links`, `pdf`, `summarize`, `extract`, `metadata`, `export`, `docgen`, `scrape`, `crawl`
- **Script IA (backend)** : `scrape-script` (scraping via script Python généré par IA), `exec` (exécution script Python générique), `api-fetch` (appel API REST + transformation JSON)

**Routing logic** (`_handleSlashCommand()` in `chat_notifier.dart`):
1. Parse command + args via `SlashCommands.parse()`
2. Check if universal → call handler directly (works on mobile/web/extension)
3. If extension-only → check `bridge.isExtension`, return error on mobile
4. Universal commands with URL arg → try backend first, fallback to extension DOM

**Known limitations** (V17):
- `/download https://youtube.com/@channel` → yt-dlp times out on channel pages (fix: use per-video URLs)
- `/links video` on YouTube → DOM extraction fails (SPA), backend fallback works but slow
- Extension requires backend tunnel (ngrok/localtunnel) for universal commands to work outside localhost

**Backend `/scrape`** (`backend/agents/search_engine.py:scrape_url()`):
- Auto-extraction : metadata (title, OG tags), prix (regex `\d[\.,]\d{2}\s?[€$£]`), cartes produits (class heuristiques), liens
- Sélecteurs CSS personnalisés via paramètre `selectors` : `{"prix": ".price", "titre": "h1"}`
- Nettoyage : suppression script/style/nav/footer/header avant parsing
- User-Agent desktop + follow redirects

**Dart `SearchServiceGlobal`** (`lib/features/chat/data/search_service_global.dart`):
- `search(query)` → appelle `/search_smart` → `SmartSearchResponse`
- `scrape(url, selectors)` → appelle `/scrape` → `Map<String, dynamic>`
- `formatMarkdown(response, query)` → formatte selon l'intent :
  - `flights` : tableaux prix + résultats + liens
  - `hotels` : tableau | Établissement | Prix |
  - `products` / `secondhand` : tableau | Produit | Prix | Source |
  - `restaurants` / `events` : listes avec snippets
  - `weather` : 3 cartes météo
  - `general` : liste résultats + sources

**Slash commands universels** (`lib/features/chat/presentation/chat_notifier.dart`):
- `/scrape <url> [selectors_json]` — scrape n'importe quelle URL
- `/summarize <url>` — scrape + résume le contenu extrait
- `/extract <url> [selector]` — extrait un sélecteur CSS spécifique
- `/links <url> [type]` — liste les liens trouvés (filtrable par video/image/audio/document)
- `/metadata <url>` — extrait les balises meta (title, description, OG, auteur)
- **Règle** : si l'argument commence par `http`, le backend `/scrape` est appelé. Sinon, comportement DOM local (extension uniquement).

**Script IA** (`lib/features/chat/data/script_execution_service.dart` + `backend/agents/script_executor.py`):
- `scrapeWithScript(url, instruction)` → DeepSeek génère un script Python de scraping sur mesure, backend l'exécute
- `execWithInstruction(instruction)` → DeepSeek génère un script Python générique (calculs, API calls, transformations)
- `apiFetchWithScript(url, instruction)` → fetch API REST + DeepSeek génère un script de transformation JSON → markdown
- Commandes slash : `/scrape-script <url> <instruction>`, `/exec <instruction>`, `/api-fetch <url> <instruction>`

## Multilingue

**LanguageService** (`lib/core/language/language_service.dart`):
- 6 langues : FR, EN, ES, DE, IT, PT
- `classifySearchIntent()` : patterns multilingues pour vols, hôtels, produits, météo
- `parseMonth()` : noms de mois dans les 6 langues
- Paramètres API localisés : OWM `lang`, SerpAPI `hl`/`gl`

**Interface utilisateur** :
- Sélecteur de langue dans `SettingsScreen` (DropdownButton)
- `toNaturalLanguage()` dans `slash_commands.dart` délègue à `LanguageService`

## Chat UI — Liens cliquables

**MarkdownBody** (`lib/features/chat/presentation/chat_bubble.dart`):
- `onTapLink` callback → `canLaunchUrl()` → `launchUrl(mode: externalApplication)`
- Les URLs dans les réponses IA sont cliquables directement

## Chrome Extension Specifics

**Build Process** (`scripts/build_extension.sh`):
1. Flutter Web build with `--pwa-strategy=none`
2. Copies manifest.json, background.js, content_script.js, speech_bridge.js, extension_bridge.js, corely_init.js, icons
3. Patches `<base href="/">` → `./` in output HTML
4. Removes Flutter service worker JS file
5. Strips SW references from index.html
6. Patches flutter_bootstrap.js (Python3):
   - Removes `serviceWorkerSettings` from `_flutter.loader.load()`
   - Neutralizes `loadServiceWorker()` with `if(1)return Promise.resolve()`
   - Adds `"useLocalCanvasKit":true` to `_flutter.buildConfig` (forces local canvaskit/ instead of CDN)
7. Patches manifest.json: removes `"type": "module"`, strips `blob:` from CSP, adds `*.wasm`
8. Creates ZIP for Chrome Web Store

**CRITICAL — Manifest V3 CSP constraints**:
- No inline `<script>` tags in HTML (blocked by `script-src 'self'`) → all JS must be external files
- No CDN scripts (blocked by `script-src 'self'`) → CanvasKit must be local (`useLocalCanvasKit:true` in buildConfig)
- No Service Worker registration (conflicts with extension's background SW) → neutralized in bootstrap
- `corely_init.js` contains all inline JS (dispatchCustomEvent, flutter-first-frame listener, diagnostics)

**Manifest V3** (`web/manifest.json`):
- No `"type": "module"` (required for content scripts)
- CSP: `script-src 'self' 'wasm-unsafe-eval'; object-src 'self';` (no `blob:`, no `worker-src`)
- `web_accessible_resources` includes `*.wasm`, `*.js`, `*.dart.js`, `assets/**`, `canvaskit/**`
- Side panel + popup UI
- Background service worker
- Content scripts for all URLs
- Host permissions for AI APIs + Firebase
- Permissions : storage, sidePanel, contextMenus, scripting, activeTab

**Limitations actuelles de l'extension** :
- speech_bridge.js gère STT + TTS basique via Web Speech API (pas de OpenRouter TTS audio)
- Pas de document offscreen pour audio playback en Manifest V3
- `content_script.js` ne fait que capturer la sélection de texte
- [x] Commandes slash : 24 commandes fonctionnelles via extension_bridge.js → background.js → dom_actions.js (corrigé session V8)
- [x] Résumé de page : SUMMARIZE_PAGE action implémentée
- [x] Navigation : OPEN_URL, NAVIGATE_BACK/FORWARD, SCROLL fonctionnels

**Riverpod pitfalls (important)**:
- **Ne PAS modifier `state` dans un `Notifier.build()`** — Riverpod interdit la modification de `state` pendant la construction. Retourner directement l'état initial au lieu de `state = state.copyWith(...)`.
- **ConsentBanner.showIfNeeded()** — Nécessite un `BuildContext` descendant du `Navigator`. Utiliser `rootNavigatorKey.currentContext` du GoRouter, PAS le context de `CorelyApp.build()`.
- **AsyncValue.value!** — Toujours utiliser `valueOrNull` avec un null check au lieu de `.value!`. Les transitions d'état Riverpod peuvent temporairement rendre `value` null même quand `hasValue` est true.

## Firebase Structure

**Collections** (Firestore):
- `users` — User profiles, quota tracking
- `chats` / `conversations` — Message history (real-time sync via snapshots)
- `projects` — Pro user projects

**Cloud Functions** (`functions/src/`):
- `checkQuota` : rate limiting (100 req/day test)
- `stripeWebhook` : Stripe payment webhooks

**Security**: Rules enforce user-owned data access

**Demo Mode**: When `isDemoMode = true`, all Firebase services replaced with in-memory mocks. App runs fully offline.

## Error Handling

**Exceptions** (`ai_client.dart`):
- `AiException` : porte le `statusCode` HTTP + message
- 401 → "Clé API invalide", 429 → "Trop de requêtes", 400 → "Erreur API..."

**Formatage utilisateur** (`chat_notifier.dart:_formatAiError()`):
- Erreurs "image" / "image_url" → message clair (pas de JSON brut)
- Erreurs 429 → "Limite de requêtes atteinte"
- Clé API → message conservé tel quel
- Autres → "Erreur IA. Réessayez."

**isStreaming** : forcé à `false` dans TOUS les blocs catch + finally

## Known Limitations / TODO

### ✅ Résolus — Sessions récentes
- [x] Extension Chrome : démarrage cassé (13 bugs corrigés, conditional imports, CSP, base href, SW)
- [x] Extension Chrome : 3 bugs CSP critiques (inline scripts → corely_init.js, CanvasKit CDN → useLocalCanvasKit:true, SW registration neutralisée)
- [x] Extension Chrome : crash ConsentBanner / VoiceServiceNotifier / AsyncValue.value! — tous corrigés
- [x] Logos/icons : remplacés par logo Corely "C" (toutes tailles)
- [x] Comportement conversationnel : recherche web seulement sur questions factuelles/temporelles
- [x] Settings : prompt système personnalisable avec sauvegarde
- [x] Cache recherche web : LRU + SHA-256 + TTL 15 min
- [x] Interruption vocale (barge-in) pendant le TTS : `SpeechFinalEvent` > 3 mots → `stopSpeaking()` + nouveau tour ; pause post-TTS 1200ms (anti-echo + réinit STT Android)
- [x] Extension Chrome : commandes slash (/download, /links, etc.) fonctionnent
- [x] Recherche enrichie : vols, hôtels, produits, météo fonctionnels sans clés API
- [x] Intégration multilingue : 6 langues, patterns de recherche localisés, noms de mois traduits
- [x] Liens cliquables dans le chat : `onTapLink` → `url_launcher`
- [x] TTS vitesse ajustée (OpenRouter 1.0, flutter_tts adaptatif)
- [x] Généralisation parsing paramètres : concerts, musées, restaurants, locations, occasions, forfaits
- [x] Mapping codes IATA pour recherches de vols (~300 aéroports, fuzzy matching)
- [x] Extension Chrome : microphone en mode vocal (speech_bridge.js v2)
- [x] Architecture search-first : liens directs comparateurs avec paramètres pré-remplis
- [x] **CRITIQUE V13** : Recherche avancée robuste — SearchService multi-endpoint + patterns fallback
- [x] **CRITIQUE V12** : Commandes slash fonctionnelles — extension_bridge filtre + flux DOM complet
- [x] **CRITIQUE V12** : Images + PDFs chargés correctement
- [x] **CRITIQUE V14** : Scraping intelligent cross-plateforme — `/scrape`, `/summarize <url>`, `/extract <url>`, `/links <url>`, `/metadata <url>` fonctionnent sur mobile/web/extension via backend `/scrape` et `/search_smart`
- [x] **CRITIQUE V16** : TTS markdown sanitization — `cleanMarkdown()` strippe sources, citations, tableaux, raisonnements, et artefacts markdown résiduels (* - _ | [ ] # >) pour un discours naturel
- [x] **CRITIQUE V16** : Quota retry — `_PendingMessage` + `retryPendingMessage()` pour re-soumettre automatiquement la requête originale après vidéo récompensée
- [x] **CRITIQUE V16** : Notification icon — `ic_notification.xml` + `keep.xml` empêche R8 de le supprimer
- [x] **CRITIQUE V16** : Slash commands overhaul — traductions `scrape`/`docgen`, messages assistant persistants (Firestore), annonces pré-exécution, erreurs persistantes au lieu de SnackBar
- [x] **CRITIQUE V16** : Monetization fixes — AdMob retry loading, GoRouter paywall navigation, Stripe fallback, algo progressif `AdRewardTracker` (tiers 0/1/2 = 1→2→3 vidéos)
- [x] **CRITIQUE V16** : Retention services — `StreakService` (+2 bonus après 3 jours), `UserProfileService` (nom + intérêts), `UsageStatsService` (messages + temps économisé), `DailyQuestionService` (push 9h local)
- [x] **CRITIQUE Bloc 1** : RCE non authentifié éliminé — auth two-tier `CLIENT_API_KEY` (soft, `X-API-Key`, transition-open) sur routes APK-facing + `API_SECRET_KEY` (opérateur, fail-closed 403) sur RCE/admin (`/script/exec`, `/config/*`, `/agent/*`, `/insights/audit`) ; `hmac.compare_digest` constant-time ; `/chat/completions` = Firebase JWT (ADR-027)
- [x] **CRITIQUE Bloc 1** : SSRF comblé — `backend/core/net_guard.py` (`assert_safe_url` + `safe_get`/`safe_get_sync`, blocklist loopback/privé/cloud-metadata `169.254.169.254`, re-validation per-hop, max 4 redirects) câblé sur scrape/crawl/download/search_smart/script_executor (ADR-027)
- [x] **CRITIQUE Bloc 1** : Sandbox scripts IA — validateur AST `_ScriptValidator` (`_ALLOWED_MODULES`/`_DANGEROUS_NAMES`/`_DANGEROUS_ATTRS`) + env minimal `_SANDBOX_ENV` (pas de clés héritées) + `tempfile.TemporaryDirectory` cwd + timeout 15s dans `script_executor.py` (ADR-027)
- [x] **CRITIQUE Bloc 1** : Injection shell `config_agent.py` éliminée — `asyncio.create_subprocess_exec` (argv, pas de shell) + `_validate_domain` strict (ADR-027)
- [x] **CRITIQUE Bloc 1** : Durcissement conteneurs/compose — non-root (uid 10001 backend, 10002 codewhale), `docker.sock` retiré, port Ollama 11434 non publié, CORS serré (`allow_credentials = not wildcard`) (ADR-027)
- [x] **CRITIQUE Bloc 1** : Fuite `.env` APK colmatée — `.env` retiré des `assets` `pubspec.yaml` (shipait clé opérateur + clé OpenRouter payante + Stripe webhook) ; clés client via `--dart-define` uniquement ; `main.dart` garde `dotenv.load` en try/catch (ADR-027)
- [x] **CRITIQUE Bloc 1** : Secret opérateur commité retiré — `scripts/server_init.sh` ne contient plus la valeur `311788a1…` → génération `openssl rand -hex 32` (placeholders post-heredoc) ; `.env.example` sépare client/VPS-only (ADR-027)
- [x] **CRITIQUE Bloc 2** : Machine à états vocale à token de génération — `_generation` incrémenté à chaque frontière de tour (start/barge-in/stop/dispose) ; les continuations async (reopen micro post-TTS, délai 1200ms) capturent `gen` et bail si obsolète → fini les races où un speak supplanté rouvrait le micro ou écrasait l'état (ADR-028)
- [x] **CRITIQUE Bloc 2** : Barge-in « repeat » réparé — bump génération + libération du garde `_isProcessingResponse` avant dispatcher ; le speak d'origine bail via le check de génération (ne rouvre pas le micro) ; `_respeakLastAssistant()` procède au lieu d'être skip silencieusement (ADR-028)
- [x] **CRITIQUE Bloc 2** : Reset systématique des drapeaux stale — `_resetTurnState()` (bump génération + clear `_isProcessingResponse`/`_lastProcessedTranscript`/`_lastRequestTime`/`_sttFailureCount`) appelé à start/stop/dispose → anti-pollution inter-sessions (ADR-028)
- [x] **CRITIQUE Bloc 2** : Sync erreur STT — nouveau `onSttError` stream (`voice_service.dart`) ; `_onSttError` compte les échecs, tente reprise (redémarrage micro 400ms), bascule en error après 3 (anti-boucle) ; reset compteur sur speech final (ADR-028)
- [x] **CRITIQUE Bloc 2** : `BargeInIntent.stop` corrigé — « chut »/« arrête »/« pause » coupe le TTS et repasse en listening via `_returnToListening()` sans round-trip LLM (au lieu d'envoyer le mot au LLM et déclencher une nouvelle réponse) (ADR-028)
- [x] **CRITIQUE Bloc 2** : `_lastProcessedTime` null-check défensif (plus de `!` forcé) (ADR-028)
- [x] **CRITIQUE Bloc 3 (1/≥5)** : Extraction `TravelParamsParser` — source unique pour le parsing vol/météo (unifie les deux parsers parallèles `ChatNotifier` FR/EN + `SearchIntentExtractor` 6-lang). Regex mois 6 langues (surensemble), `normalizeDate` sûr (`int.parse`+try/catch), stop-words union (46). Shims statiques `ChatNotifier.*` préservés (rétro-compat tests). `chat_notifier.dart` 4270→4042 lignes, 3 méthodes mortes supprimées de `search_intent_extractor.dart`. Bug latent `normalizeDate` padLeft éliminé (ADR-029).
- [x] **CRITIQUE Bloc 3 (2/≥5)** : Extraction `WebSearchTrigger` — gatekeeper de recherche web (`needsWebSearch` + `extractSearchQuery`, pures multilingues) sorti du god object vers `data/web_search_trigger.dart`. 3 sites d'appel migrés, 2 méthodes privées supprimées (pas de shim — privées, 0 réf test). `chat_notifier.dart` 4042→3943 (−99 ; cumul −327). Réévaluation : `QuotaService` déjà extrait (services dédiés existent), `classifyTask` non dupliqué (unique dans `model_router.dart`) (ADR-030).
- [x] **CRITIQUE Bloc 4** : Tests critiques des fonctions pures extraites — 68 tests net-new (`travel_params_parser_test.dart` 46 + `web_search_trigger_test.dart` 22). La 1ʳᵉ exécution a exposé **3 bugs réels pré-existants** (tous antérieurs à l'extraction), corrigés : (1) absorption mot-clé capitalisé (`Flug Berlin` capturé comme ville) → `_travelKeywords` + `_stripLeadingKeyword` post-traitement ; (2) dérive regex↔map PT `setembro`→janvier (`monthPattern` capturait mais la map `parseMonth` n'avait pas l'entry) → `'setembro': 9` + commentaire contrat regex↔map dans `language_service.dart` ; (3) repli météo minuscule `météo paris`→null — cause racine : `\b` ECMAScript capitalise **chaque** accent (`\w` exclut accents → `météo`→`MÉTÉO` casse le match `[Mm]étéo`) → `_capitalizeWords` (`(^|[\s-])([a-zà-ÿ])` préserve délimiteur). Vérif : **68/68** + régression **33/33** (`enhanced_search_test` 28 shims `ChatNotifier.*` + `search_service_parsing_test` 5). `flutter analyze` compile OK (0 err/0 warning, 162 lints info pré-existants) — limite « SDK 644 » des ADR-029/030 **levée** (chmod +x dart-sdk+artifacts) (ADR-029).
- [x] **CRITIQUE Bloc 5** : 6 sites d'I/O bloquant sortis de l'event loop async (ADR-031) — `script_executor.execute_script` (`subprocess.run(timeout=15)` → `asyncio.create_subprocess_exec` + `wait_for(communicate)` + `proc.kill()`+`await proc.wait()` sur `asyncio.TimeoutError`, reap + garde `ProcessLookupError` → **zéro zombie**) ; `search_engine.scrape_url` + `search_smart._scrape_page` (parse BeautifulSoup CPU-bound → helpers module-level sync `_extract_scrape_data`/`_parse_scraped_page` + `asyncio.to_thread`) ; `main.py` routes `/download_media`+`/crawl` (stopgap `asyncio.to_thread`, signatures préservées). `config_agent.exec_migrate_docker_data` (`open`/`os.makedirs`) **différé avec rationale** (I/O sub-ms entre `systemctl` minute-longs déjà awaited = cérémonie zéro gain). **Bug découvert** : 1ʳᵉ implémentation `except asyncio.TimeoutExpired:` → `asyncio.TimeoutExpired` **n'existe pas** (`wait_for` lève `asyncio.TimeoutError`, alias du builtin `TimeoutError` ; `TimeoutExpired` = API sync `subprocess` only) → `AttributeError` catché par `except Exception` + `proc.kill()` jamais atteint → **zombie leak 100 % CPU**. Test `test_execute_script_does_not_block_event_loop` + check zombie post-run ont révélé le bug ; corrigé + durci. **Vérif : 12/12** (`test_async_io.py`) + suite backend 20 passed (2 failed + 2 collection errors **pré-existants**, hors-périmètre) + **0 zombie** post-run. ⚠️ Follow-up : réécriture full-async `DownloadService`/`CrawlService` (httpx.AsyncClient + asyncio.gather) — le stopgap `asyncio.to_thread` sature le pool à 32 downloads concurrents (refactor des 2 services = bloc séparé).
- [x] **Bug TTS liaison `bien`** : `phonetic_liaison_service.dart` — la règle de liaison `bien aimé`→`bien naimé` matchait `\bben\b` (stem phonétique) au lieu de `\bbien\b` (forme orthographique réelle) → la règle ne se déclenchait **jamais** sur le texte en entrée (`bien aimé` restait inchangé). Fix : regex `\bbien\b` + commentaire de contrat. (La règle `rien` adjacente utilisait déjà `\brien\b` correctement.) Test `phonetic_liaison_service_test.dart` 23/23 vert.
- [x] **Flutter test suite red→green (790/790)** : 11 échecs préexistants résolus — (1) `model_router_test` vision-aware null fallback ; (2) `slash_commands_test` count 26→30 + `containsAll` +6 noms (docgen/scrape/scrape-script/exec/api-fetch/crawl) ; (3) `slash_command_handlers_test` exclusion `nonBrowserCommands` (scrape-script/exec/api-fetch/crawl = backend/universel, pas des actions navigateur) ; (4) `chat_bubble_test` avatar assistant = `Container` circulaire brandé (dégradé Cofely + lettre « C »), pas un `CircleAvatar` Material — test stale aligné (`find.text('C')`) ; (5) `login_screen_test` 4 finders `ElevatedButton`→`FilledButton` (M3, `login_screen.dart:242`). Suite backend **39/39 vert** également (template tests supprimés + chat-mock résolus). **Artifact d'environnement de test** : `flutter test` (Flutter 3.41.9) ne bundle pas le shader framework `shaders/ink_sparkle.frag` → `ui.FragmentProgram.fromAsset` (native asset store, PAS le channel Dart `flutter/assets`/`rootBundle` → inmockable depuis Dart) lève une erreur async non gérée (`.then()` sans `.catchError`) sur le 1ᵉʳ tap InkWell/InkResponse d'un isolate, fail le test ; `_initCalled` garde un appel/isolate. Helper réutilisable `test/helpers/widget_test_shaders.dart` (`warmUpInkSparkleShader`) : déclenche le chargement une fois dans une `runZonedGuarded` (avale l'erreur) avec un InkWell **hittable** (SizedBox 80×80 + Text('X'), pas SizedBox() 0×0 non-hittable) → `_initCalled=true`. À appeler comme **1ᵉʳ `testWidgets`** de tout fichier de test widget qui tappe un bouton Material (1 warm-up par fichier = 1 par isolate).
- [x] **Bloc 6 cluster 4 — Extraction `chat_text_helpers` (ADR-029 suite)** : 7 helpers texte purs extraits de `chat_notifier.dart` (3943→3862, −81 lignes ; cumulé −408 sur 4 clusters) vers `lib/features/chat/data/chat_text_helpers.dart` (`normalizeDocFormat`, `extractDocumentTitle`, `escapeForJson`, `stripActionCommands`, `parseJsonLoose`, `buildProductSearchQuery`, `formatAiError`). Test miroir `chat_text_helpers_test.dart` 39/39 vert. 7 sites d'appel migrés. Refactor via script Python audité `/tmp/refactor_chat_notifier.py` (asserts count==1, write gated).
- [x] **Bug parsing vols réel (corrigé + couvert)** : `parseFlightParams("trouve un billet paris-londre direct du 29/05")` retournait `null` (le repli `_sanitizeFlightQuery`+`_capitalizeWords` produisait `Paris-Londre 29/05`, `du` strippé par les stop-words, qu'**aucun pattern** ne matchait). Fix : pattern B relaxé `(?:d[ue]|le)\s+`→`(?:d[ue]|le)?\s*` (`travel_params_parser.dart:229-240`). Tests : 47/47 + shims 28/28 vert. ⚠️ **Limite connue** : round-trip lowercase `paris-londre du 29/05 au 02/06` — `au`/`retour` aussi strippés par `_sanitizeFlightQuery` → date de retour perdue sur le chemin sanitize. Fix propre = extraire les dates **avant** sanitization (à faire en session runtime).
- [x] **Bloc Tâche #14 — Extension Chrome (vérif statique + fix réel)** : build vert (`bash scripts/build_extension.sh` exit 0) + 7 patches du script tous vérifiés dans les artefacts + contrat action Dart↔JS cohérent (22 `BrowserActionType` tous routés dans `web/background.js` ; sous-ensemble DOM 13 actions → `web/dom_actions.js`). **Fix** : `web/manifest.json` déclarait permission `offscreen` + `offscreen.html`/`offscreen.js` en WAR, MAIS 0 code n'utilise `chrome.offscreen` et les fichiers n'existent pas (ajout V10 a822434b, jamais implémenté) → retiré permission + WAR refs. **Runtime = device-only** : chrome-devtools MCP ne peut pas unpacked-load (file picker + chrome:// restrictions).

### 🔴 À faire — Priorité CRITIQUE (prochaine session)
- [ ] **Tester mode vocal V16 sur Xiaomi 12** : 5 tours complets, pas de monologue, barge-in >3 mots (repeat/topicChange/stop), reprise micro après erreur STT, TTS fluide sans sources/asterisques, quota retry auto après vidéo. La machine à états est désormais robuste (token de génération + sync erreur STT — ADR-028) ; reste à valider sur device. **Session 68d36b15 n'a pas pu** : adb ne voit pas le Xiaomi 12 (USB debugging / autorisation / câble).
- [x] **Déployer le backend** : ✅ Déployé 2026-06-13 sur `api.zentic.fr` (Hetzner VPS). Stack : Caddy + Backend FastAPI + CodeWhale Agent + Redis + Ollama + ttyd. Voir `DEPLOY.md` pour les détails.
- [x] **Parsing vols réel (unit)** : "trouve un billet paris-londre direct du 29/05", requêtes lowercase + mots parasites — **corrigé + couvert par `travel_params_parser_test.dart`** (régression reproduite puis fix). Le repli `_sanitizeFlightQuery`+`_capitalizeWords` produisait `Paris-Londre 29/05` (`du` strippé par les stop-words) qu'aucun pattern ne matchait → pattern B relaxé (`du`/`le` optionnel, symétrique à pattern D qui l'était déjà pour le cas espace). ⚠️ **Limite connue** : round-trip lowercase (`paris-londre du 29/05 au 02/06`) — `au`/`retour` sont aussi strippés par `_sanitizeFlightQuery` (sinon `au`→`Au` est pris pour une ville) → date de retour perdue sur le chemin sanitize ; fix propre = extraire les dates **avant** sanitization (à faire en session runtime, pas à risque de toucher l'extraction de villes).
- [ ] **Parsing vols réel (e2e device)** : valider le flux chat complet sur device (slash command / recherche enrichie) avec la requête lowercase ci-dessus + le cas round-trip.
- [ ] **Tester slash commands mobile** : `/scrape https://example.com`, `/summarize <url>`, `/links <url>` avec backend cloud `api.zentic.fr`. Build requis : `flutter build apk --dart-define=BACKEND_URL=https://api.zentic.fr --dart-define=CLIENT_API_KEY=<clé>` (ADR-027) — sans `CLIENT_API_KEY` le backend reste transition-open côté APK mais le header `X-API-Key` n'est pas envoyé.
- [ ] **TTS qualité** : évaluer si le nettoyage markdown suffit ou si des artefacts persistent (tableaux complexes, emojis non standards)
- [ ] **Terminal web** : changer le mot de passe `TTYD_PASS` par défaut (`changeme`) dans `docker-compose.yml` sur le VPS, rebuild et redémarrer
- [ ] **Rotation `API_SECRET_KEY`** : une valeur réelle (`311788a14ea7b929c5280f074a8b33ecafe361de59e3ab673c5194d9516470ea`) était commitée dans `scripts/server_init.sh` (retirée du repo — ADR-027). Si encore live sur le VPS `.env`, la tourner + `docker compose up -d --force-recreate backend codewhale-agent`. Git history la contient encore → `git filter-repo` si purge requise. Définir aussi `CLIENT_API_KEY` sur le VPS (`server_init.sh` la génère pour nouveaux deploys ; deploy existant = ajout manuel).

### 🟡 À faire — Priorité moyenne
- [ ] Analyse fichiers TXT/MD : tester l'injection comme contexte conversationnel
- [ ] Vision DeepSeek : `deepseek-chat` peut rejeter `image_url` selon version API
- [ ] Extension Chrome : TTS audio — speech_bridge.js v2 a le support, OpenRouter TTS non supporté (Manifest V3 sans offscreen)
- [ ] Extension Chrome : résumé de page, extraction média — actions navigateur existent mais non testées
- [x] Tests non-régression `TravelParamsParser` : `parseFlightParams` (4 patterns + cas négatifs), `isValidCityPair`, `extractCity` (4 patterns + repli minuscules), `extractZipCode`, `normalizeDate`, `parseMonth` (6 langues) — 68 tests + régression `enhanced_search_test.dart` (28 shims `ChatNotifier.*`) + `search_service_parsing_test.dart` (5) = 101/101 verts. Shims préservés, `enhanced_search_test.dart` inchangé (ADR-029). Limite « SDK 644 » levée.
- [x] IATA fuzzy per-word : tests non-régression du mapping ~300 aéroports — couvert par `test/features/chat/data/iata_codes_test.dart` (~37 tests, 9 groupes : lookup direct tous continents, casse, accents/disambiguïsation, fuzzy bidirectionnel, per-word, prefix 5 chars, quirks ordre-map, null/empty, stabilité 20 codes idempotente). 2 bugs module réels découverts & fixés : (1) `resolveIataCode('')`→`'PAR'` (fuzzy `contains("")` matche tout) → garde `if (key.isEmpty) return null` ; (2) `resolveIataCode('ab')`→`'SAW'` → garde fuzzy `if (key.length >= 3)`. Module = `lib/features/chat/data/iata_codes.dart` (séparé de `TravelParamsParser`).
- [x] Recherche hôtels : `searchHotels` checkIn/checkOut/guests — ✅ vérifié câblé : extraction `search_intent_extractor.dart:320-327,412-419` (dates→checkIn/checkOut, `_extractGuests`) + call-chain `chat_notifier.dart:3659-3666` (`searchHotels(..., checkIn: params?.checkIn, checkOut: params?.checkOut, guests: params?.guests)`, 2ᵉ site `3691-3693`) + `enhanced_search_service.dart:432-483` (accepte + utilise `ci = checkIn ?? ''`). TODO périmé, pas de bug.
- [x] **Quota upload tier-aware (latent bug, découvert session 68d36b15)** — ✅ Corrigé (logique + tests unitaires) : la limite d'upload était **5 MB pour TOUS les tiers** au lieu de « 5 MB gratuit, 50 MB Pro ». Fix : `message.dart` ajoute `proMaxAttachmentsTotalBytes = 50*1024*1024` + helper `attachmentLimitFor({required bool isPro})` (50MB Pro / 5MB free) ; `maxAttachmentsTotalBytes` (5MB) + `exceedsAttachmentLimit` conservés (tests free-tier). Garde agrégée tier-aware en tête de `sendMessage` (`chat_notifier.dart`) + `_handleImagePick`/`_handleFilePick` (`chat_screen.dart`) câblés au helper (SnackBar dynamique `${limitMB}MB`). `isPro` lu via `ref.read(isProProvider.future).catchError((_) => false)` (JAMAIS `.value` — AsyncValue peut être null mid-transition). Test `message_test.dart` `attachmentLimitFor is tier-aware` (50MB/5MB). ⚠️ **Reste device-only** : smoke-test Xiaomi 12 (build APK `--dart-define` + upload réel 50MB Pro vs 5MB free, comportement UI stateful) — adb ne voit pas le device.
- [x] **Réduction analyzer warnings 89→0** (session 68d36b15, ADR-032) : 89 warnings éliminés en 6 incréments vérifiés verts (0 err / 0 warn final / **790/790** tests verts). **Incrément 1 (89→53, 36)** : 21 `unused_import` + 13 `unused_local_variable` + 2 `dead_null_aware_expression`. **Incrément 2 (53→45, 8)** : 5 `unused_field` + 1 `unnecessary_null_comparison` + 1 `body_might_complete_normally_catch_error` + 1 `inference_failure_on_untyped_parameter` cascade. **Incrément 3 (45→41, 4)** : 3 `Function`→`void Function` (deep_link callbacks) + 1 `js.allowInterop((event))`→`(dynamic event)`. **⚠️ Incident cascade (leçon)** : `Future.delayed<void>(...)` causait 4 `wrong_number_of_type_arguments_constructor` ERROR — `Future.delayed` N'est PAS générique (contrairement à `Dio.get<T>`/`showDialog<T>`) → revert des 4 sites ; leçon = **vérifier la genericité d'un constructeur avant d'annoter**. **Incrément 4 (41→24, 17)** : 17 `inference_failure_on_function_invocation` sur Dio `get`/`post`/`fetch` + Flutter `showDialog` — clusters génériques réels (SerpAPI `get<Map<String,dynamic>>` ×9, Dio `fetch<dynamic>` ×2, `post<dynamic>`, weather `get<dynamic>` ×4, `showDialog<void>`). Zéro behavior change. **Incrément 5 (24→17, 7)** : 7 `strict_raw_type` sûrs — `StreamSubscription<Uri>?` + 6 tests `isA<Map<dynamic, dynamic>>()` / `isA<List<dynamic>>()`. **Incrément 6 (17→0)** : 12 `strict_raw_type` `chat_notifier` → `.cast<Map<dynamic, dynamic>>()` / `.whereType<Map<dynamic, dynamic>>()` / `.cast<List<dynamic>>()` (covariant, zéro behavior change) ; 1 `_feedback` `unused_field` → retrait du **wiring mort** (`_learningRepo`/`_feedback` init + imports retirés du god object — `_knowledgeBase`/`_consentData`/`_insights` LIVE conservés) ; 4 `Future.delayed` false-positives → `// ignore: inference_failure_on_instance_creation, Future.delayed n'est pas générique en Dart 3.41 (false-positive)`. **État final : 0 err / 0 warn / 790 tests verts.** Les 4416 `info` lints restants sont des préférences de style pré-existantes (hors périmètre). ⚠️ **Orphelins supprimés** : `feedback_collector.dart` (138 L) + `learning_repository.dart` (165 L) — supprimés sur instruction utilisateur explicite. Méthode : **Edit tool atomique** > script Python (le Python a corrompu `chat_screen.dart` à 0 bytes — récupéré via `git checkout HEAD`). Leçon : pour mutation multi-fichier dans un god-object, le Edit tool atomique est plus sûr.
- [ ] Retention UI : afficher les streaks, stats d'usage, et question du jour dans l'écran de profil/paramètres
- [x] **Backend full-async (follow-up Bloc 5 / ADR-031)** — ✅ Corrigé : `DownloadService` + `CrawlService` réécrits en `httpx.AsyncClient` + `asyncio.gather` (crawl parallèle batches `_MAX_CONCURRENT=5`). `download_service.py` : `extract_media`/`extract_gallery` async, yt-dlp via `asyncio.create_subprocess_exec` + `sys.executable` (hérite le venv avec yt_dlp installé) + `wait_for(timeout=30)` + `proc.kill()`+`await proc.wait()` sur `asyncio.TimeoutError` (reap `ProcessLookupError`, zéro zombie) ; page scraper via `httpx.AsyncClient`+`safe_get` (garde SSRF async). `crawl_service.py` : `crawl()` async, BFS parallèle race-free (`_fetch_and_parse` async). `main.py` routes `/download_media`+`/crawl` → `await service.*` (stopgap `asyncio.to_thread` retiré). Backend pytest **39/39 vert** (zéro nouveau échec ; les anciens échecs `test_chat_*_mock`/template étaient déjà résolu).
- [x] AdRewardTracker : persister l'état tier entre sessions — Fixed V20 : SharedPreferences avec `ad_videos_watched_today`, `ad_videos_date`, `ad_last_watch_time_ms` + reset quotidien minuit
- [ ] **Quota upload tier-aware e2e Xiaomi 12** : smoke-test device — build APK `--dart-define` + upload réel 50MB Pro vs 5MB free, comportement UI stateful (SnackBar dynamique `${limitMB}MB`). La logique + tests unitaires sont faits ; reste la validation device.
- [ ] **Extension Chrome runtime (chrome://extensions unpacked load)** : la vérif statique + build vert sont faits (7 patches, manifeste honnête sans offscreen) ; reste à charger l'extension dans Chrome et valider device — UI Flutter render popup/sidePanel, slash DOM exec, speech_bridge STT/TTS. chrome-devtools MCP ne peut pas unpacked-load (file picker + chrome:// restrictions).
- [ ] **Parsing vols round-trip lowercase** : fix propre = extraire les dates **avant** `_sanitizeFlightQuery` pour ne pas perdre `au 02/06`/`retour` lors du strip stop-words. À faire en session runtime (pas à risque de toucher l'extraction de villes, mais demande smoke-test sur cas réel).
- [ ] **Audit Phase 2 (post-89→0)** : le god object `chat_notifier.dart` est passé de 4270 → 3862 lignes (−408 sur 4 clusters extraits), mais le fichier reste un god object. Cibles safe restantes : (1) extraction `QuotaService` de la garde `sendMessage` ; (2) `searchHotels`/`searchProducts`/`searchWeather` routeurs en services dédiés ; (3) `_buildStream` (~400 L) décomposition. Haut-risque (stateful runtime) → à ne pas faire en autonomie sans vérif device.

### 🟢 À faire — Priorité basse
- [ ] Synchronisation temps réel des préférences entre mobile et extension
- [ ] Support HEIC/HEIF pour les images
- [ ] OCR pour PDF scannés
- [ ] Firebase Storage pour les images (au lieu de base64)
- [ ] Documents volumineux : tronqués à 15000 caractères dans le contexte system
- [ ] Push notifications : tester `DailyQuestionService` push à 9h00 locale sur Xiaomi 12
- [x] **HAUTE** : Autres types de fichiers (DOCX, XLSX, PPTX) : Fixed V13 : extraction namespace-agnostic (`localName` + `namespaceUri`) sans dépendance au préfixe XML. Fallback texte brut + gestion erreurs XML/ZIP.