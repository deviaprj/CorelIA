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

## Quality Guidelines (from .github/skills/)

- **Architecture**: MVVM + Riverpod
- **Responsiveness**: 100% responsive (mobile/web)
- **Lint**: `very_good_analysis` package
- **Performance**: Target <16ms frames (Flame charts)
- **Coverage**: 80%+ via CI (GitHub Actions)
- **Sync**: All UI/logic shared between app/extension; Firebase listeners for realtime sync
