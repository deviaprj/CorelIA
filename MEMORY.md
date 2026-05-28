# AironBot — Mémoire de Projet

Ce fichier contient les connaissances clés et décisions importantes pour le développement continu d'AironBot.

---

## Architecture & Conventions

### State Management
- **Riverpod** pour tout le state management
- `AsyncNotifierProvider` pour les notifiers avec état async
- `StreamProvider.family` pour les streams Firestore paramétrés
- `Provider` pour les services singleton

### Structure des Features
```
features/
├── auth/
├── chat/
├── projects/
├── monetization/
│   ├── ads/
│   └── subscription/
├── onboarding/
└── settings/
```

Chaque feature suit le pattern :
- `domain/` — Entités/models
- `data/` — Repositories, API clients, services
- `presentation/` — Screens, widgets, notifiers

### Firebase
- Project ID : `aironbot-1773058753`
- Collections : `users`, `conversations`, `messages`, `projects`, `referrals`
- Cloud Functions : `checkQuota`, `stripeWebhook`

---

## Décisions Techniques

### IA & API Keys
- **DeepSeek-V3** pour le tier gratuit (deepseek-chat)
- API keys via `--dart-define` depuis `.env`
- Clé personnelle DeepSeek stockable dans `SecureStorageService`

### Quotas
- Gratuit : 50 requêtes/jour (reset à minuit UTC)
- Pro : illimité
- Vérification server-side via Cloud Function `checkQuota`
- Mode dégradé si Cloud Function indisponible

### Monetization
- **RevenueCat** pour mobile (iOS/Android)
- **Stripe** pour web/extension (via webhook)
- AdMob pour les pubs (bannières, interstitials, rewarded)
- Entitlement Pro : `pro`

### Plateformes
- Mobile : Android API 26+, iOS 15+
- Extension Chrome : Manifest V3, Flutter Web build
- Desktop : non supporté nativement (fallback web)

---

## Patterns Récurrents

### Chat Streaming
```dart
final buffer = StringBuffer();
await for (final token in stream) {
  buffer.write(token);
  // Mise à jour state avec buffer
}
```

### Firestore Realtime
```dart
Stream<List<T>> watchCollection(String userId) {
  return firestore.collection('...')
      .where('userId', isEqualTo: userId)
      .snapshots()
      .map((s) => s.docs.map(T.fromFirestore).toList());
}
```

### Riverpod Family Providers
```dart
final myProvider = StreamProvider.family<T, String>(
  (ref, param) => ...
);
```

---

## Pièges & Solutions Connues

| Problème | Solution |
|----------|----------|
| `.take(n)` sur un stream prend les **premiers** éléments | Utiliser `.toList().reversed.take(n).reversed` pour les derniers |
| `http.Client()` non disposed | Utiliser un singleton `_httpClient` |
| Pro mode forcé à `true` en prod | Bug corrigé — vérifier `subscription_service.dart` |
| Secrets Firebase Functions | Utiliser `firebase functions:secrets:set` |

---

## Commandes Utiles

```bash
# Tests
bash scripts/run_tests.sh all
flutter test test/features/chat/chat_screen_test.dart

# Build extension
bash scripts/build_extension.sh

# Deploy functions
cd functions && npm run deploy

# Secrets Firebase
firebase functions:secrets:set STRIPE_SECRET_KEY
firebase functions:secrets:set STRIPE_WEBHOOK_SECRET
```

---

## TODO Long Terme

- [ ] Implémenter le système de parrainage (champs `referralCode`, `referredBy` dans `AppUser`)
- [ ] Export PDF des conversations (feature Pro)
- [ ] Gestion de fichiers dans le chat (upload Firebase Storage)
- [ ] Analytics d'usage pour métriques virales
- [ ] Unifier Stripe (web) et RevenueCat (mobile) en un seul système

---

## Sessions Récentes

### Session 2026-05-28 — Thème Cofely Unifié + Icônes V20

#### Refonte thème : login_screen + onboarding
**Problème** : Login screen et onboarding screen utilisaient encore `#6C63FF` (violet AironBot), pas le thème Cofely.
**Fix login** : `build()` entièrement réécrit — en-tête dégradé `#001218→#003F5C`, logo "C" cercle gradient 72px, carte blanche arrondie, `FilledButton` en `CofelyTokens.primary`.
**Fix onboarding** : `_pages` avec nouveaux gradients bleus Cofely, `_PageContent` : logo "C" pour page 1, icônes dans cercles semi-transparents pour pages 2-3.

