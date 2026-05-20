# TASKS.md — Suivi Corely

Dernière mise à jour : 2026-05-20 — Session complète : TTS, /docgen, Extension, Tests

## Terminé — Session 2026-05-20 — Bug Fixes ✅

### TTS -15% ✅
- `_speechRate` : 0.52 → 0.44 (flutter_tts)
- Edge TTS emotion rates : ×0.85 (neutral 0.90→0.77, etc.)
- speech_bridge.js : emotion rates ×0.85 (neutral 1.0→0.85, etc.)

### Extension bridge crash fix ✅
- **Cause racine** : `js.allowInterop` callback non wrappé dans try-catch → crash "Uncaught Error" quand `corely_browser_action_result` arrive
- **Fix** : `_addWindowListener` wrappe le callback dans try-catch
- Data parsing dans `corely_browser_action_result` aussi wrappé
- Timeout Dart : 10s → 15s (marge pour 8s JS DOM timeout)

### background.js timeouts ✅
- OPEN_URL : `Promise.race` avec 8s timeout
- SAVE_AS_PDF : `Promise.race` avec 8s timeout
- DOWNLOAD_DATA : `Promise.race` avec 10s timeout
- Injection delay : 200ms → 500ms
- extension_bridge.js : meilleur logging erreurs

### Slash command autocomplete ✅
- Palette disponible sur TOUTES les plateformes (pas juste extension)
- `_suppressSlashFilter` : empêche la palette de réapparaître après sélection
- `handleSlashCommand` : debug logging ajouté pour diagnostic

### /docgen universel ✅
- Fonctionne sur mobile ET extension (commande universelle)
- Fallback gracieux si download échoue : document intégré dans le chat
- Search errors gérées sans bloquer la génération

### Copier/Modifier prompt ✅
- `_UserActionRow` : boutons Copier + Modifier sur messages utilisateur
- Modifier pré-remplit la barre de saisie avec le texte du message
- `requestFocus()` ajouté à `InputBarState`

---

## Terminé — Session V10 (2026-05-15) — Search-First & Parsing Généralisé

### SearchIntentExtractor (nouveau) ✅
- **Fichier** : `lib/features/chat/data/search_intent_extractor.dart` (~1150 lignes)
- Extraction généralisée pour 9 intents : flights, hotels, products, weather, events, restaurants, rentals, secondhand, bestdeal
- `SearchMemory` : apprentissage par `recordSuccess()`, stocke patterns et mots-clés
- Extraction paramètres : villes, dates (num/text/relative), condition, prix, tri, cuisine
- Détection domaine événementiel : concerts, musées, festivals, théâtre, sports, expositions

### IATA Codes (nouveau) ✅
- **Fichier** : `lib/features/chat/data/iata_codes.dart` (~310 lignes)
- ~300 aéroports majeurs mappés (city name → IATA code)
- `resolveIataCode()` : direct → unaccented → fuzzy contains → per-word → prefix 5 chars
- `toSearchableAirport()` pour résolution automatique

### EnhancedSearchService — Réécrit ✅
- **Fichier** : `lib/features/chat/data/enhanced_search_service.dart` (~1120 lignes)
- **Changement architectural** : liens directs vers comparateurs avec paramètres pré-remplis
- Plus de DuckDuckGo scraping comme source primaire
- Vols : Google Flights, Skyscanner, Kayak, Kiwi, Expedia, Opodo, Momondo (7 liens)
- Hôtels : Booking, Expedia, Hotels.com, Agoda, Trivago, TripAdvisor, Airbnb, Abritel, Trip.com, GoVoyages (10 liens)
- Restaurants : TripAdvisor, TheFork, Google Maps
- Rentals : Airbnb, Abritel, Booking, Casamundo, HomeToGo
- Second-hand : eBay, Rakuten, Back Market, Vinted, Leboncoin

### ChatNotifier — Intégration ✅
- `sendMessage()` utilise `SearchIntentExtractor` + `recordSuccess()`
- `_performEnhancedSearch()` gère les 9 intents
- `_isValidCityPair()` : validation des villes extraites (≤3 mots, pas de termes parasites)
- Fallback `parseFlightParams` si params extractor invalides

### Bug Fixes ✅
- **Parsing vols lowercase** : `_extractFlightParams` → sanitize+capitalize avant regex
- **IATA fuzzy** : per-word matching + prefix 5 chars ("londre" → "londres" → LON)
- **Stop words** : ajout `direct`, `directs` dans `_isStopWord`
- **User-Agent** : `if (!kIsWeb)` pour éviter l'erreur "Refused to set unsafe header" dans l'extension
- **Mois portugais** : `março: 2` → `março: 3`

