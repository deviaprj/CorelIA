# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AironBot is a cross-platform AI chat application (Flutter/Dart) targeting 1M+ users. It includes:
- **Mobile app**: Android/iOS with Firebase Auth, chat, voice input
- **Chrome Extension**: Same codebase, built with Flutter Web + Manifest V3
- **Backend** (optional cloud): Python FastAPI at `api.aironbot.app` with Redis rate limiting
- **Monetization**: AdMob ads (free tier), RevenueCat subscriptions (Pro tier)
- **AI**: DeepSeek-V4-Flash (free text), DeepSeek-Chat (vision fallback), OpenRouter (Pro: Mistral-Large, GPT-4o-mini)

### Contrainte d'autonomie (règle d'or)
L'APK Android et l'extension Chrome doivent être 100% autonomes. Aucun backend local requis. Toutes les fonctionnalités doivent fonctionner via services natifs, appels API directs, ou packages Dart/Flutter embarqués. Le backend cloud (`api.aironbot.app`) est un bonus, pas une dépendance.

## Architecture

**Pattern**: MVVM + Riverpod for state management

**Core Structure**:
```
lib/
├── main.dart                    # Entry point, Firebase/AdMob/RevenueCat init
├── app/                         # Router (go_router) and theme
├── core/                        # Shared: providers, platform_service, secure_storage
│   ├── platform/platform_service.dart  # Detects mobile/extension/web
│   ├── providers/
│   │   ├── app_providers.dart           # Theme, onboarding, search toggle
│   │   └── firebase_providers.dart      # Auth state, Firestore, Messaging
│   └── constants/app_constants.dart      # API URLs, model names, limits
├── features/
│   ├── auth/                    # FirebaseAuth + email/Google/Apple + mock auth
│   ├── chat/
│   │   ├── data/                # ai_client, search_service, file/image upload, quotas
│   │   ├── domain/              # Message, Conversation models
│   │   └── presentation/        # ChatNotifier, voice services, UI screens
│   ├── projects/                # Pro feature: saved projects/folders
│   ├── monetization/            # Ads (AdMob) + subscriptions (RevenueCat)
│   ├── referral/                # Deep links + referral service
│   └── settings/               # Settings screen
└── shared/                      # Widgets, extensions
```

**Backend** (`backend/`):
```
backend/
├── agents/
│   ├── chat_router.py           # AI stream routing (DeepSeek + OpenRouter + tools)
│   └── search_engine.py         # DuckDuckGo + SerpAPI search
├── core/                        # Config, auth, logging
└── schemas/                     # Pydantic models
```

**Chrome Extension** (`web/`):
```
web/
├── manifest.json                # Manifest V3 — sidePanel, contextMenus, scripting
├── background.js                # Service worker — context menu, side panel open
├── content_script.js            # Text selection capture on all pages
├── speech_bridge.js             # Web Speech API bridge (STT only, no TTS)
├── icons/                       # Extension icons
└── index.html                   # Flutter Web bootstrap with CSS spinner
```

**Platform Detection** (`lib/core/platform/platform_service.dart`):
- Detects: mobile Android, mobile iOS, Chrome extension, web
- Critical for conditional Firebase/AdMob/RevenueCat initialization

**State Management**:
- Riverpod providers in `lib/core/providers/app_providers.dart` (theme, onboarding, search toggle)
- Firebase providers in `lib/core/providers/firebase_providers.dart` (auth state, Firestore, Messaging)

**Key Flows**:
1. App start → Firebase init → check onboarding → check auth → route to appropriate screen
2. Chat → Firestore repository → AI client (DeepSeek/OpenRouter) → quota check → response
3. Voice dictation → SpeechToText → text input → ChatNotifier
4. Voice conversation loop → VoiceConversationNotifier (listening → thinking → speaking → idle → repeat)
5. Extension build → Flutter Web + custom manifest.json + service worker removal

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
bash scripts/build_extension.sh   # → aironbot-extension.zip
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

## AI Models & Routing

**DeepSeek** (`lib/features/chat/data/ai_client.dart`):
- `deepseek-v4-flash` — texte (gratuit, par défaut)
- `deepseek-chat` — texte + vision (fallback image si pas OpenRouter)
- Paramètres : `stream`, `max_tokens`, `enable_search`
- Endpoint : `https://api.deepseek.com/v1/chat/completions`

**OpenRouter** (Pro, `lib/features/chat/data/ai_client.dart`):
- `mistralai/mistral-large-2407` — texte Pro
- `openai/gpt-4o-mini` — vision Pro
- Headers obligatoires : `HTTP-Referer`, `X-Title`

