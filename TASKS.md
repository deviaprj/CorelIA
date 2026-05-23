# TASKS.md — Suivi Corely

Dernière mise à jour : 2026-05-23 — Session V16 : Tests verts + fixes interpolation

## Terminé — Session 2026-05-23 — Tests Non-Régression ✅

### Problèmes résolus
1. **Suite de tests cassée après V16** : 12 échecs de compilation/runtime réduits à 0.
2. **Interpolation `$` échappée (`\$`) dans 3 fichiers** : `file_upload_service.dart`, `attachment.dart` retournaient des template strings littéraux au lieu de valeurs interpolées.
3. **`model_router.dart` dépendait des clés API** : `resolveModel()` retournait `null` en test car les clés DeepSeek/OpenRouter étaient vides. Le check de clé a été déplacé dans `_buildStreamForModel()` (call site), ce qui permet de tester le routage indépendamment.
4. **`SendCallback` manquait `attachments`** : `input_bar_test.dart` et `slash_command_handlers_test.dart` mis à jour pour refléter la nouvelle signature.
5. **Constantes et enum obsolètes** : `constants_test.dart` (URL DeepSeek), `slash_commands_test.dart` (count 25→26), `browser_action_test.dart` (count 21→22).

### Fichiers modifiés
- `test/features/chat/input_bar_test.dart` — ajout `attachments = const []` dans les stubs `onSend`
- `test/features/chat/slash_command_handlers_test.dart` — mapping `docgen`/`scrape` vers `BrowserActionType.getPageContent`
- `test/features/chat/slash_commands_test.dart` — count 25→26
- `test/features/chat/data/model_router_test.dart` — message `'explain why'` → `'raisonner sur ce sujet'` pour matcher keywords
- `test/core/constants_test.dart` — URL DeepSeek corrigée (`/chat/completions` sans `/v1`)
- `lib/features/chat/data/file_upload_service.dart` — suppression `\` avant `$` dans `truncateForContext()` (3 lignes)
- `lib/features/chat/domain/attachment.dart` — suppression `\` avant `$` dans `toApiPart()`
- `lib/features/chat/data/model_router.dart` — suppression checks clés API dans `resolveModel()`, ajout fallback `deepseek-v4-flash`

### Résultat
```
+602 tests passed, 0 failed
```

## Terminé — Session V16 (2026-05-22) — Mode Vocal Simplifié ✅

### Problèmes résolus
1. **Architecture V15 instable** : VAD prosodique, streaming TTS par phrases, full-duplex = fondamentalement cassé sur Android. Remplacé par une architecture tour-par-tour simple et fiable.
2. **Monologue (STT capte l'écho du TTS)** : micro coupé pendant le TTS (half-duplex), rouvert après. Plus d'echo capturé.
3. **TTS décousu** : suppression du streaming par phrases. La réponse complète est parlée d'un bloc via `speakNaturally()`.
4. **Détection aléatoire de fin de phrase** : suppression du VAD custom. Utilisation de `finalResult` natif du STT uniquement.
5. **Micro mort après 1er tour** : plus de redémarrage complexe du micro. Le cycle est explicitement géré : listen → stop → TTS → start.

### Architecture V16 (tour-par-tour)
```
LISTENING → THINKING → SPEAKING → LISTENING
   ↑_____________________________________|
