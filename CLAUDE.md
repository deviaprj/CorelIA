# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AironBot is a cross-platform AI chat application (Flutter) targeting 1M+ users. It includes:
- **Mobile app**: Android/iOS with Firebase Auth, chat, voice input
- **Chrome Extension**: Same codebase, built with Flutter Web + Manifest V3
- **Monetization**: AdMob ads (free tier), RevenueCat subscriptions (Pro tier)
- **AI**: DeepSeek-V3 (free), OpenRouter for pro models (Mistral/Groq)

## Architecture

**Pattern**: MVVM + Riverpod for state management

**Core Structure**:
```
lib/
├── main.dart                    # Entry point, Firebase/AdMob/RevenueCat init
├── app/                         # Router (go_router) and theme
├── core/                        # Shared: providers, platform_service, secure_storage
├── features/                    # Feature modules (auth, chat, projects, monetization, onboarding, settings)
│   ├── auth/                    # FirebaseAuth + email/Google/Apple login
│   ├── chat/                    # AI client, conversations, voice, quotas
│   ├── projects/                # Pro feature: saved projects/folders
│   ├── monetization/            # Ads (AdMob) + subscriptions (RevenueCat)
│   └── onboarding/              # First-time user flow
└── shared/                      # Widgets, extensions
```

**Platform Detection** (`lib/core/platform/platform_service.dart`):
- Detects: mobile Android, mobile iOS, Chrome extension, web
- Critical for conditional Firebase/AdMob/RevenueCat initialization

**State Management**:
- Riverpod providers in `lib/core/providers/app_providers.dart` (theme, onboarding)
- Firebase providers in `lib/core/providers/firebase_providers.dart` (auth state)

**Key Flows**:
1. App start → Firebase init → check onboarding → check auth → route to appropriate screen
2. Chat → Firestore repository → AI client (DeepSeek/OpenRouter) → quota check → response
3. Extension build → Flutter Web + custom manifest.json + service worker removal

## Commands

**Setup**:
```bash
flutter pub get
cp .env.example .env  # Fill in API keys
```

**Run**:
```bash
# Mobile
flutter run -d <device>

# Web
flutter run -d chrome

# Extension (dev mode)
bash scripts/build_extension.sh
# Load build/extension/ in chrome://extensions
```

**Test**:
```bash
# All tests (unit + widget)
bash scripts/run_tests.sh all

# Specific test types
bash scripts/run_tests.sh unit
bash scripts/run_tests.sh widget
bash scripts/run_tests.sh integration  # Requires emulator/device
bash scripts/run_tests.sh coverage

# Single test
flutter test path/to/test.dart
```

**Build**:
```bash
# Android APK
flutter build apk

# iOS
flutter build ios

# Chrome Extension
bash scripts/build_extension.sh  # → aironbot-extension.zip
```

**Lint**:
```bash
flutter analyze
```

## Environment Variables

Required in `.env` (never commit):
- `DEEPSEEK_API_KEY`, `OPENROUTER_API_KEY` – AI providers
- `ADMOB_*` – AdMob app/banner/interstitial/rewarded IDs
- `REVENUECAT_API_KEY_*` – iOS/Android subscription keys
- `STRIPE_*` – Web payment (extension)
- `APP_ENV` – development/production

## Testing Conventions

**Test Types**:
- `test/core/` – Core utilities
- `test/features/*/` – Feature-specific tests
- `test/load/` – Load/stress tests
- `integration_test/` – E2E tests (require emulator)

**Tags**: Tests use `--tags` for filtering: `unit`, `widget`, `integration`, `performance`, `load`

**Helpers**: `test/test_helpers.dart` provides shared test utilities

## Chrome Extension Specifics

**Build Process** (`scripts/build_extension.sh`):
1. Flutter Web build with `--pwa-strategy=none`
2. Copies manifest.json, background.js, content_script.js
3. Removes Flutter service worker (conflicts with Manifest V3)
4. Patches index.html to remove SW registration
5. Creates ZIP for Chrome Web Store

**Manifest V3** (`web/manifest.json`):
- Side panel + popup UI
- Background service worker
- Content scripts for all URLs
- Host permissions for AI APIs + Firebase

## Firebase Structure

**Collections** (Firestore):
- `users` – User profiles, quota tracking
- `chats` / `conversations` – Message history
- `projects` – Pro user projects

**Security**: Rules enforce user-owned data access

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
- `listenMode: ListenMode.dictation` pour écoute continue

**VoiceConversationNotifier** (`lib/features/chat/presentation/voice_conversation_service.dart`):
- Boucle : `listening → thinking → speaking → idle → listening`
- `_speakResponseAndLoop()` : stop micro → TTS → pause anti-echo 500ms → **state = idle** (CRITIQUE : débloque la boucle)
- Max 3 échecs STT consécutifs → état `error` (pas de boucle infinie)
- `_listenWithVad()` : retourne `null` si STT indisponible, `""` si silence
- `_pendingTranscript` protège contre les doublons de callback

**TTS** (`lib/features/chat/presentation/tts_natural_service.dart`):
- `flutter_tts` natif, vitesse par défaut : 0.65
- Nettoyage markdown : strip URLs, citations `[n]`, emojis, formatting
- `speakNaturally()` : nettoie → lit → attend la fin via `Completer`

## Attachment UX (pièces jointes)

**Nouveau flux** (refonte 2026-05-04) :
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
