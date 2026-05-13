# TASKS.md — Suivi Corely

Dernière mise à jour : 2026-05-13 — Session V6 : Extension Runtime Fixes

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

## Terminé — Session V6 (2026-05-13) — Extension Runtime Fixes

### Bug #1 : ConsentBanner crash (Navigator.of null) ✅
- **Erreur** : `Null check operator used on a null value` au démarrage de l'extension
- **Cause** : `ConsentBanner.showIfNeeded(context, ref)` utilisait le context de `CorelyApp.build()`, qui est au-dessus du `MaterialApp.router`. `showModalBottomSheet` → `Navigator.of(context)` → crash.
- **Fix** : `GlobalKey<NavigatorState> rootNavigatorKey` dans `router.dart`, passé à `GoRouter(navigatorKey:)`. `ConsentBanner` utilise `rootNavigatorKey.currentContext` + try-catch + `context.mounted` check.

### Bug #2 : VoiceServiceNotifier réentrance (uninitialized provider) ✅
- **Erreur** : `Bad state: Tried to read the state of an uninitialized provider` (2x)
- **Cause** : `VoiceServiceNotifier.build()` faisait `state = state.copyWith(isAvailable: true)`. Riverpod interdit `state =` dans `build()` → réinitialisation immédiate → cascade.
- **Fix** : Retourner `VoiceState(isAvailable: _webBridge!.isAvailable)` directement au lieu de modifier `state`.

### Bug #3 : AsyncValue.value! null checks ✅
- **Cause potentielle** : `next.value!` dans `ChatNotifier` et `VoiceConversationNotifier` pouvait crasher si `AsyncValue` transitionne entre états.
- **Fix** : Remplacé par `next.valueOrNull` + null checks + try-catch dans `ChatNotifier.build()`.

### Autres corrections ✅
- Stack trace sécurisée dans `runZonedGuarded` (try-catch autour de `$stack`)
- `FlutterError.onError` affiche maintenant la stack trace complète
- `context.mounted` check avant `showModalBottomSheet` dans `ConsentBanner`

---

## Backlog (sessions futures)

### 1. EXTENSION CHROME — Commandes slash cassées
- [ ] **Corriger les commandes slash** : `/download`, `/pdf`, `/links`, `/summarize`, `/extract`, `/scroll`, `/open`, `/click`, `/fill`, `/screenshot`, `/back`, `/forward`
- [ ] Le flux complet ne fonctionne pas : `ChatNotifier._handleSlashCommand()` → `ExtensionBridge.executeAction()` → `browser_actions.js` → `background.js` → `content_script.js` → retour. Le `_pendingActions` Completer ne reçoit jamais de réponse.
- [ ] Piste : vérifier `chrome.runtime.sendMessage` callback dans `extension_bridge.js` et le flux de réponse asynchrone

### 2. EXTENSION CHROME — Chargement et validation
- [ ] Tester le side panel et le popup (les deux modes d'affichage)
- [ ] Tester la sélection de texte → menu contextuel → envoi dans Corely
- [ ] Extraction/téléchargement médias
- [x] Résumé de page → SUMMARIZE_PAGE action implémentée
- [x] Navigation navigateur → OPEN_URL, NAVIGATE_BACK/FORWARD, SCROLL
- [x] Capture d'écran → SCREENSHOT implémentée
- [x] Système d'actions navigateur bidirectionnel (browser_actions.js + dom_actions.js + ExtensionBridge)

### 3. ANALYSE DE DOCUMENTS ET D'IMAGES
- [ ] PDF scannés : OCR (nécessite API cloud ou Tesseract)
- [x] Injection fichiers TXT/MD comme contexte conversationnel

### 4. VOCAL
- [ ] Mode barge-in : test UX et ajustement anti-echo
- [ ] Streaming audio : test sur connexions lentes
- [ ] Cache TTS : vérifier la persistance sur Android low-storage
- [ ] Extension : créer offscreen document pour TTS audio (Manifest V3)

### 5. QUALITÉ BETA
- [ ] Exécuter les tests unitaires (`bash scripts/run_tests.sh all`)
- [ ] Tests d'intégration extension Chrome (build + load + test flux complet)
- [x] Build release Android APK + installer sur Xiaomi (session 2026-05-13)
- [ ] Audit sécurité : clés API non exposées dans l'APK/extension
- [ ] Performance : profiler le temps de démarrage cold/warm (mobile + extension)
- [ ] Accessibilité : vérifier contrastes, tailles de texte, labels

### 6. RIVERPORD — Vérifier les providers existants
- [ ] Chercher d'autres `state = state.copyWith(...)` dans des méthodes `build()` qui pourraient causer des réentrances
- [ ] Vérifier que tous les `AsyncValue.value!` sont remplacés par `valueOrNull`