### Chrome Extension ✅
- **speech_bridge.js v2** : STT multi-langue, continuous mode, retry x3, TTS multi-langue, mic check
- **manifest.json** : permission `offscreen`, hosts DuckDuckGo ajoutés

### Résultat ✅
- **463 tests passés, 0 échec**
- APK installé sur Xiaomi 12, Extension rebuildée
- Branches `br-AironBot-V2` et `main` synchronisées sur origin

---

## À faire — Prochaine session

### Priorité HAUTE
- [ ] **Tester le parsing vols en conditions réelles** : "trouve un billet paris-londre direct du 29/05", "vol aller-retour nice-barcelone le 10 juin retour le 15", etc.
- [x] **Fix `_performEnhancedSearch` hôtels** : checkIn/checkOut/guests sont bien passés à `searchHotels` — vérifié, le code est correct
- [x] **Vérifier OPEN_URL timeout** : `background.js` a `Promise.race` avec 8s timeout + `normalizeExternalUrl` pour les URLs malformées

### Priorité MOYENNE
- [ ] **TTS audio dans l'extension** : speech_bridge.js v2 a le support, tester avec une vraie réponse IA
- [ ] **Tests de non-régression** : `_tryParseFlightParamsGeneric` lowercase, `_isValidCityPair`, IATA fuzzy
- [ ] **Analyse fichiers TXT/MD** : tester l'injection comme contexte conversationnel
- [ ] **Résumé de page extension** : tester SUMMARIZE_PAGE + GET_PAGE_CONTENT

### Priorité BASSE
- [ ] Synchronisation temps réel des préférences entre mobile et extension
- [ ] Support HEIC/HEIF pour les images
- [ ] OCR pour PDF scannés
- [ ] Firebase Storage pour les images (au lieu de base64)

---

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

## Terminé — Session V8 (2026-05-14) — Commandes Slash, Docs & Tests

### Fix racine : commandes slash de l'extension ✅
- **Cause** : `web/extension_bridge.js` n'avait pas de listener pour l'événement `corely_browser_action` dispatché par Dart. Le flux était cassé : Dart → CustomEvent → [RIEN].
- **Fix** : Ajout d'un listener `window.addEventListener('corely_browser_action', ...)` dans `extension_bridge.js` qui relaie vers `chrome.runtime.sendMessage` et dispatch le résultat via `corely_browser_action_result`.
- **Fichier manquant** : `web/dom_actions.js` créé (386 lignes) — 14 handlers d'actions DOM injectés via `chrome.scripting.executeScript`.

### Nouvelles commandes slash (12 → 24) ✅
- **Commandes ajoutées** : `/forms`, `/tables`, `/media`, `/metadata`, `/autofill`, `/inspect`, `/highlight`, `/waitfor`, `/export`, `/monitor`, `/translate`, `/searchpage`
- **Handlers** : 12 nouvelles méthodes dans `ChatNotifier` (~250 lignes)
- **BrowserActionType** : 8 nouveaux types d'actions (extractTables, extractForms, extractMedia, pageMetadata, autoFillPage, highlightElement, waitForSelector, getElementInfo)
- **dom_actions.js** : handlers pour CLICK_ELEMENT, FILL_FORM, SCROLL, EXTRACT_TEXT/LINKS/TABLES/FORMS/MEDIA, PAGE_METADATA, HIGHLIGHT_ELEMENT, AUTOFILL_PAGE, WAIT_FOR_SELECTOR, GET_ELEMENT_INFO

### Documentation ✅
- `docs/GUIDE_COMMANDES_SLASH.md` — Référence complète 24 commandes avec exemples et combos naturels
- `docs/GUIDE_UTILISATEUR_MOBILE.md` — 8 sections : chat, vocal, pièces jointes, recherche, paramètres, Pro
- `docs/GUIDE_UTILISATEUR_EXTENSION.md` — 10 sections : installation, modes, interaction web, limitations
- `docs/GUIDE_COMBOS.md` — 24 combos concrets, 5 patterns, méthodologie de création

### Tests ✅ (108 tests, 0 échecs)
- `test/features/chat/slash_commands_test.dart` — 24 commandes, parsing, recherche, combos, validation groups
- `test/features/chat/slash_command_handlers_test.dart` — BrowserAction, ActionResult, enums, mapping, CSS selectors, validation
- `test/features/chat/data/file_upload_service_test.dart` — `lastSentenceEnd()` fix (RangeError + public API)
- `test/features/chat/data/tts_cache_service_test.dart` — Références `_lastSentenceEnd` → `lastSentenceEnd`