#### Génération icônes Python PIL
**Design** : fond dégradé diagonal `#00121E → #003F5C`, arc "C" blanc épais centré, halo accent `#58B4D1`.
**Script** : `make_gradient_bg()` pixel-par-pixel, `draw_c_on()` avec superposition d'arcs, `make_icon()` avec masque rounded_rectangle ou ellipse.
**Produit** : 10 fichiers Android (mipmap-*) + 9 icônes web PWA + 5 extension Chrome.
**Règle** : toujours vérifier `img.getpixel()` centre + zone "C" après génération pour s'assurer que le design est correct.

#### CofelyTokens — design system source de vérité
- `primary = #003F5C`, `accent = #58B4D1`, `avatarGradient` LinearGradient const
- Toujours importer `'../../../app/cofely_theme.dart'` (chemin relatif selon profondeur)
- `DialogTheme` (PAS `DialogThemeData`), `Chip` sans `tooltip`

### Session 2026-05-27 — TTS Anti-Saccade + DocGen PNG

#### Bug Critique : Voix TTS saccadée/robotique
**Cause racine 1** : `_splitForNaturalSpeech()` découpait les phrases à 120 chars via `substring(i, end)` — coupe **au milieu d'un mot** sur presque toutes les phrases françaises (avg 140-200 chars).
**Cause racine 2** : Pause de 250ms entre **chaque chunk** → rythme robotique mécanique.
**Solution** : Réécriture complète de `_splitForNaturalSpeech()` + nouvelle méthode `_splitLongSentence()` :
- Chunks max 300 chars (`_maxTtsChunk = 300`)
- Priorité : limites de phrases (`.!?`) → clauses (`,;`) → mots (jamais mid-word)
- Pause inter-phrase : 250ms → **60ms**, paragraphe : 500ms → **350ms**
- `_speechRate` : 0.45 → **0.42**, `_pitch` : 1.15 → **1.10**
- `emotionTtsConfigs` : toutes les rates réduites ~10%
**Fichiers** : `tts_natural_service.dart`, `tts_emotion.dart`
**Règle** : si un bug TTS est patché 2+ fois sans résultat → réécriture complète de la méthode de découpage

#### Bug DocGen : PNG toujours en JPEG
**Cause** : `_toImage()` ignorait le paramètre `format`, fetchait toujours JPEG de Pollinations.
**Fix** : Ajout `&format=jpeg|png` dans l'URL Pollinations.
**Fichier** : `document_generation_service.dart`

#### État tests
- 18/18 tests TTS passés ✅
- 508/511 tests chat passés (+3 pré-existants phonetic_liaison) ✅

---

### Session 2026-05-04

#### Bug Critique: Mode Vocal Se Coupe Instantanément
**Problème**: Le micro n'était pas activé quand l'utilisateur déclenchait le mode vocal. Le code affichait "Écoute en cours..." mais n'enregistrait rien.

**Cause**: Le code `startListening()` n'verifie pas la permission du microphone avant d'appeler `_stt.listen()`.

**Solution**: Ajout de la vérification explicite de permission dans `VoiceServiceNotifier.startListening()`:
```dart
final status = await Permission.microphone.status;
if (!status.isGranted) {
  final result = await Permission.microphone.request();
  if (!result.isGranted) {
    state = state.copyWith(isListening: false);
    return;
  }
}
```

**Optimisation**: Permission mise en cache (`_microphonePermissionGranted`) pour éviter les vérifications redondantes.

#### Code Quality & Efficiency Fixes (via /simplify agent)
1. **RegExp recreé à chaque appel** - Fix: `static final` pour `_urlPattern` et `_citationPattern` dans `tts_natural_service.dart`
2. **Polling loop inutile dans `speakNaturally()`** - Fix: utiliser directement `completer.future` au lieu de polling
3. **Timer unused `_timeoutTimer`** - Fix: suppression du champ et du cancel
4. **Polling loop trop agressif (150ms)** - Fix: optimisé avec mise à jour conditionnelle du transcript
5. **Permission check on every call** - Fix: cached after first grant

