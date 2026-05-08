# TASKS.md — Suivi Corely

Dernière mise à jour : 2026-05-08 — Session V5 : Extension Chrome — 3 bugs CSP critiques corrigés

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

## Terminé — Session V3 (2026-05-08)

### Tâche 1 : Audit et correction extension Chrome ✅
- [x] **isDemoMode forcé à false sur extension** — Firebase initialisé, conversations persistées
- [x] **isProProvider web** — Lecture du plan depuis Firestore (pas toujours false)
- [x] **WebSpeechBridge** — Bridge interop STT/TTS entre Flutter et speech_bridge.js via dart:js
- [x] **VoiceServiceNotifier** — Branchement conditionnel : web → WebSpeechBridge, mobile → speech_to_text
- [x] **TTS émotions sur flutter_tts** — _speakWithFlutterTts applique rate/pitch selon émotion
- [x] **image_upload_service_web** — Implémentation réelle via FilePicker (gallery seulement, pas camera)
- [x] **Paywall web** — Bouton Stripe checkout + liste features Pro au lieu d'un simple message
- [x] **ExtensionBridge** — Pont Dart ↔ chrome.runtime via CustomEvents + extension_bridge.js
- [x] **ChatScreen** — Écoute du texte sélectionné depuis l'extension, pré-remplit l'input
- [x] **content_script.js** — Extraction contenu page (article/main/body) + GET_PAGE_CONTENT
- [x] **background.js** — Menu contextuel renommé ask_corely, suppression code mort, relais chrome.storage
- [x] **manifest.json** — Suppression permissions tts/offscreen inutilisées
- [x] **speech_bridge.js** — Événements renommés aironbot_* → corely_*
- [x] **build_extension.sh** — Zip renommé corely-extension.zip
- [x] **0 erreurs de compilation** vérifiées avec flutter analyze

### Tâche 0 : Analyse complète du projet ✅
- [x] Identifier les bugs de démarrage extension Chrome
- [x] Bugs documentés dans `memory/extension-startup-bugs.md`

### Tâche 1 : Fix extension démarrage ✅
- [x] Créer stubs web pour mobile-only services
- [x] Ajouter imports conditionnels `export 'mobile.dart' if (dart.library.html) 'web.dart'`
- [x] Fix `build_extension.sh` : patcher `<base href="/">` → `./`
- [x] Fix `build_extension.sh` : neutraliser refs SW dans flutter_bootstrap.js
- [x] Retirer `"type": "module"` du manifest.json
- [x] Ajouter `*.wasm` à `web_accessible_resources`
- [x] Fix CSP : `blob:` uniquement dans `worker-src` (pas `script-src`)
- [x] `AppConstants._env()` : `String.fromEnvironment` prioritaire avant dotenv
- [x] `quota_exceeded_dialog.dart` : supprimé import direct `google_mobile_ads`

### Tâches 2-5 : Logos, renommage, refacto conversationnel, settings ✅
- [x] (Voir session V3 pour détails)

## Terminé — Session V4 (2026-05-08)

### 1. Amélioration du dialogue vocal ✅
- [x] **Cache TTS** — SHA-256(text+voice+rate+pitch) → MP3, LRU 50, TTL 24h
- [x] **Streaming Edge TTS** — `synthesizeStream()` incrémental, lecture dès 4KB
- [x] **Mode barge-in** — Micro activé pendant TTS (500ms anti-echo), interruption si ≥2 mots
- [x] **Whisper STT fallback** — `WhisperSttService` via DeepSeek Whisper API, stub web

### 2. Analyse fichiers dans la conversation ✅
- [x] PPTX, DOCX amélioré, PDF paragraphes, troncature intelligente, limite Pro 30K

### 3. Recherche internet optimisée ✅
- [x] Debouncer 2s, DuckDuckGo Instant Answer, mode hors-ligne

### 4. Sync multi-appareils ✅
- [x] PreferencesSyncService, userProfileProvider, isProSyncProvider temps réel

### 5. Corrections critiques pour beta ✅
- [x] Conditional exports TTS cache, Whisper, 0 erreurs flutter analyze

## Terminé — Session V5 (2026-05-08)

### Extension Chrome : 3 bugs CSP critiques corrigés ✅

L'extension moulinait indéfiniment sans charger Flutter. 3 bugs identifiés via console :

**Bug #1 : Scripts inline bloqués par CSP**
- Erreur : `Executing inline script violates CSP 'script-src self'`
- Cause : `<script>function dispatchCustomEvent(...)` et `<script>window.addEventListener('flutter-first-frame'...)` inline dans `index.html`
- Fix : Scripts déplacés vers `web/corely_init.js` (fichier externe chargé via `<script src>`)

**Bug #2 : Service Worker Flutter en conflit avec Manifest V3**
- Erreur : `Failed to register a ServiceWorker... flutter_service_worker_disabled.js`
- Cause : `serviceWorkerSettings` passé à `_flutter.loader.load()`, tentative d'enregistrement SW
- Fix : `serviceWorkerSettings` retiré de l'appel `load()`, fonction `loadServiceWorker()` neutralisée (`if(1)return Promise.resolve()`)

**Bug #3 : CanvasKit chargé depuis CDN Google**
- Erreur : `Loading the script 'https://www.gstatic.com/flutter-canvaskit/...' violates CSP`
- Cause : La fonction `b(s,t)` vérifie `t.useLocalCanvasKit` (2e argument = `_flutter.buildConfig`), pas le paramètre `config`
- Fix : `"useLocalCanvasKit":true` ajouté à `_flutter.buildConfig` dans `flutter_bootstrap.js`

**Autres corrections :**
- [x] CSP : `blob:` retiré de `worker-src` (rejeté par Chrome V3)
- [x] Diagnostics : timeout 30s + `window.onerror` pour afficher message d'erreur
- [x] `build_extension.sh` entièrement réécrit (patch CanvasKit local, SW neutralisé, corely_init.js copié)
- [x] Firestore rules déployées (`firestore.rules`)
- [x] 4 fichiers de tests unitaires ajoutés

---
## Backlog (sessions futures)

### 1. EXTENSION CHROME — Chargement et validation
- [ ] **Valider le chargement complet** : l'extension doit charger Flutter, afficher le chat, répondre à l'IA
- [ ] Tester le side panel et le popup (les deux modes d'affichage)
- [ ] Tester la sélection de texte → menu contextuel → envoi dans Corely
- [ ] Résumé de page via Readability.js
- [ ] Autofill formulaires
- [ ] Extraction/téléchargement médias

### 2. ANALYSE DE DOCUMENTS ET D'IMAGES
- [ ] PDF scannés : OCR (nécessite API cloud ou Tesseract)
- [ ] Tester injection fichiers TXT/MD comme contexte conversationnel

### 3. VOCAL
- [ ] Mode barge-in : test UX et ajustement anti-echo
- [ ] Streaming audio : test sur connexions lentes
- [ ] Cache TTS : vérifier la persistance sur Android low-storage
- [ ] Extension : créer offscreen document pour TTS audio (Manifest V3)

### 4. QUALITÉ BETA
- [ ] Exécuter les tests unitaires (`bash scripts/run_tests.sh all`)
- [ ] Tests d'intégration extension Chrome (build + load + test flux complet)
- [ ] Build release Android APK + vérifier flux principal (chat, voix, fichiers)
- [ ] Audit sécurité : clés API non exposées dans l'APK/extension, Firestore rules en production
- [ ] Performance : profiler le temps de démarrage cold/warm (mobile + extension)
- [ ] Accessibilité : vérifier contrastes, tailles de texte, labels