### Bug fix : actionId flaky test ✅
- **Cause** : `BrowserAction.actionId = DateTime.now().millisecondsSinceEpoch.toString()` — deux objets créés dans la même ms ont le même ID.
- **Fix** : Compteur statique `_counter` → `'${timestamp}_${++_counter}'` garantit l'unicité.

### 1. EXTENSION CHROME — Commandes slash ✅ CORRIGÉ
- [x] **Corriger les commandes slash** : `/download`, `/pdf`, `/links`, `/summarize`, `/extract`, `/scroll`, `/open`, `/click`, `/fill`, `/screenshot`, `/back`, `/forward`
- [x] Le flux complet fonctionne : `ChatNotifier._handleSlashCommand()` → `ExtensionBridge.executeAction()` → `extension_bridge.js` → `background.js` → `dom_actions.js` → retour. Le `_pendingActions` Completer reçoit maintenant la réponse.
- [x] 12 nouvelles commandes ajoutées (/forms, /tables, /media, /metadata, /autofill, /inspect, /highlight, /waitfor, /export, /monitor, /translate, /searchpage)

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

---

## Terminé — Session V9 (2026-05-14) — Multilingue, Recherche Enrichie & Correctifs UX

### Intégration multilingue ✅
- **LanguageService** (`lib/core/language/language_service.dart`) : 6 langues (FR/EN/ES/DE/IT/PT)
- `classifySearchIntent()` avec patterns multilingues pour vols, hôtels, produits, météo
- `toNaturalLanguage()` traduit les commandes slash selon la locale
- `parseMonth()` supporte les noms de mois dans les 6 langues
- Paramètres API localisés : OWM `lang`, SerpAPI `hl`/`gl`
- Sélecteur de langue dans `SettingsScreen`

### Correctif critique : parseFlightParams regex non fonctionnelles ✅
- **Cause** : `$numericDate` et `$months` non interpolés dans les raw strings Dart (`r'...'`)
- **Fix** : Concaténation de chaînes + fallback de capitalisation pour entrées minuscules
- **Stop words** : 45 mots filtrés pour éviter extraction de "Avion"/"Aller" comme villes

### Correctif architectural : résultats enrichis injectés dans le contexte IA ✅
- **Cause** : Résultats de `_performEnhancedSearch()` jamais transmis à `_buildStream()`
- **Fix** : Paramètre `enhancedContext` injecté comme message système avant l'historique

### Recherche enrichie sans clé API SerpAPI ✅
- **Cause** : Pas de `SERPAPI_API_KEY` dans `.env` → `searchFlights()`/`searchHotels()`/`searchProducts()` retournaient `[]`
- **Fix** : Fallback DuckDuckGo scraping + liens directs toujours générés (Skyscanner, Google Flights, Kayak, Opodo, Booking.com, Airbnb)

### Liens cliquables dans le chat ✅
- Ajout `onTapLink` sur le `MarkdownBody` → ouvre les URLs via `url_launcher`

### Vitesse TTS réduite ✅
- `_speechRate` : 0.65 → 0.50 (plus lent, reste dynamique avec pitch 1.10)

### Bug extension : `sender is not defined` ✅
- `background.js:61` : `sender` → `_sender`

---

## Backlog (sessions futures)

### 7. PARSING PARAMÈTRES — Généralisation pour tous types de services/biens
- [ ] **Généraliser l'extraction de paramètres** au-delà des vols : concerts, musées, restaurants, locations vacances, forfaits voyage, etc.
- [ ] **Mapping codes IATA** pour les recherches de vols (les comparateurs fonctionnent mieux avec PAR/BEG qu'avec "Paris"/"Belgrade")
- [ ] **Normalisation des dates** : Kayak a retourné des dates décalées de 2 jours (13-20 juin au lieu de 15-22)
- [ ] **Pattern unifié** : extraire type de recherche → paramètres → fallback sans API → injection contexte IA → formatage markdown

### 8. EXTENSION CHROME — Microphone
- [ ] Micro non détecté en mode vocal : vérifier permission `audioCapture`, améliorer UX de demande de permission
- [ ] Tests cross-browser (Firefox, Edge, Brave)

### 9. QUALITÉ
- [ ] Tests d'intégration extension Chrome (build + load + test flux complet)
- [ ] Audit sécurité : clés API non exposées dans l'APK/extension
- [ ] Performance : profiler temps de démarrage cold/warm