#### Files Modified
- `lib/features/chat/presentation/voice_conversation_service.dart`
- `lib/features/chat/presentation/voice_service.dart`
- `lib/features/chat/presentation/tts_natural_service.dart`
- `lib/features/chat/presentation/aurora_splash.dart`
- `lib/features/chat/presentation/chat_screen.dart`
- `lib/features/chat/data/quota_service.dart`
- `lib/features/chat/data/file_quota_service.dart`
- `lib/features/chat/data/image_upload_service.dart`
- `lib/features/chat/domain/message.dart`
- `lib/features/chat/data/ollama_local_client.dart` (supprimé)

---

*Dernière mise à jour : 2026-05-21*

### Session 2026-05-21

#### Bug Critique: Images impossibles à charger
**Problème**: `Message.toFirestore()` ne stockait pas `imageBase64`, donc les images disparaissaient après rechargement Firestore.
**Fix**: `toFirestore()` inclut maintenant `imageBase64` si < 900000 chars. Limite image réduite à 700KB pour respecter la limite Firestore (~1MB document).
**Fichiers modifiés**: `lib/features/chat/domain/message.dart`, `lib/features/chat/data/image_upload_service_io.dart`, `lib/features/chat/data/image_upload_service_web.dart`

#### Bug Critique: PDFs impossibles à lire
**Problème**: `_extractPdf()` ne décompressait pas les streams FlateDecode, échouant sur 90% des PDFs modernes.
**Fix**: Extraction en 2 étapes — directe puis décompression des streams PDF avec `inflateBuffer` du package `archive`. Nouvelles méthodes : `_extractFromPdfStreams`, `_findPdfStreams`, `_extractPdfStringsFromDecoded`, `_deduplicateStrings`, `_isPdfWhitespace`, `_indexOfBytes`. Classe `_PdfStream` ajoutée.
**Fichiers modifiés**: `lib/features/chat/data/file_upload_service.dart`

#### Bug Critique: Commandes slash extension cassées
**Problème**: `chrome.tabs.query({ active: true, currentWindow: true })` dans `extension_bridge.js` retournait parfois le side panel lui-même (URL `chrome-extension://`) au lieu de la page web active, causant des timeouts et échecs d'injection `dom_actions.js`.
**Fix**: Filtre explicite des tabs `chrome-extension://` pour obtenir le vrai tab actif de la page web.
**Fichiers modifiés**: `web/extension_bridge.js`

#### Bug Haute: Recherche DuckDuckGo scraping fragile
**Problème**: DuckDuckGo a changé son markup HTML, cassant les regex d'extraction.
**Fix**: Ajout de patterns fallback plus robustes (liens directs sans encodage, ultra-souple générique).
**Fichiers modifiés**: `lib/features/chat/data/search_service.dart`

### Session 2026-05-21 (suite)

#### Vérification et correction des commandes slash
**Problèmes identifiés** :
1. `_handleSlashPdf` ouvrait une URL puis immédiatement `saveAsPdf` sans attendre le chargement → PDF de l'ancienne page.
2. `_handleSlashSummarize`, `_handleSlashExtract`, `_handleSlashMetadata`, `_handleSlashSearchPage`, `_handleSlashTranslate` appelaient `sendMessage()` mais `sendMessage` avait une guard `if (state.isStreaming) return;` qui bloquait silencieusement si un streaming était en cours.
3. `_handleSlashScreenshot` ne retournait pas l'image capturée — juste un message texte.
4. `_handleSlashMonitor` affichait "Surveillance activée" mais c'était une vérification ponctuelle.
5. `_handleSlashTables` crash potentiel si `rowCount` était null.

**Fixs appliqués** :
1. `_handleSlashPdf` : retiré l'ouverture auto d'URL. Utilisateur fait `/open <url>` puis `/pdf [filename]` (combo explicite).
2. `sendMessage` : ajout paramètre `bypassSlashCheck = false`. Quand true, contourne le guard `isStreaming`. Tous les handlers LLM slash utilisent `bypassSlashCheck: true`.
3. `_handleSlashScreenshot` : télécharge la capture via `DOWNLOAD_DATA` (PNG base64 → blob → téléchargement).
4. `_handleSlashMonitor` : message changé en "Vérification ponctuelle" avec suggestions de combos.
5. `_handleSlashTables` : null-safe pour `rowCount` et `colCount` (`?? '?'`).