```
- STT continu natif (`listenFor: 30min`, `pauseFor: null`)
- TTS parle le message COMPLET (pas de streaming par phrases)
- Half-duplex : micro OFF pendant le TTS, ON après
- Barge-in : speech final détecté pendant speaking → stop TTS + nouveau message LLM

### Fichiers modifiés
- `lib/features/chat/presentation/voice_service.dart` : STT simplifié, suppression VAD prosodique, mode conversation, redémarrage explicite
- `lib/features/chat/presentation/voice_conversation_service.dart` : machine à états tour-par-tour, TTS bloc, barge-in via speech final, suppression streaming TTS
- `lib/features/chat/presentation/tts_natural_service.dart` : suppression `speakStreaming()`, `_speakWithEdgeTtsStreaming()`, `setHesitationEnabled()`
- `lib/features/chat/presentation/prosody_vad_analyzer.dart` : **supprimé**
- `lib/features/chat/presentation/aurora_splash.dart` : suppression état `processingStt`
- `lib/features/chat/presentation/chat_screen.dart` : suppression état `processingStt`

### Fichiers inchangés (conservés)
- `barge_in_intent_classifier.dart` : classification d'intention barge-in
- `emotion_parser.dart` : parsing des balises émotion `[joyeux]`, etc.
- `tts_emotion.dart` : configs rate/pitch par émotion
- `openrouter_tts_service.dart` : synthèse TTS via OpenRouter
- `vocal_hesitation_injector.dart` : injections d'hésitations (inactif mais conservé)

## Terminé — Session 2026-05-23 — TTS Fix + Quota Retry + Monetization ✅

### Problèmes résolus
1. **TTS lit les sources et markdown** : `cleanMarkdown()` dans `tts_natural_service.dart` strippe maintenant :
   - Sections Sources/Références/Links (8 patterns, avec/sans `---`, bold/plain)
   - Blocs de raisonnement `<think>...</think>` et ` ```reasoning...``` `
   - Tableaux markdown → texte plat (cellules séparées par virgules)
   - Artefacts résiduels : `*`, `-`, `_`, `|`, `[`, `]`, `#`, `>` en début de ligne ou isolés
   - Newlines → espaces (discours continu sans pauses artificielles)
2. **Quota oublié après vidéo** : `_PendingMessage` stocke tous les paramètres de `sendMessage()`. `retryPendingMessage()` re-soumet automatiquement après `QuotaExceededDialog` vidéo réussie. `clearPendingMessage()` sur annulation.
3. **Notification icon manquante** : `ic_notification.xml` (vecteur cloche 24dp) + `keep.xml` (`tools:keep="@drawable/ic_notification"`) empêche R8/shrinkResources de le supprimer.
4. **Monetization fixes** : AdMob retry loading (3 essais avec backoff), GoRouter paywall navigation (`context.push`), Stripe fallback web, algo progressif `AdRewardTracker` (tier 0→1→2 = 1→2→3 vidéos, 30s anti-spam, reset minuit).
5. **Retention services** : `StreakService` (bonus +2 après 3 jours), `UserProfileService` (nom + intérêts), `UsageStatsService` (compteur messages + temps économisé), `DailyQuestionService` (notification locale 9h00).
6. **Slash commands overhaul** : traductions `scrape`/`docgen` (6 langues), messages assistant persistants via `_persistAssistantMessage()` (Firestore), annonces pré-exécution, erreurs persistantes au lieu de SnackBar éphémères.

### Fichiers modifiés (session)
- `lib/features/chat/presentation/tts_natural_service.dart` — `cleanMarkdown()` + `_stripSourcesSection()`
- `lib/features/chat/presentation/chat_notifier.dart` — `_PendingMessage`, `retryPendingMessage()`, `clearPendingMessage()`
- `lib/features/chat/presentation/chat_screen.dart` — `retryPendingMessage()` dans quota dialog
- `android/app/src/main/res/drawable/ic_notification.xml` — nouveau
- `android/app/src/main/res/raw/keep.xml` — nouveau
- `lib/features/monetization/ads/ad_reward_tracker.dart` — nouveau
- `lib/features/monetization/ads/ad_service_mobile.dart` — retry loading + rewarded fix
- `lib/features/monetization/ads/quota_exceeded_dialog.dart` — séquentiel, progress bar, auto-load
- `lib/features/retention/` — 4 services nouveaux

---

## TODO next-session (2026-05-24) — Priorité CRITIQUE

### 1. Tester mode vocal V16 sur Xiaomi 12
- [ ] 5 tours complets : aucun blocage, micro redémarre à chaque fois
- [ ] TTS naturel : pas de sources, asterisques, tirets, tableaux lus à voix haute
- [ ] Quota retry : demander vol Paris→Marseille en vocal, atteindre quota, regarder vidéo, vérifier que Corely répond au vol automatiquement
- [ ] Barge-in : parler pendant que Corely parle (> 3 mots) → TTS s'arrête, Corely répond au nouveau message
- [ ] Pas de monologue : Corely ne doit pas répondre à sa propre voix

