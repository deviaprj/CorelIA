# TASKS.md — Suivi Corely

Dernière mise à jour : 2026-05-08 — Session V4 : Améliorations voix, fichiers, recherche, sync

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

## Terminé — Session V4 (2026-05-08)

### 1. Amélioration du dialogue vocal ✅
- [x] **Cache TTS** — `TtsCacheService` SHA-256(text+voice+rate+pitch) → fichier MP3 local, LRU 50, TTL 24h
- [x] **Streaming Edge TTS** — `synthesizeStream()` incrémental, lecture dès 4KB, fallback synthesize classique
- [x] **Mode barge-in** — Micro activé pendant TTS (500ms anti-echo), interruption si ≥2 mots détectés
- [x] **Whisper STT fallback** — `WhisperSttService` via DeepSeek Whisper API, mobile uniquement, stub web

### 2. Analyse fichiers dans la conversation ✅
- [x] **Support PPTX** — Extraction des diapositives (shapes `<a:t>`, tri par numéro)
- [x] **Amélioration DOCX** — Extraction par paragraphes (`w:p`) au lieu de texte brut
- [x] **Amélioration PDF** — Regroupement en paragraphes cohérents (ponctuation de fin)
- [x] **Troncature intelligente** — Respect des paragraphes et phrases, caractères restants indiqués
- [x] **Limite contexte Pro** — 15 000 (Free) → 30 000 (Pro) caractères pour les fichiers

### 3. Recherche internet optimisée ✅
- [x] **Debouncer** — Fusion des requêtes identiques dans les 2 secondes
- [x] **DuckDuckGo Instant Answer** — `getInstantAnswer()` pour définitions/facts rapides
- [x] **Mode hors-ligne** — Cache expiré retourné en dernier recours si réseau indisponible

### 4. Sync multi-appareils ✅
- [x] **Conversations temps réel** — Déjà en place via Firestore snapshots
- [x] **Préférences sync** — `PreferencesSyncService` (Firestore ↔ SharedPreferences), `syncedPreferencesProvider`
- [x] **Profil utilisateur temps réel** — `userProfileProvider` + `isProSyncProvider` via Firestore snapshots
- [x] **isPro web temps réel** — `isProProvider` web utilise `isProSyncProvider` en priorité

### 5. Corrections critiques pour beta ✅
- [x] **TTS cache web** — Pattern d'export conditionnel (io/web stub), pas de `dart:io` sur web
- [x] **Whisper STT** — Export conditionnel io/web, `http` package pour multipart au lieu de HttpClient manuel
- [x] **PreferencesSyncService** — Branché dans `main.dart`, watcher Firestore actif
- [x] **0 erreurs de compilation** vérifiées avec flutter analyze

---
## Backlog (sessions futures)

### 1. EXTENSION GOOGLE CHROME (enrichissement)
- [ ] Vérifier démarrage extension après tous les fixes
- [ ] Résumé de page via Readability.js
- [ ] Autofill formulaires
- [ ] Extraction/téléchargement médias

### 2. ANALYSE DE DOCUMENTS ET D'IMAGES
- [ ] PDF scannés : OCR (nécessite API cloud ou Tesseract)

### 3. VOCAL
- [ ] Mode barge-in : test UX et ajustement anti-echo
- [ ] Streaming audio : test sur connexions lentes
- [ ] Cache TTS : vérifier la persistance sur Android low-storage

### 4. QUALITÉ BETA
- [ ] Tests unitaires pour les nouveaux services (TtsCache, Whisper, PreferencesSync)
- [ ] Tests d'intégration extension Chrome (build + load + test)
- [ ] Vérification de la build release Android (APK)
- [ ] Vérification de la build extension Chrome (ZIP)
- [ ] Audit sécurité : clés API non exposées, Firestore rules
- [ ] Performance : profiler le temps de démarrage cold/warm
- [ ] Accessibilité : vérifier contrastes, tailles de texte, labels