**Vérification combos** :
- `/links` → `/download` : `_lastLinksForDownload` + `_lastLinksFilter` persistés ✅
- `/open <url>` → `/pdf [filename]` : combo explicite fonctionnel ✅
- `/forms [index]` → `/autofill` : `_handleSlashAutofill` extrait les formulaires puis remplit champ par champ ✅
- `/tables` → `/export csv` : `_handleSlashExport` extrait les tableaux et génère CSV ✅
- `/media images` → `/download <url>` : message guide l'utilisateur ✅
- `/waitfor <selector>` → `/click <selector>` → `/fill <selector> <value>` : séquence DOM standard ✅
- `/searchpage <term>` → `/extract <selector>` : séquence extraction + analyse ✅
- `/summarize` : standalone appelant `sendMessage` avec contenu de page ✅
- `/docgen` : universel (mobile + extension) ✅

### Session 2026-05-21 — Module Vocal OpenRouter

#### Amelioration du module vocal (OpenRouter TTS + routage LLM vocal)
**Objectifs** :
1. Remplacer l'ancien TTS par OpenRouter TTS performant (gpt-4o-mini-tts -> kokoro-82m)
2. Choisir un LLM de dialogue vocal optimise (arcee/trinity joyeux, neversleep/ring rapide)
3. Mettre en place un routage intelligent avec fallback
4. Adapter les parametres (temperature, top_p, frequency_penalty) pour conversation vocale

**Fichier cree** : `lib/features/chat/data/openrouter_vocal_service.dart`
- `OpenRouterVocalService.getVocalResponse(prompt, history, useJovial)` : routage LLM vocal
  - useJovial=true  -> arcee/trinity (gratuit, joyeux)
  - useJovial=false -> neversleep/ring-2.6-1t (gratuit, rapide)
  - Fallback : deepseek/deepseek-r1:free -> openai/gpt-4o-mini
  - Parametres : temperature=0.95, top_p=0.95, frequency_penalty=0.2, max_tokens=2048
- `OpenRouterVocalService.synthesizeVocal(text, voice, speed)` : TTS avec fallback
  - gpt-4o-mini-tts (nova/shimmer) -> kokoro-82m
  - Vitesse = 1.0 (au lieu de 0.65 precedemment)
- `OpenRouterVocalService.defaultVoice(useJovial)` : shimmer pour jovial, nova pour neutre
- `OpenRouterVocalService.voiceForEmotion(emotionName)` : mapping emotion -> voix

**Fichiers modifies** :
- `lib/features/chat/presentation/tts_natural_service.dart` : `_openRouterTtsSpeed` passe de 0.65 a 1.0
- `lib/features/chat/data/model_router.dart` : ajout `task:vocal` et `task:vocalFast` dans `resolveModel`
- `lib/features/chat/presentation/chat_notifier.dart` : parametres vocaux deja a 0.95/0.95/0.2 (confirmation)
- `lib/features/chat/presentation/voice_conversation_service.dart` : deja utilise `modelOverride: 'task:vocal'`

**Parametres LLM vocaux confirmes** :
- temperature = 0.95
- top_p = 0.95
- frequency_penalty = 0.2
- max_tokens = 2048 (limite vocale pour reponses concises)

**Prompt systeme vocal par defaut** :
"MODE VOCAL ACTIF — Reponds comme un ami au telephone : jovial, naturel, concis (2-3 phrases max), pas de listes, pas de markdown. Tutoie, sois chaleureux et dynamique. Pas de 'En tant qu'IA' ni d'excuses inutiles. Va droit au but avec le sourire."

**Mapping voix TTS OpenRouter** :
- neutral -> nova
- joyful/friendly/cheerful -> shimmer
- excited -> fable
- serious -> echo
- sad -> onyx

### Session 2026-05-21 — Multi-Attachments (images + fichiers)

#### Objectif
Permettre d'ajouter plusieurs images et fichiers dans un meme message, avec limite agrégée de 5MB par message.

#### Fichier cree
- `lib/features/chat/domain/attachment.dart` — Modele Attachment avec types (image, pdf, document, spreadsheet, presentation, text)