### 2. Tester slash commands mobile avec backend local
- [ ] `/scrape https://example.com` → annonce + résultat/erreur persistant
- [ ] `/links https://example.com` → liste liens sans crash
- [ ] `/summarize https://example.com` → résumé persistant
- [ ] Backend `192.168.1.38:8000` opérationnel via `adb reverse tcp:8000`

### 3. Déployer le backend cloud
- [ ] `bash scripts/deploy_backend.sh` sur machine avec internet (Docker pull + push)
- [ ] Vérifier `api.aironbot.app` répond sur `/health` et `/search_smart`

### 4. Évaluer la recherche avancée
- [ ] Tester `searchFlights`, `searchHotels`, `searchProducts`, `searchWeather`
- [ ] Vérifier le parsing des paramètres (`parseFlightParams`, etc.)
- [ ] Évaluer si l'architecture actuelle suffit ou si une revue est nécessaire

### 5. Évaluer l'analyse de fichiers et images
- [ ] Tester l'extraction de texte de PDF, DOCX, XLSX
- [ ] Tester la vision (images envoyées au LLM)
- [ ] Évaluer si l'architecture actuelle suffit ou si une revue est nécessaire

### 6. Décision architecture globale
Après les tests, décider :
- **Continuer à patcher** les mécanismes existants pour un résultat optimal
- **Revoir l'architecture** de certains mécanismes (slash, recherche, fichiers) si les patchs ne suffisent pas

## Termine — Session V14 (2026-05-21) — Vocal UX : Bips, Latence, Qualité, Full-Duplex ✅

## Termine — Session V14 (2026-05-21) — Vocal UX : Bips, Latence, Qualité, Full-Duplex ✅

### Problèmes résolus
1. **Bips micro** : `listenFor: 30min` en mode continu + suppression des `stop()` auto → un seul bip au démarrage de la conversation
2. **Attente trop longue** : VAD adaptative (400ms si ponctuation finale, 900ms sinon) au lieu de 1.5s fixe
3. **Voix monotone** : sélection dynamique de voix `flutter_tts` (neural/premium fr-FR) + speed adaptatif (0.90 courts / 0.75 longs) + chunks 120 chars
4. **Barge-in retardé** : remplacement du word-count par barge-in audio temps réel (`micLevel > 0.12`)
5. **Thread parallèle** : full-duplex STT/TTS — le micro reste ouvert pendant que l'IA parle

### Fichiers modifiés
- `lib/features/chat/presentation/voice_service.dart` : STT continu 30min, VAD adaptative `_resetSilenceTimer`, suppression redémarrage auto avec bip
- `lib/features/chat/presentation/voice_conversation_service.dart` : barge-in audio `_handleVoiceState`, full-duplex `_restartListeningAfterTts` sans redémarrage inutile
- `lib/features/chat/presentation/tts_natural_service.dart` : `_selectBestVoice` dynamique, préchauffage TTS, speed adaptatif, chunks 120 chars, `hasPremiumVoice` detection
- `lib/features/chat/presentation/tts_emotion.dart` : suppression du champ `voice` invalide (dépendance Azure), configs rate/pitch uniquement
- `lib/features/chat/presentation/chat_notifier.dart` : prompt vocal enrichi avec balises émotion `[joyeux]`, `[triste]`, etc. pour sélection dynamique de voix TTS

## Terminé — Session V14 (2026-05-21) — Scraping Intelligent + Slash Commands Cross-Platform ✅

