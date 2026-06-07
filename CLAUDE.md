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
- `lib/features/monetization/subscription/paywall_screen.dart` → `_mobile` (real paywall) / `_web` (info message)
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
│   └── constants/app_constants.dart      # API URLs, model names, limits, String.fromEnvironment
├── features/
│   ├── auth/                    # FirebaseAuth + email/Google/Apple + mock auth
│   ├── chat/
│   │   ├── data/                # ai_client, search_service, oralize_service, file/image upload, quotas
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
4. Chat → intent classification (`_needsWebSearch()`) → web search only for factual/temporal queries
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
flutter build web --dart-define=DEEPSEEK_API_KEY=sk-xxx --dart-define=OPENROUTER_API_KEY=sk-xxx
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
- **Barge-in par speech final** : `SpeechFinalEvent` détecté pendant `speaking` avec > 3 mots → `stopSpeaking()` + nouveau message LLM
- Pas de redémarrage complexe du micro entre les tours — cycle explicitement géré
- `_speakResponseAndLoop()` : stop micro → TTS → pause anti-echo 500ms → **state = idle** (CRITIQUE : débloque la boucle)
- Max 3 échecs STT consécutifs → état `error` (pas de boucle infinie)
- `_listenWithVad()` : retourne `null` si STT indisponible, `""` si silence
- `_pendingTranscript` protège contre les doublons de callback

**TTS** (`lib/features/chat/presentation/tts_natural_service.dart`):
- **Tier-aware** : OpenRouter TTS réservé aux Pro (`speakNaturally(text, isPro: true)`). Utilisateurs gratuits → flutter_tts natif.
- **Oralize Pass (LLM)** : `OralizeService.oralize()` appelle DeepSeek Flash pour convertir le markdown en texte oral naturel AVANT le TTS. Remplace l'approche regex fragile de `cleanMarkdown`. Coût ~$0.00003/appel, latence ~0.5-1s. Fallback automatique vers `cleanMarkdown` si l'appel LLM échoue.
- **Primaire (mobile Pro)** : OpenRouter TTS (`/audio/speech`) — voix réalistes (nova, shimmer, alloy, echo, fable, onyx)
- **Fallback universel** : flutter_tts natif avec **sélection dynamique de voix** (`getVoices` → meilleure fr-FR neural/premium)
- **Préchauffage** : utterance vide dans `init()` pour réduire la latence de la première phrase
- **Speed adaptatif par émotion** : base `_speechRate = 0.42`, adapté via `emotionTtsConfigs` (neutral 0.52, joyful 0.58, sad 0.46). Court texte (<150 chars) : +5%, long texte : -5%.
- **Chunks intelligents** : max 300 caractères, découpe sur limites de phrases (`.!?`) > clauses (`,;`) > mots. **Jamais au milieu d'un mot.**
- **Pauses naturelles** : 60ms inter-phrase, 350ms inter-paragraphe (anti-robotique)
- OpenRouter TTS speed : 1.0, flutter_tts base pitch : 1.10
- Chaîne : gpt-4o-mini-tts → kokoro-82m (fallback) → flutter_tts (dernier recours)
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

**Intégration chat** (`chat_notifier.dart`):
- `useSearch: false` par défaut (recherche désactivée)
- Classification d'intent `_needsWebSearch()` : déclencheurs factuels/temporels, exclusions créatives/code
- Extraction de requête `_extractSearchQuery()` : supprime salutations, limite longueur
- Recherche déclenchée si `state.useSearch || _needsWebSearch(userMsg.content)`
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

**Extraction de paramètres** (`chat_notifier.dart`):
- `parseFlightParams()` : 2-stage parsing (original → sanitize stop words → capitalize → retry)
- 4 patterns (A/B/C/D) : hyphenated/space-separated cities, text/numeric dates
- `_sanitizeFlightQuery()` : 45 stop words filtrés (vol, billet, avion, aller, retour, etc.)
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
- [x] Interruption vocale (barge-in) pendant le TTS (500ms anti-echo)
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

### 🔴 À faire — Priorité CRITIQUE (prochaine session)
- [ ] **Tester mode vocal V16 sur Xiaomi 12** : 5 tours complets, pas de monologue, barge-in >3 mots, TTS fluide sans sources/asterisques, quota retry auto après vidéo
- [ ] **Déployer le backend** : `bash scripts/deploy_backend.sh` depuis la machine utilisateur (Docker nécessite internet). Cible `api.zentic.fr`.
- [ ] **Tester parsing vols réel** : "trouve un billet paris-londre direct du 29/05", requêtes lowercase + mots parasites
- [ ] **Tester slash commands mobile** : `/scrape https://example.com`, `/summarize <url>`, `/links <url>` avec backend local `192.168.1.38:8000`
- [ ] **TTS qualité** : évaluer si le nettoyage markdown suffit ou si des artefacts persistent (tableaux complexes, emojis non standards)

### 🟡 À faire — Priorité moyenne
- [ ] Analyse fichiers TXT/MD : tester l'injection comme contexte conversationnel
- [ ] Vision DeepSeek : `deepseek-chat` peut rejeter `image_url` selon version API
- [ ] Extension Chrome : TTS audio — speech_bridge.js v2 a le support, OpenRouter TTS non supporté (Manifest V3 sans offscreen)
- [ ] Extension Chrome : résumé de page, extraction média — actions navigateur existent mais non testées
- [ ] Tests non-régression : `_tryParseFlightParamsGeneric`, `_isValidCityPair`, IATA fuzzy per-word
- [ ] Recherche hôtels : `searchHotels` n'utilise pas checkIn/checkOut/guests depuis les params → vérifier passage dans `_performEnhancedSearch`
- [ ] Retention UI : afficher les streaks, stats d'usage, et question du jour dans l'écran de profil/paramètres
- [x] AdRewardTracker : persister l'état tier entre sessions — Fixed V20 : SharedPreferences avec `ad_videos_watched_today`, `ad_videos_date`, `ad_last_watch_time_ms` + reset quotidien minuit

### 🟢 À faire — Priorité basse
- [ ] Synchronisation temps réel des préférences entre mobile et extension
- [ ] Support HEIC/HEIF pour les images
- [ ] OCR pour PDF scannés
- [ ] Firebase Storage pour les images (au lieu de base64)
- [ ] Documents volumineux : tronqués à 15000 caractères dans le contexte system
- [ ] Push notifications : tester `DailyQuestionService` push à 9h00 locale sur Xiaomi 12
- [x] **HAUTE** : Autres types de fichiers (DOCX, XLSX, PPTX) : Fixed V13 : extraction namespace-agnostic (`localName` + `namespaceUri`) sans dépendance au préfixe XML. Fallback texte brut + gestion erreurs XML/ZIP.