#### Fichiers modifies
- `lib/features/chat/domain/message.dart` — Remplace champs legacy (imageBase64, fileName, fileContent) par `List<Attachment> attachments`. Retrocompatibilite Firestore preservee.
- `lib/features/chat/data/image_upload_service_io.dart` — `pickFromGallery()` retourne `List<Attachment>`, support multi-image, limite 5MB agrégée
- `lib/features/chat/data/image_upload_service_web.dart` — Meme changement pour web/extension
- `lib/features/chat/data/file_upload_service.dart` — `pickAndExtract()` retourne `List<Attachment>`, support multi-fichier, limite 5MB agrégée
- `lib/features/chat/presentation/chat_notifier.dart` — `sendMessage()` accepte `List<Attachment>`, verification 5MB, routage modèle auto depuis types d'attachments
- `lib/features/chat/presentation/input_bar.dart` — Affiche plusieurs attachments en chips, envoi par liste
- `lib/features/chat/presentation/chat_screen.dart` — `_pendingAttachments` devient une liste, ajout cumulatif
- `lib/features/chat/data/model_router.dart` — `classifyTask()` accepte `attachmentTypes` pour router vers vision/document/longFile

#### Message d'erreur si limite depassee
"Taille limite depassee (5MB par message). Vous pouvez ajouter plusieurs fichiers, mais la taille totale ne doit pas depasser 5MB."

#### Routage automatique du modele selon les pieces jointes
| Types d'attachments | Modele choisi |
|---------------------|---------------|
| Images | TaskType.vision -> gemini-flash / deepseek-chat |
| PDF/DOCX/XLSX/PPTX | TaskType.document -> deepseek-v4-pro |
| TXT/CSV/MD | TaskType.longFile -> deepseek-v4-pro / mistral-7b |

#### Exemple d'utilisation
- Ajouter 10 images de 500Ko chacune = 5MB total, OK
- Ajouter 3 PDFs de 2Mo = 6MB total, refuse avec message clair
- Ajouter 1 image + 1 PDF = OK si total <= 5MB


### Session 2026-05-21 — Reprise : Corrections Multi-Attachments + Tests + Builds

#### Bugs critiques corrigés
1. **chat_screen.dart** : `_pendingAttachment` (indéfini) → `_pendingAttachments` (liste). Support cumulatif multi-fichiers.
2. **chat_notifier.dart** : `sendMessage()` accepte maintenant `List<Attachment>? attachments`. Vérification 5MB agrégée. Passage des attachments à `_buildStream` et aux repositories.
3. **chat_notifier.dart** : `_getDirectAiStream` accepte `List<String>? attachmentTypes`.
4. **model_router.dart** : `classifyTask` accepte `attachmentTypes` → routage auto vision/document/longFile.
5. **firestore_chat_repository.dart + mock_chat_repository.dart** : `addMessage` accepte `List<Attachment>? attachments` et les persiste dans `Message`.
6. **_buildAttachmentContextForHistory** : gère `List<Attachment>` pour injecter le contexte de tous les documents.

#### Tests ajoutés
- `test/features/chat/data/model_router_test.dart` — Routage modèle par type de pièce jointe
- `test/features/chat/multi_attachment_integration_test.dart` — Limite 5MB, API multimodal, contexte fichier
- `test/features/chat/slash_commands_e2e_test.dart` — Combos slash et mapping BrowserAction
- `test/features/chat/data/openrouter_vocal_service_comprehensive_test.dart` — Mapping voix/émotions, chaînes LLM

#### Compilation
- APK Android (Xiaomi 12 & Xiaomi 8 Pro) : en cours (nécessite escalation sandbox)
- Extension Chrome : en cours (nécessite escalation sandbox)

### Session 2026-05-21 — Scraping Intelligent Cross-Plateforme (V14)

#### Objectif
Rendre la recherche avancée réellement utile en scrapant les comparateurs pour obtenir des prix/offres concrets, et rendre les commandes slash universelles (mobile/web/extension) via le backend cloud.

#### Fichiers créés
- `backend/agents/search_smart.py` — Orchestrateur LLM intent + parallel multi-source scraping + learned selectors
- `backend/Dockerfile` — Python 3.12 slim + BS4/lxml + uvicorn 4 workers
- `scripts/deploy_backend.sh` — Build Docker → tar.gz → scp → docker compose up
- `lib/features/chat/data/search_service_global.dart` — Client Dart unifié `search()`, `scrape()`, `formatMarkdown()`
- `docs/API_CONFIGURATION.md` — Référence complète clés API, endpoints, `.env`
- `AGENTS.md` + `CODEX_AGENT.md` — Stratégies agents Claude Code et Codex