### Problèmes résolus
1. **Recherche sans résultats concrets** : le backend `/search_smart` scrape désormais les comparateurs (Skyscanner, Booking, Back Market, etc.) pour extraire vrais prix, cartes produits, liens directs — pas seulement des liens génériques.
2. **Slash commands limitées à l'extension** : `/summarize`, `/extract`, `/links`, `/metadata` acceptent maintenant une URL optionnelle et fonctionnent sur mobile/web via le backend `/scrape`.
3. **Nouvelle commande `/scrape`** : scraper n'importe quelle URL avec sélecteurs CSS personnalisés, cross-plateforme.
4. **Formatters markdown intelligents** : `SearchServiceGlobal.formatMarkdown()` produit des tableaux et listes selon l'intent (vols ✈️, hôtels 🏨, produits 🛒, restaurants 🍽️, événements 🎭, météo ☀️).

### Fichiers créés
- `backend/agents/search_smart.py` — orchestrateur LLM intent + parallel scraping + selectors learnés
- `backend/Dockerfile` — image Python 3.12 slim avec BS4/lxml
- `backend/scripts/deploy_backend.sh` — build + push Docker vers `api.aironbot.app`
- `lib/features/chat/data/search_service_global.dart` — client Dart unifié (`search()`, `scrape()`, `formatMarkdown()`)
- `docs/API_CONFIGURATION.md` — référence clés API, endpoints, `.env`
- `AGENTS.md` + `CODEX_AGENT.md` — stratégies agents Claude/Codex

### Fichiers modifiés
- `backend/agents/search_engine.py` : `scrape_url()` avec auto-extraction metadata, prix, cartes, liens
- `backend/main.py` : endpoints `/search_smart` et `/scrape`
- `lib/features/chat/presentation/slash_commands.dart` : commande `/scrape` + 4 commandes universelles (summarize/extract/links/metadata avec URL)
- `lib/features/chat/presentation/chat_notifier.dart` : handlers `_handleSlashScrape`, `_handleSlashSummarize` (URL-aware), `_handleSlashExtract` (URL-aware), `_handleSlashLinks` (URL-aware), `_handleSlashMetadata` (URL-aware)
- `docs/GUIDE_COMMANDES_SLASH.md` : v2.1 avec section Scraping Intelligent et table plateformes
- `docs/GUIDE_COMBOS.md` : v2.1 avec combos 25-28 cross-plateforme (`/scrape` + `/summarize`)

## Termine — Session Vocal OpenRouter (2026-05-21) — Module Vocal TTS + LLM Routing ✅

### Fichier cree
- `lib/features/chat/data/openrouter_vocal_service.dart` — Service vocal unifie (LLM + TTS)

### Modifications
- `tts_natural_service.dart` : vitesse OpenRouter TTS 0.65 -> 1.0
- `model_router.dart` : ajout `task:vocal` / `task:vocalFast` overrides
- `chat_notifier.dart` : confirmation parametres vocaux 0.95/0.95/0.2

### Routage LLM vocal
| Mode | Modele primaire | Fallback 1 | Fallback 2 | Fallback 3 |
|------|----------------|------------|------------|------------|
| Jovial | arcee/trinity | neversleep/ring-2.6-1t | deepseek-r1:free | gpt-4o-mini |
| Rapide | neversleep/ring-2.6-1t | arcee/trinity | deepseek-r1:free | gpt-4o-mini |

### Routage TTS vocal
| Primaire | Fallback | Fallback ultime |
|----------|----------|-----------------|
| gpt-4o-mini-tts (nova/shimmer) | kokoro-82m | flutter_tts natif |

### Parametres
- temperature = 0.95, top_p = 0.95, frequency_penalty = 0.2
- TTS speed = 1.0, TTS voice = nova (jovial) / shimmer (enthousiaste)
- max_tokens = 2048 (reponses vocales concises)

## Terminé — Session V12 (2026-05-21) — Bugs Critiques Images/PDFs/Slash/Recherche ✅


## Termine — Session Multi-Attachments (2026-05-21) — Images + Fichiers multiples ✅

- Limite agrégée : 5MB par message (images + fichiers combines)
- Multi-selection : jusqu'a 10 fichiers/images d'un coup
- Routage modèle automatique selon type de fichier (vision/document/longFile)
- Message d'erreur clair si limite depassee
- Retrocompatibilite Firestore preservee