**Routage des requêtes** (`_getDirectAiStream` dans `chat_notifier.dart`):
1. **Image détectée** (`content` est un `List`) → `_getVisionStream()`
   - OpenRouter GPT-4o-mini (si clé dispo)
   - Sinon DeepSeek `deepseek-chat` (modèle vision)
   - Sinon `AiException` avec message clair
2. Pro sans image → OpenRouter Mistral
3. Free sans image → DeepSeek V4 Flash

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

## Voice Mode Architecture

**Deux modes distincts** :
1. **Dictée** (bouton micro dans `InputBar`) → `VoiceServiceNotifier.startListening()`
2. **Conversation vocale mains-libres** (toggle "Vocal ON/OFF" dans toolbar) → `VoiceConversationNotifier.startConversation()`

**VoiceServiceNotifier** (`lib/features/chat/presentation/voice_service.dart`):
- Instance `SpeechToText` fraîche créée à chaque `startListening()` via `_createAndInitStt()`
- L'ancienne instance est détruite proprement (`stop()` puis `null`)
- Permission micro : cache `_microphonePermissionGranted`, reset dans `forceReset()`
- Timeout : `listenFor: 120s`, silence : `pauseFor: 10s`
- `listen_mode: ListenMode.dictation` pour écoute continue

**VoiceConversationNotifier** (`lib/features/chat/presentation/voice_conversation_service.dart`):
- Boucle : `listening → thinking → speaking → idle → listening`
- `_speakResponseAndLoop()` : stop micro → TTS → pause anti-echo 500ms → **state = idle** (CRITIQUE : débloque la boucle)
- Max 3 échecs STT consécutifs → état `error` (pas de boucle infinie)
- `_listenWithVad()` : retourne `null` si STT indisponible, `""` si silence
- `_pendingTranscript` protège contre les doublons de callback

**TTS** (`lib/features/chat/presentation/tts_natural_service.dart`):
- `flutter_tts` natif, vitesse par défaut : 0.65
- Nettoyage markdown : strip URLs, citations `[n]`, emojis, formatting
- `speakNaturally()` : nettoye → lit → attend la fin via `Completer`

**Aurora Splash** (`lib/features/chat/presentation/aurora_splash.dart`):
- Overlay plein écran pendant le mode vocal mains-libres
- 15 particules animées avec couleur cyclique
- États : vert=micro (listening), bleu=thinking, orange=speaking, cyan=STT processing
- Affiche le transcript en temps réel pendant l'écoute

**Extension Chrome — Pont vocal** (`web/speech_bridge.js`):
- STT uniquement via `webkitSpeechRecognition`
- Événements CustomEvent : `aironbot_speech_start`, `aironbot_speech_result`, `aironbot_speech_end`, `aironbot_speech_error`
- Pas de pont TTS (à créer)

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
- `useSearch: true` par défaut
- `enable_search: true` dans le body DeepSeek
- Résultats injectés comme message système avant l'historique

## Chrome Extension Specifics

**Build Process** (`scripts/build_extension.sh`):
1. Flutter Web build with `--pwa-strategy=none`
2. Copies manifest.json, background.js, content_script.js, speech_bridge.js, icons
3. Removes Flutter service worker (conflicts with Manifest V3)
4. Patches index.html to remove SW registration
5. Creates ZIP for Chrome Web Store

**Manifest V3** (`web/manifest.json`):
- Side panel + popup UI
- Background service worker
- Content scripts for all URLs
- Host permissions for AI APIs + Firebase
- Permissions : storage, sidePanel, contextMenus, scripting, activeTab

**Limitations actuelles de l'extension** :
- Pas de pont TTS (speech_bridge.js gère uniquement STT)
- Pas de document offscreen pour audio en Manifest V3
- `content_script.js` ne fait que capturer la sélection de texte
- Pas de résumé de page, pas d'extraction média, pas d'autofill

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

- [ ] Analyse fichiers TXT/MD : tester l'injection comme contexte conversationnel
- [ ] Vision DeepSeek : `deepseek-chat` peut rejeter `image_url` selon version API
- [ ] Documents volumineux : tronqués à 15000 caractères dans le contexte system
- [ ] Pas de upload Firebase Storage pour les images (base64 consommé directement)
- [ ] PDF scannés/image : extraction texte uniquement, pas d'OCR
- [ ] Pas de support HEIC/HEIF pour les images
- [ ] Pas de cache pour la recherche web (chaque requête est un appel réseau frais)
- [ ] Extension Chrome : pas de TTS, pas de résumé de page, pas d'extraction média
- [ ] Aurora splash : couleurs toutes noires (effet aurora désactivé), pas de réaction au volume
- [ ] Pas d'interruption vocale (barge-in) pendant le TTS
- [ ] Pas de synchronisation temps réel des préférences entre mobile et extension