#### Fichiers modifiés
- `backend/agents/search_engine.py` : `scrape_url()` avec auto-extraction metadata, prix (regex currency), cartes (class heuristiques), liens. Support sélecteurs CSS custom.
- `backend/main.py` : endpoints `/search_smart` (GET `q`) et `/scrape` (GET `url`, `selectors`)
- `lib/features/chat/presentation/slash_commands.dart` : commande `/scrape` + universalCommandNames (`docgen`, `scrape`, `summarize`, `extract`, `links`, `metadata`)
- `lib/features/chat/presentation/chat_notifier.dart` : 5 handlers URL-aware (`_handleSlashScrape`, `_handleSlashSummarize`, `_handleSlashExtract`, `_handleSlashLinks`, `_handleSlashMetadata`). Si arg commence par `http` → backend `/scrape`.
- `docs/GUIDE_COMMANDES_SLASH.md` : v2.1 (2026-05-21) avec section "Scraping intelligent" et table des plateformes (Extension vs Universel)
- `docs/GUIDE_COMBOS.md` : v2.1 (2026-05-21) avec combos 25-28 cross-plateforme (`/scrape` + `/summarize`)

#### Architecture `/search_smart`
1. **Intent classification** : DeepSeek/OpenRouter LLM analyse la requête → intent (flights, hotels, products, secondhand, restaurants, events, weather, general) + paramètres structurés
2. **URL building** : comparateurs avec params pré-remplis (Skyscanner, Booking, Back Market, eBay, Leboncoin, etc.)
3. **Parallel scraping** : `asyncio.gather` sur ~5 URLs max, timeout 8s par source
4. **Learned selectors** : `_LEARNED_SELECTORS` en mémoire mappe les domaines vers les sélecteurs CSS prix/titre
5. **Auto-extraction fallback** : si pas de sélecteur connu, BS4 cherche les patterns communs (`.price`, `[class*='result']`, etc.)
6. **Résultat** : `SmartSearchResponse` avec `SmartSearchResult` (type: price/card/link) + sources

#### Formatters markdown
- `flights` : ✈️ Vols trouvés → prix détectés + résultats + liens
- `hotels` : 🏨 Hébergements → tableau | Établissement | Prix |
- `products/secondhand` : 🛒/🔄 → tableau | Produit | Prix | Source |
- `restaurants` : 🍽️ Restaurants → liste avec snippets
- `events` : 🎭 Événements → liste avec snippets
- `weather` : ☀️ Météo → cartes
- `general` : 🔍 Résultats → liste + sources

#### Slash commands universels — comportement
| Commande | Extension (sans URL) | Mobile/Web (avec URL) |
|----------|---------------------|----------------------|
| `/summarize` | Résume la page active | Scrape l'URL + résume |
| `/extract [selector]` | Extrait le DOM local | Scrape l'URL + extrait sélecteur |
| `/links [filter]` | Liens de la page active | Liens scrapés de l'URL |
| `/metadata` | Meta tags de la page active | Meta tags scrapés de l'URL |
| `/scrape <url>` | N/A (nécessite URL) | Scrape complet prix/cartes/liens |

#### Backend deployment
- Dockerfile buildée localement mais `apt-get` échoue sans internet (DNS Docker local).
- **Action requise** : exécuter `bash scripts/deploy_backend.sh` depuis la machine de l'utilisateur où Docker a internet.
- Cible : `api.aironbot.app` (FastAPI + uvicorn 4 workers + Docker).

#### Notes pour la prochaine session
- **Vocal turn-taking** : priorité CRITIQUE. L'IA doit savoir exactement quand parler sans couper la parole. Cela passe par :
  1. Détection de fin de phrase intelligente (prosodie, pas juste silence)
  2. Latence quasi nulle entre la fin de phrase utilisateur et le début du son IA (<300ms)
  3. Voix qui respire : hésitations naturelles ("euh", "hmm"), intonations, pauses
  4. Modèles à évaluer : **StyleTTS 2** (open-source, fine-grained style control) et **ElevenLabs** (multilingue, low-latency, émotion)
  5. Barge-in intelligent : ne pas interrompre l'utilisateur sauf "stop" explicite ou changement de sujet clair
- **Tests parsing vols** : tester en conditions réelles avec requêtes lowercase + mots parasites

---

*Dernière mise à jour : 2026-05-21*