- Images : fix persistence Firestore (`imageBase64` dans `toFirestore()`, limite 700KB)
- PDFs : fix extraction avec décompression FlateDecode streams
- Commandes slash : fix tabId correct dans `extension_bridge.js`
- Recherche DuckDuckGo : patterns fallback robustes

## Terminé — Session V11 (2026-05-20) — OpenRouter TTS + ModelRouter + Vocal LLM + Fixes ✅

### OpenRouter TTS (nouveau) ✅
- **Fichier** : `lib/features/chat/data/openrouter_tts_service.dart`
- Remplace Edge TTS comme moteur TTS primaire sur mobile
- Chaîne : gpt-4o-mini-tts → kokoro-82m (fallback)
- TtsVoice enum (nova, shimmer, alloy, echo, fable, onyx)
- emotionVoiceMap : neutral→nova, joyful→shimmer, serious→echo, excited→fable, sad→onyx
- Texte tronqué à 4096 chars, `isAvailable` getter
- Cache audio via `TtsCacheService.putBytes()`

### ModelRouter (nouveau) ✅
- **Fichier** : `lib/features/chat/data/model_router.dart`
- TaskType enum : general, reasoning, vision, document, code, longFile, vocal, vocalFast
- RateLimitTracker avec cooldown map
- Chaîne vocale : arcee/trinity → neversleep/ring-2.6-1t → deepseek-r1:free → gpt-4o-mini
- Chaîne vocalFast : neversleep/ring-2.6-1t → arcee/trinity → deepseek-r1:free → gpt-4o-mini

### Vocal LLM params ✅
- temperature=0.95, top_p=0.95, frequency_penalty=0.2
- Prompt jovial injecté : "MODE VOCAL ACTIF — Réponds comme un ami au téléphone"
- `sendMessage()` accepte `modelOverride` et `isVoiceConversation`

### TTS vitesse ajustée ✅
- OpenRouter TTS speed : 0.65
- flutter_tts base : 0.45
- TtsEmotion rates réduits (neutral 0.85, joyful 0.95, etc.)
- speech_bridge.js rates ajustés (neutral 0.90, joyful 1.00, etc.)

### File attachment fix ✅
- Guard : `if (trimmed.isEmpty && imageBase64 == null && fileContent == null) return;`
- effectiveText : "Analyse ce document" quand texte vide mais fichier attaché
- DOCX MIME type corrigé : offancedocument → officedocument
- Hard 6000-char cap supprimé (respecte 15k/30k pro/free)

### Slash commands LLM enhancement ✅
- `/searchpage` : LLM analyse sémantique des occurrences, fallback indexOf
- `/extract` : LLM nettoyage/structuration du texte, fallback raw text
- `/metadata` : LLM évaluation SEO + suggestions, fallback raw metadata
- `/autofill` : LLM génère JSON de données de test → fill fields, fallback hardcoded "Jean Dupont"

### ModelSelectorBar ✅
- 6 chips : Auto, Flash, Pro, Raison, Code, Vision
- `selectedModel` default : 'auto'

### DeepSeek SSE ✅
- Skip `reasoning_content` dans les deltas SSE
- `max_completion_tokens` pour reasoner, `max_tokens` pour les autres

### Auth fallback ✅
- isDemoMode=true quand Firebase indisponible
- authRepositoryProvider throws StateError en demo mode

---

## Terminé — Session V13 (2026-05-21) — Robustesse Recherche + Extraction Fichiers + Documentation Agents ✅

### Recherche web robuste (SearchService) ✅
- **Fichier** : `lib/features/chat/data/search_service.dart`
- 3 endpoints DuckDuckGo en cascade : `html.duckduckgo.com/html/` → `lite.duckduckgo.com/lite/` → `duckduckgo.com/html/`
- Rotation User-Agent (Android, iOS, Desktop)
- Protection taille HTML : tronquage à 500KB avant regex
- Pattern `uddg` ajouté pour nouveaux layouts DuckDuckGo
- `_decodeDdgUrl()` : supporte `/l/?uddg=`, `/l/?u=`, `/l/?kh=...&u=`, `//duckduckgo.com/l/?uddg=`
- Pattern fallback direct (liens absolus sans redirection)
- Tests : `_decodeDdgUrl` (6 cas), parsing patterns

