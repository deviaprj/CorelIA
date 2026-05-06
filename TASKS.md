# TASKS.md — Suivi Corely

Dernière mise à jour : 2026-05-06 — Session V2 : Extension fixes + Renommage + Refacto comportement + Settings

## Terminé (sessions précédentes)

- [x] **Microphone** — Instance STT fraîche par `startListening()`, `ListenMode.dictation`, deadlock corrigé
- [x] **TTS vitesse** — Réduite à 0.65, pitch 1.10
- [x] **Vision / Images** — Routage prioritaire AVANT Pro/Free, fallback `deepseek-chat`, erreurs formatées
- [x] **Pièces jointes UX** — `AttachmentData` + `SendCallback`, chip preview + ✕
- [x] **Web Search** — `useSearch: true` par défaut, `enable_search: true` dans body DeepSeek
- [x] **Chat bloqué** — `isStreaming: false` forcé dans tous les blocs catch
- [x] **Analyse fichiers** — BOM UTF-8/UTF-16, nom du fichier dans le contexte système
- [x] **Edge TTS + EmotionParser** — WebSocket, voix françaises, conditional import web/mobile
- [x] **TTS naturel refactorisé** — `TtsNaturalService` avec Edge TTS primaire + flutter_tts fallback
- [x] **Splash aurora réactif** — AnimationControllers, réaction micro, couleurs par émotion
- [x] **Voice conversation + émotion** — Parse balises prosodiques, splash change de couleur
- [x] **TTS bridge extension** — `speech_bridge.js` pont TTS via Web Speech API + mapping émotion
- [x] **Fix bip micro** — Instance STT initialisée une seule fois dans `_initSttOnce()`
- [x] **Rewarded ads quota recovery** — SearchQuotaService, VoiceQuotaService, QuotaExceededDialog
- [x] **Ollama vision** — `OllamaVisionService` + fallback cloud (P1)
- [x] **Cache recherche web** — `SearchCacheService` LRU + SHA-256 + TTL 15 min (P1)

## Terminé — Session V2 (2026-05-06)

### Tâche 0 : Analyse complète du projet ✅
- [x] Identifier les bugs de démarrage extension Chrome
- [x] Bugs documentés dans `memory/extension-startup-bugs.md`

### Tâche 1 : Fix extension démarrage ✅
- [x] Créer stubs web pour mobile-only services (dio_client, image_upload, ollama_vision, ad_service, ad_banner, subscription, paywall, deep_link)
- [x] Ajouter imports conditionnels `export 'mobile.dart' if (dart.library.html) 'web.dart'`
- [x] Fix `build_extension.sh` : patcher `<base href="/">` → `./`
- [x] Fix `build_extension.sh` : neutraliser refs SW dans flutter_bootstrap.js
- [x] Retirer `"type": "module"` du manifest.json
- [x] Ajouter `*.wasm` à `web_accessible_resources`
- [x] Fix CSP : `blob:` uniquement dans `worker-src` (pas `script-src`)
- [x] `AppConstants._env()` : `String.fromEnvironment` prioritaire avant dotenv
- [x] `quota_exceeded_dialog.dart` : supprimé import direct `google_mobile_ads`

### Tâche 2 : Remplacer tous les logos/icons ✅
- [x] Logo "C" Corely généré (fond #6C63FF, lettre blanche)
- [x] Tailles extension : 16x16, 48x48, 128x128
- [x] Tailles PWA : 192x192, 512x512, maskable
- [x] Tailles Android : mipmap mdpi → xxxhdpi (ic_launcher + ic_launcher_round)
- [x] Tailles iOS : AppIcon 20x20 → 1024x1024
- [x] Favicon 32x32 mis à jour

### Tâche 3 : Renommer AironBot → Corely ✅
- [x] `AppConstants.appName` → 'Corely'
- [x] Titres UI, messages, manifest.json, index.html, background.js
- [x] iOS Info.plist, AndroidManifest.xml
- [x] Test mis à jour (constants_test.dart)
- [x] Firebase project IDs et noms d'événements JS conservés (infrastructure)

### Tâche 4 : Refacto comportement conversationnel ✅
- [x] Recherche web désactivée par défaut (`useSearch: false`)
- [x] Classification d'intent `_needsWebSearch()` : factuel/temporel vs créatif/code
- [x] Extraction de requête `_extractSearchQuery()` : supprime salutations
- [x] Prompt système Corely injecté en tête de chaque conversation
- [x] `enableSearch: false` dans l'appel DeepSeek
- [x] Prompt de recherche web simplifié (plus "assistant avec accès internet")

### Tâche 5 : Refacto écran settings ✅
- [x] Supprimé slider vitesse TTS
- [x] Supprimé champ clé API DeepSeek
- [x] Ajouté textarea system prompt (6-8 lignes)
- [x] Ajouté boutons Fichier / Réinitialiser / Sauvegarder
- [x] `systemPromptProvider` (StateNotifier + SharedPreferences)
- [x] Prompt injecté au début de chaque conversation via `ref.read(systemPromptProvider)`

---
## Backlog (sessions futures)

### 1. AMÉLIORATION DU DIALOGUE VOCAL
- [ ] Streaming audio Edge TTS (HTTP chunked)
- [ ] Cache TTS : hash du texte → fichier audio local
- [ ] Mode barge-in : interrompre le TTS en parlant
- [ ] STT Whisper comme fallback

### 2. ANALYSE DE DOCUMENTS ET D'IMAGES
- [ ] PDF scannés : OCR
- [ ] Support PPTX, amélioration DOCX/XLSX
- [ ] Limite contexte 15000 → 30000 avec résumé auto

### 3. RECHERCHE INTERNET OPTIMISÉE
- [ ] Debouncer de recherche (500ms)
- [ ] DuckDuckGo Instant Answer API
- [ ] Mode hors-ligne : cache uniquement

### 4. EXTENSION GOOGLE CHROME (enrichissement)
- [ ] Vérifier démarrage extension après fixes
- [ ] Sync conversations via Firestore
- [ ] Résumé de page via Readability.js
- [ ] Autofill formulaires
- [ ] Extraction/téléchargement médias

### 5. SPLASH ANIMÉ PAR LA VOIX ✅
- [x] Forme réactive au volume
- [x] Gradient animé et émotions
- [x] Réduction du jitter visuel

### 6. SYNCHRONISATION MULTI-APPAREILS
- [ ] Conversations temps réel via Firestore
- [ ] Préférences sync (chrome.storage.sync + Firestore)
- [ ] Authentification partagée mobile/extension