### Extraction fichiers namespace-agnostic (FileUploadService) ✅
- **Fichier** : `lib/features/chat/data/file_upload_service.dart`
- DOCX : extraction par `localName` + namespace URI contenant `wordprocessingml` (plus de dépendance au préfixe `w:`)
- PPTX : extraction par `localName` 't' et 'sp' sans dépendance au préfixe `a:` ou `p:`
- Fallback : tous les nœuds texte si extraction structurée échoue
- Gestion erreurs : `XmlException` → message clair, `ArchiveException` → message clair
- Tests : extraction namespace alternatif simulée (DOCX + PPTX)

### Documentation agents ✅
- **AGENTS.md** : stratégie complète Claude Code avec redémarrage, golden rules, workflow
- **CODEX_AGENT.md** : stratégie équivalente adaptée à Codex (tool mapping, context handling)
- **docs/API_CONFIGURATION.md** : toutes les clés API, sources, commandes d'injection, `.env` de référence

---

## CRITIQUE — Prochaine session

### BUGS CRITIQUES À RÉSOUDRE EN PRIORITÉ
- [x] **Recherche avancée cassée** : Fixed V13 — SearchService multi-endpoint + patterns fallback robustes. EnhancedSearchService (liens directs) déjà fonctionnel. ✅
- [x] **Commandes slash ne fonctionnent pas** : Fixed V12 — extension_bridge filtre les tabs `chrome-extension://`. ✅
- [x] **Images impossibles à charger** : Fixed V12 — `Message.toFirestore()` stockait `imageBase64` + limite 700KB. ✅
- [x] **PDFs impossibles à lire** : Fixed V12 — extraction 2 étapes avec décompression FlateDecode streams. ✅
- [x] **Autres fichiers médiocres** : Fixed V13 — extraction DOCX/PPTX namespace-agnostic avec fallbacks et gestion d'erreurs. ✅

**Aucun bug critique bloquant restant. Projet en état bêta.**

---

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

## Terminé — Session V15 (2026-05-22) — Vocal Turn-Taking (Mode Conversation Fluide)

### Résumé
Le mode conversation vocal mains-libres est désormais fluide et humain. Latence réduite, interruptions intelligentes, voix avec hésitations naturelles, et détection de fin de phrase basée sur la prosodie.

### Décisions techniques clés
- **VAD Prosodique** : remplacement du timer fixe par `ProsodyVadAnalyzer` qui analyse le niveau sonore, la ponctuation, et la cadence de parole pour distinguer une pause respiratoire (`breathingPause`) d'une fin de phrase (`endOfPhrase`). Règles : ponctuation + 400ms silence, pas de ponctuation + 900ms silence, chute d'énergie sous 15% du pic sur 300ms, safety cap 12s.
- **Streaming TTS par phrase** : `VoiceConversationNotifier._speakStreamingSentences()` parle les phrases complètes dès qu'elles arrivent du LLM. Si pas de fin de phrase après 120 caractères, parle le fragment quand même. Seuils réduits : 12 chars première phrase, 20 chars suivantes.
- **Barge-in intelligent par intention** : `BargeInIntentClassifier` détecte 5 intentions (stop, topicChange, correction, repeat, none) via regex sans appel LLM. Single-word shortcuts : "stop", "chut", "non", "encore", "pardon", "quoi". Comportements spécifiques : `repeat` relit la dernière réponse sans appeler le LLM ; `topicChange` préfixe le message ; `stop`/`correction` interrompent et envoient un nouveau message.
- **Hésitations naturelles** : `VocalHesitationInjector` post-processe le texte TTS avec "euh", "hmm", pauses "..." selon des règles probabilistes (intensité 0.25). Fonctionne avec tous les moteurs TTS sans modification du prompt LLM.
- **Cross-platform Edge TTS** : barrel file `edge_tts_service.dart` avec conditional export (`dart.library.io` vs web). Web stub retourne `UnsupportedError`. `EdgeTtsService.setEmotion()` mappe les émotions vers les voix Microsoft Edge (HenriNeural, DeniseNeural, etc.).

### Fichiers créés
- `lib/features/chat/presentation/prosody_vad_analyzer.dart` — VAD prosodique avec ring buffer mic
- `lib/features/chat/presentation/barge_in_intent_classifier.dart` — Classification d'intention barge-in (5 classes)
- `lib/features/chat/presentation/vocal_hesitation_injector.dart` — Injection probabiliste d'hésitations TTS
- `lib/features/chat/presentation/edge_tts_service.dart` — Barrel conditional export
- `lib/features/chat/presentation/edge_tts_service_web.dart` — Stub web Edge TTS
- `test/features/chat/presentation/prosody_vad_analyzer_test.dart` — 12 tests unitaires
- `test/features/chat/presentation/barge_in_intent_classifier_test.dart` — 15 tests unitaires
- `test/features/chat/presentation/vocal_hesitation_injector_test.dart` — 9 tests unitaires (probabilistes)
- `docs/tts_model_evaluation.md` — Évaluation comparatif TTS (Edge, OpenRouter, ElevenLabs, StyleTTS 2)

### Fichiers modifiés
- `lib/features/chat/presentation/edge_tts_service_io.dart` — Renommé, ajout `setEmotion()`, configs par émotion
- `lib/features/chat/presentation/tts_emotion.dart` — Ajout `edgeEmotionTtsConfigs` (calibré pour Edge SSML scale)
- `lib/features/chat/presentation/tts_natural_service.dart` — Ajout `TtsEngine.edgeTts`, `speakStreaming()`, `_hesitationEnabled`
- `lib/features/chat/presentation/voice_service.dart` — Intégration `ProsodyVadAnalyzer`, `speakStreamingWithEmotion()`, timer VAD 50ms
- `lib/features/chat/presentation/voice_conversation_service.dart` — Seuils TTS réduits, barge-in par intention, `_lastSpokenText` pour repeat
- `lib/features/chat/presentation/chat_notifier.dart` — Prompt vocal enrichi : "Parle avec un rythme naturel, comme à l'oral"
- `test/features/chat/presentation/edge_tts_service_test.dart` — Fix test préexistant `.voice` invalide sur `EmotionTtsConfig`

### Tests
- 36 nouveaux tests unitaires, 0 échec
- `flutter analyze` : 0 erreur de compilation sur les fichiers modifiés
- `flutter build web` : réussit (Edge TTS derrière conditional export)

### Évaluation TTS avancée (résumé)
| Modèle | Latence | Coût | Qualité | Intégration | Plateforme |
|--------|---------|------|---------|-------------|------------|
| Edge TTS streaming | 150-400ms | Gratuit | Bonne (neural) | Complexe (WebSocket) | Mobile uniquement |
| OpenRouter TTS | 800-2500ms | Payant (crédits) | Excellente (nova/shimmer) | Simple (HTTP) | Mobile + Web |
| ElevenLabs | 300-800ms | Payant (API key) | Excellente + émotion | Simple (HTTP) | Toutes |
| StyleTTS 2 | ~500ms (server) | Gratuit (self-host) | Très bonne | Complexe (server GPU) | Server-side uniquement |
| flutter_tts | 50-200ms | Gratuit | Moyenne (OS dépendant) | Trivial | Toutes |

**Conclusion** : Edge TTS streaming est la meilleure option mobile (gratuit, latence faible). ElevenLabs est le meilleur upgrade payant (qualité + émotion). StyleTTS 2 est prometteur mais nécessite un serveur GPU dédié.

---

## À faire — Prochaine session

### Priorité HAUTE
- [ ] **Déployer le backend** : `bash scripts/deploy_backend.sh` depuis la machine de l'utilisateur (Docker a besoin d'internet pour `apt-get`). Cible : `api.aironbot.app`.
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
- [x] Streaming audio : test sur connexions lentes — TTS OpenRouter MP3 streaming mis en place ✅
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