# CorelIA — Mémoire de Projet

Ce fichier contient les connaissances clés et décisions importantes pour le développement continu d'CorelIA.

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
- Project ID : `corelia-1773058753`
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

### Session 2026-06-27 — Intégration OmniVoice TTS + Nettoyage HTML TTS

#### OmniVoice TTS (k2-fsa/OmniVoice 0.1.5)
- **Modèle** : State-of-the-art TTS 646 langues (FR : 23 675h)
- **Backend** : `backend/voice/omnivoice_tts.py` — service Python avec GPU auto-detect (CUDA/MPS/XPU/CPU)
- **Endpoints** : `POST /voice/omnivoice`, `/voice/omnivoice/stream`, `/voice/design`, `/voice/clone`, `GET /voice/status`
- **Mode** : Auto Voice (le plus fiable pour FR). Voice Design uniquement EN+ZH.
- **CPU** : `num_step=8` (rapide), RTF ~1.8x sur AMD EPYC 12 cœurs
- **Fallback** : OmniVoice → OpenRouter (Pro) → flutter_tts (gratuit universel)
- **Client Flutter** : `lib/features/chat/data/omnivoice_tts_service.dart` — HTTP vers backend

#### Nettoyage HTML TTS
- HTML tags strip déplacé en **étape 0** de `cleanMarkdown()` (avant : étape 11/15)
- Ajout `decodeHtmlEntities()` : `&amp;` → `&`, `&lt;` → `<`, etc.
- Regex `<[^>]*>` avec `dotAll: true` pour balises multi-lignes

#### Déploiement VPS (Hetzner 167.233.100.132)
- OmniVoice 0.1.5 installé dans `.venv`
- Nginx reverse proxy port 80 → 8000
- Port 8000 ouvert dans UFW
- Backend lancé via `nohup uvicorn`

### Session 2026-05-28 — Thème Corely Unifié + Icônes V20

#### Refonte thème : login_screen + onboarding
**Problème** : Login screen et onboarding screen utilisaient encore `#6C63FF` (violet CorelIA), pas le thème Corely.
**Fix login** : `build()` entièrement réécrit — en-tête dégradé `#001218→#003F5C`, logo "C" cercle gradient 72px, carte blanche arrondie, `FilledButton` en `CorelyTokens.primary`.
**Fix onboarding** : `_pages` avec nouveaux gradients bleus Corely, `_PageContent` : logo "C" pour page 1, icônes dans cercles semi-transparents pour pages 2-3.

#### Génération icônes Python PIL
**Design** : fond dégradé diagonal `#00121E → #003F5C`, arc "C" blanc épais centré, halo accent `#58B4D1`.
**Script** : `make_gradient_bg()` pixel-par-pixel, `draw_c_on()` avec superposition d'arcs, `make_icon()` avec masque rounded_rectangle ou ellipse.
**Produit** : 10 fichiers Android (mipmap-*) + 9 icônes web PWA + 5 extension Chrome.
**Règle** : toujours vérifier `img.getpixel()` centre + zone "C" après génération pour s'assurer que le design est correct.

#### CorelyTokens — design system source de vérité
- `primary = #003F5C`, `accent = #58B4D1`, `avatarGradient` LinearGradient const
- Toujours importer `'../../../app/corely_theme.dart'` (chemin relatif selon profondeur)
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

*Dernière mise à jour : 2026-06-07*

---

### Session 2026-06-07 — Reprise : Audit Critique + Documentation Drift Fix + Vérification isPro

#### Contexte
Session de reprise autonome. Lecture complète des 4 fichiers de contexte (CLAUDE.md, MEMORY.md, DECISIONS.md, TASKS.md), audit critique de l'existant, correction de la dérive documentaire, vérification de l'intégrité du threading `isPro`.

#### Audit critique — Constats
1. **Documentation drift** : `CLAUDE.md` décrivait encore le TTS avec chunks de 120 chars, speed 0.90/0.75, et sans mention du tier-aware routing. Corrigé.
2. **isPro threading** : vérifié tous les call sites dans `chat_notifier.dart` (28 occurrences), `voice_service.dart`, `tts_natural_service.dart` — correctement threadé. Le `voice_conversation_service.dart` délègue à `voice_service.dart` qui gère `isPro`.
3. **AdRewardTracker** : le code persiste déjà via `SharedPreferences` (`ad_videos_watched_today`, `ad_videos_date`, `ad_last_watch_time_ms`), contrairement à la note "en mémoire uniquement" dans le TODO.
4. **TTS patchs multiples** : 3 sessions de patchs sur le TTS (V16 markdown cleanup, V17 anti-saccade, 2026-05-27 paramètres). L'approche regex de `cleanMarkdown()` restera fragile. Piste créative : « oralize pass » — un 2e appel LLM qui oralise le markdown.

#### Piste créative — Oralize Pass
Plutôt que de continuer à patcher les regex de `cleanMarkdown()`, faire produire par le LLM une version « oralisée » de sa réponse avant TTS. Coût : ~100 tokens par réponse, négligeable. Élimine la fragilité des regex.

#### Actions réalisées
- `CLAUDE.md` : TTS section mise à jour (chunks 300, rates émotion, isPro, pauses naturelles, cleanMarkdown complet)
- `CLAUDE.md` : ModelRouter section mise à jour (isPro/isFree, tier-aware routing, TTS tier-aware)
- `CLAUDE.md` : Slash Commands section mise à jour (26→29 commandes, ajout scrape-script/exec/api-fetch, ScriptExecutionService)
- `CLAUDE.md` : AdRewardTracker TODO marqué comme résolu (SharedPreferences)
- `flutter analyze` : passage vérifié (exit 0)
- `git status` : branche `br-corely-agent-pro`, 54 fichiers modifiés, 56 non trackés

#### Implémentation — Oralize Pass (LLM-based markdown cleanup)
- **Fichier créé** : `lib/features/chat/data/oralize_service.dart` — Service statique `OralizeService.oralize()`
- **Fichier modifié** : `lib/features/chat/presentation/tts_natural_service.dart` — `speakNaturally()` appelle `OralizeService.oralize()` avant `cleanMarkdown()`
- **Principe** : au lieu de nettoyer le markdown avec des regex fragiles, un appel LLM léger (DeepSeek Flash, ~100 tokens, ~0.5-1s) convertit le markdown en texte oral naturel. Le LLM comprend le contexte et sait exactement ce qui doit être dit à l'oral (supprime sources, convertit tableaux en phrases, ignore URLs, etc.)
- **Cache** : LRU 32 entrées pour éviter les appels redondants
- **Détection intelligente** : `_needsOralization()` détecte si le texte contient du markdown problématique (tableaux, code, liens, listes, headers) — skip automatique pour texte déjà propre
- **Fallback** : si l'appel LLM échoue (timeout 8s, pas de clé API, erreur réseau), `cleanMarkdown` continue de fonctionner comme filet de sécurité
- **Coût** : ~$0.00003 par appel, uniquement si markdown détecté
- **Latence** : ~0.5-1s, masquée par le temps de réponse du LLM principal

### Session 2026-06-05 — Optimisation Coûts API (Tier-Aware Routing)

#### Problème
Le routage des modèles IA ne tenait pas compte du statut Pro/Free de l'utilisateur. Les utilisateurs gratuits pouvaient consommer des modèles OpenRouter payants (gpt-4o-mini, gemini-flash-1.5, mistral-large-2407) via les chaînes de fallback. Le TTS utilisait OpenRouter TTS (payant) en primaire même pour les gratuits.

#### Solution — Tier-Aware ModelRouter
**Fichier** : `lib/features/chat/data/model_router.dart`

1. **`isFree: true`** ajouté à tous les modèles DeepSeek direct API (`deepseek-v4-flash`, `deepseek-v4-pro`, `deepseek-reasoner`, `deepseek-chat`). Sémantique : "assez économique pour les utilisateurs gratuits".

2. **Chaîne vision réordonnée** : `[deepseek-chat, google/gemini-flash-1.5, openai/gpt-4o-mini]` — DeepSeek (économique) en premier, modèles OpenRouter payants en fallback.

3. **`resolveModel(isPro:)`** : nouveau paramètre `bool isPro = true`. Si `isPro == false`, les modèles avec `isFree == false` (OpenRouter payants) sont sautés. Les utilisateurs gratuits ne peuvent pas forcer un modèle payant via `userOverride`.

4. **Fallback ultime** : `deepseek-v4-pro` toujours accessible (marqué `isFree: true`).

#### Solution — Threading isPro dans chat_notifier
**Fichier** : `lib/features/chat/presentation/chat_notifier.dart`

- `isPro` passé à `ModelRouter.resolveModel(taskType, isPro: isPro)` dans tous les appels
- `isPro` passé à `_getVisionStream(history, isPro: isPro)` → filtré pour la chaîne vision
- `isPro` threadé à travers `_getWorkerStream()` → `_fallbackToDirectApiStream()` → `ModelRouter.resolveModel()`

#### Solution — TTS gratuit par défaut
**Fichiers** : `lib/features/chat/presentation/tts_natural_service.dart`, `voice_service.dart`

- `speakNaturally(text, {bool isPro = true})` : si `isPro == false`, OpenRouter TTS est sauté → flutter_tts natif (gratuit) utilisé directement
- `VoiceServiceNotifier` lit `isProProvider` et passe `isPro` à chaque appel TTS

#### Impact attendu
- **Utilisateurs gratuits** : $0.00 de coût API par requête (DeepSeek direct uniquement, TTS natif)
- **Utilisateurs Pro** : inchangé, accès à tous les modèles OpenRouter + TTS OpenRouter
- **Vision gratuite** : deepseek-chat (économique) au lieu de gemini-flash-1.5 (payant)
- **Fallback** : si tous les modèles gratuits sont en rate-limit, fallback sur deepseek-v4-pro

#### Règle
- Tout nouveau modèle ajouté au registre doit avoir `isFree` correctement défini
- `isFree = true` = DeepSeek direct API ou OpenRouter free tier
- `isFree = false` (défaut) = OpenRouter payant, réservé aux Pro

### Session 2026-06-06 — Scripts à la volée (Scraping IA)

#### Problème
Le scraping était statique : 26 commandes slash codées en dur, aucune capacité de génération de script à la volée. Pour extraire des données d'une page inconnue, il fallait soit utiliser les sélecteurs CSS manuels (`/scrape`), soit espérer que le backend `search_smart` ait un sélecteur pré-appris.

#### Solution — `/scrape-script <url> <instruction>`
**Fichiers créés** :
- `backend/agents/script_executor.py` — Sandbox Python isolé qui génère et exécute des scripts via DeepSeek
- `lib/features/chat/data/script_execution_service.dart` — Client Dart avec formatage markdown

**Fichiers modifiés** :
- `backend/main.py` — Nouvel endpoint `POST /script/scrape`
- `backend/schemas/chat.py` — `ScriptExecutionRequest` / `ScriptExecutionResponse`
- `lib/features/chat/presentation/slash_commands.dart` — Commande `scrape-script` (27e commande)
- `lib/features/chat/presentation/chat_notifier.dart` — Handler `_handleSlashScrapeScript()`

**Flux** :
1. Utilisateur tape `/scrape-script https://... "extraire tous les prix"`
2. Backend appelle DeepSeek V4 Flash → génère un script Python sur mesure
3. Script exécuté dans un subprocess isolé (timeout 30s, imports restreints)
4. Résultat JSON structuré retourné et affiché dans le chat

**Sécurité** :
- Sandbox : `subprocess.run()` dans `/tmp`, timeout 30s
- Imports bloqués : `os`, `sys`, `subprocess`, `eval`, `exec`, `open()`, etc.
- Imports autorisés : `httpx`, `BeautifulSoup`, `json`, `re`, `urllib.parse`
- Vérification `_is_safe_script()` avant exécution
- Coût : ~$0.0001 par script (DeepSeek V4 Flash)

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
- Cible : `api.zentic.fr` (FastAPI + uvicorn 4 workers + Docker).

#### Notes pour la prochaine session
- **Vocal turn-taking** : priorité CRITIQUE. L'IA doit savoir exactement quand parler sans couper la parole. Cela passe par :
  1. Détection de fin de phrase intelligente (prosodie, pas juste silence)
  2. Latence quasi nulle entre la fin de phrase utilisateur et le début du son IA (<300ms)
  3. Voix qui respire : hésitations naturelles ("euh", "hmm"), intonations, pauses
  4. Modèles à évaluer : **StyleTTS 2** (open-source, fine-grained style control) et **ElevenLabs** (multilingue, low-latency, émotion)
   5. Barge-in intelligent : ne pas interrompre l'utilisateur sauf "stop" explicite ou changement de sujet clair
 - **Tests parsing vols** : tester en conditions réelles avec requêtes lowercase + mots parasites

---

*Dernière mise à jour : 2026-06-05*

### Session 2026-06-13 — Reprise : Corrections Sécurité + Documentation + Infra

#### Contexte
Session de reprise autonome. Audit critique de l'existant, correction de la dérive documentaire, corrections de sécurité et robustesse sur l'infra Docker.

#### Actions réalisées

1. **Sécurité — Mot de passe ttyd**
   - **Problème** : `terminal/Dockerfile` contenait le mot de passe en dur : `CMD ["-p", "7681", "-c", "corelia:Cmq+WWtEGS29/gnB", ...]`
   - **Fix** : Remplacé par des variables d'environnement `TTYD_USER` et `TTYD_PASS` (défaut `changeme`).
   - **Fichier** : `terminal/Dockerfile`

2. **Robustesse — Healthcheck backend**
   - **Problème** : Le service `backend` dans `docker-compose.yml` n'avait pas de `healthcheck`. Caddy pouvait router vers un container non-prêt.
   - **Fix** : Ajout `healthcheck` avec `curl -sf http://localhost:8000/health`, intervalle 15s, 3 retries.
   - **Fichier** : `docker-compose.yml`

3. **Robustesse — Dépendance Ollama optionnelle**
   - **Problème** : `codewhale-agent` dépendait strictement de `ollama` (`depends_on: ollama`). Si Ollama était down ou non-configuré (pas de GPU), l'agent ne démarrait pas.
   - **Fix** : Suppression de `depends_on: ollama` pour le service `codewhale-agent`. L'agent utilise principalement DeepSeek/OpenRouter ; Ollama est un fallback optionnel.
   - **Fichier** : `docker-compose.yml`

4. **Documentation drift — TASKS.md**
   - **Problème** : `TASKS.md` dernier update 2026-05-28. 4 sessions de juin 2026 manquantes.
   - **Fix** : Ajout des sessions 2026-06-05 (Tier-Aware), 2026-06-06 (Scraping IA), 2026-06-07 (Oralize Pass), 2026-06-12 (CodeWhale + Infra).
   - **Fichier** : `TASKS.md`

#### Vérifications
- `docker-compose.yml` : syntaxe valide (pas de duplication de clés)
- `terminal/Dockerfile` : syntaxe valide, mot de passe externalisé
- `codewhale-agent/main.py` : présent à la racine (pas dans `app/`), cohérent avec Dockerfile

#### Blocages restants
1. 🔴 **DNS Cloudflare** : records A manquants pour `api.zentic.fr`, `chat.zentic.fr`, `terminal.zentic.fr`
2. 🔴 **GitHub SSH** : clé deploy pas encore ajoutée dans GitHub Settings
3. 🔴 **Déploiement backend** : `scripts/deploy_backend.sh` prêt mais nécessite exécution depuis la machine avec clé SSH Hetzner

---

*Dernière mise à jour : 2026-06-13*

---

### Session 2026-06-12 — CodeWhale Agent + Infra Hetzner + Cleanup

#### Action 1 : Nettoyage Cloudflare Worker
- Fichiers morts supprimés : `llm.ts`, `rate_limit.ts`, `sanitize.ts`, `scrape.ts`
- Le worker est désormais un proxy reverse transparent uniquement (Hono + CORS + proxy vers Hetzner)
- `index.ts` réduit à 167 lignes propres

#### Action 2 : Création du CodeWhale Agent
- **Nouveau microservice** dans `codewhale-agent/` :
  - `app/main.py` — FastAPI complet avec endpoints : `/agent/run`, `/agent/tools`, `/agent/status/{id}`, `/agent/result/{id}`, `/agent/stream/{id}`, `/health`
  - `app/__init__.py`
  - `Dockerfile` — image Python 3.12-slim, port 8001, healthcheck
  - `requirements.txt` — fastapi, uvicorn, httpx, pydantic
- Architecture : tâches asynchrones avec stockage in-memory, tool calling (shell read-only, docker status, disk usage, read file, list directory), LLM via DeepSeek/OpenRouter
- Compatible avec `agent_router.py` (bridge backend → codewhale-agent)

#### Action 3 : Consolidation déploiement
- `scripts/deploy_backend.sh` : ajout gestion des secrets `.env` (vérification vars requises, scp du .env vers le serveur)
- `docker-compose.yml` : fix commentaire Traefik → Caddy
- `backend/main.py` : déjà configuré avec agent_router + config_agent

#### Action 4 : Corrections tests
- `lib/app/corely_theme.dart` : `DialogThemeData` → `DialogTheme` (API Flutter 3.41)
- `test/core/constants_test.dart` : `Genere` → `Généré` (accent)

#### État tests
- 632 passés, 9 échecs pré-existants (login_screen refonte Corely, chat_bubble alignment, http_client singleton)
- `flutter analyze` : 4695 infos (0 erreurs, 0 warnings — uniquement des lints stylistiques)

#### Fichiers modifiés
- `cloudflare-worker/src/index.ts` — refait (proxy pur)
- `cloudflare-worker/src/llm.ts` — **supprimé**
- `cloudflare-worker/src/rate_limit.ts` — **supprimé**
- `cloudflare-worker/src/sanitize.ts` — **supprimé**
- `cloudflare-worker/src/scrape.ts` — **supprimé**
- `cloudflare-worker/wrangler.jsonc` — vars simplifiées
- `scripts/deploy_backend.sh` — ajout secrets .env
- `docker-compose.yml` — fix commentaire, section codewhale-agent
- `lib/app/corely_theme.dart` — DialogThemeData → DialogTheme
- `test/core/constants_test.dart` — fix accent share tagline

#### Fichiers créés
- `codewhale-agent/main.py` — microservice agent complet (FastAPI, endpoints `/agent/run`, `/agent/status/{id}`, etc.)
- `codewhale-agent/Dockerfile` — image Python 3.12-slim, port 8001, healthcheck
- `codewhale-agent/requirements.txt` — fastapi, uvicorn, httpx, pydantic, openai

#### Blocages restants
1. ✅ CodeWhale Agent résolu (microservice créé)
2. 🔴 Déploiement réel sur Hetzner : nécessite clé SSH + `.env` sur la machine hôte
3. 🟡 Neigloo : workspace vide, retiré des `additionalDirectories`


### Session 2026-06-12 — Infrastructure Hetzner : DNS + GitHub SSH + ttyd + Claude Code

#### Actions réalisées

**Phase 1 — DNS Cloudflare (instructions)**
- Identifié les name servers : `dax.ns.cloudflare.com` / `jasmine.ns.cloudflare.com`
- `agent.zentic.fr` et `ollama.zentic.fr` déjà configurés (records A existants)
- `api.zentic.fr`, `chat.zentic.fr`, `terminal.zentic.fr` → NXDOMAIN (à créer)

**Phase 2 — GitHub SSH bidirectionnel**
- Clé deploy générée sur le VPS : `~/.ssh/id_ed25519_github`
- Clé publique : `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL2bATliKhhYFGOU3buyweXnm8KWxKr+eLPhfgEW4eHO corelia@hetzner-deploy`
- `~/.ssh/config` configuré pour github.com avec IdentityFile
- **Action utilisateur** : ajouter la clé dans GitHub Settings > SSH Keys

**Phase 3 — Terminal web ttyd**
- Service ajouté dans `docker-compose.yml` (tsl0922/ttyd:latest)
- Route ajoutée dans `Caddyfile` (terminal.zentic.fr → reverse_proxy terminal:7681)
- Mot de passe généré dans `.env` : `TTYD_PASSWORD=Cmq+WWtEGS29/gnB`
- Image Docker pullée et conteneur créé sur le VPS
- **Action utilisateur** : `ssh corelia@167.233.100.132 "cd /opt/corelia && docker compose up -d terminal"` pour finaliser

**Phase 4 — Claude Code + DeepSeek TUI**
- Claude Code v2.1.176 installé dans `/usr/bin/claude`
- Codewhale v0.8.58 installé (`deepseek-tui` renommé, compatible)
- Node.js v22.22.3 installé
- tmux installé
- Git config : user.name + user.email

**Phase 5 — Synchronisation**
- docker-compose.yml, Caddyfile, settings.local.json, corely_theme.dart, scripts/ → synced vers VPS
- Fichiers Cloudflare Worker morts supprimés

#### Fichiers modifiés
- `docker-compose.yml` — ajout service `terminal` (ttyd avec auth)
- `Caddyfile` — ajout routes terminal.zentic.fr et chat.zentic.fr
- `codewhale-agent/Dockerfile` — fix CMD pour main.py à la racine

#### Blocages
1. 🔴 DNS Cloudflare : ajouter records A manuellement dans le dashboard
2. 🔴 GitHub SSH : ajouter la clé deploy dans GitHub Settings
3. 🟡 ttyd : redémarrer le conteneur avec la bonne config (docker compose up -d terminal)

---

## Session 2026-06-16 — Audit chirurgical + 7 corrections production-ready

### Contexte
Reprise de session (protocole REPRISE). Audit critique du code existant après
déploiement backend. 25 constats, 7 corrections autonomes exécutées, le reste
(destructif/outward-facing) signalé à l'utilisateur.

### Corrections appliquées (toutes production-ready)

1. **Routage vocal mort → restauré** (`model_router.dart`) : `task:vocal` /
   `task:vocalFast` n'avaient pas de mapping dans `resolveModel()` → le mode vocal
   routait via deepseek-v4-flash au lieu d'arcee/trinity (jovial). Mappings ajoutés.
2. **Oralize Pass → tier-aware** (`oralize_service.dart`) : `oralize(text, {bool isPro = false})`,
   `!isPro` court-circuite l'appel LLM (gratuit = $0, fallback cleanMarkdown).
   Timeout 8s → 4s. Cache FIFO → LRU (touch sur hit).
3. **`isPro` fail-safe + defense-in-depth** (`tts_natural_service.dart` +
   `openrouter_tts_service.dart`) : `speakNaturally({bool isPro = false})` (défaut
   gratuit, fail-safe). `synthesize({bool isPro = false})` retourne null si `!isPro`
   (garde-fou contre facturation). Threading `isPro` via `_speakWithOpenRouterTts`
   (`{required bool isPro}`). `synthesizeVocal` (dead code) mis à jour par cohérence.
4. **Fallback vision-aware** (`model_router.dart`) : `resolveModel` retourne `null`
   pour `TaskType.vision` si le dernier recours n'est pas vision-capable →
   `_getVisionStream` déclenche le `throw AiException` propre (code vivant, avant mort).
5. **ttyd fail-closed (3 couches)** : `Dockerfile` (retrait `ENV TTYD_PASS=changeme`),
   `start-ttyd.sh` (exit 1 si vide/changeme), `docker-compose.yml`
   (`TTYD_PASS=${TTYD_PASS:?…}` obligatoire). Le service tournait avec `changeme`
   en prod — TASKS.md prétendait l'inverse (drift doc corrigé).
6. **Whitelist clés extension** (`build_extension.sh`) : n'embarque plus que
   `DEEPSEEK_API_KEY`, `ADMOB_*`, `REVENUECAT_*`, `APP_ENV`. `OPENROUTER_API_KEY`
   (clé payante opérateur) exclue — l'extension est toujours DEMO (`isPro=false`),
   OpenRouter n'y est jamais appelé. Fuite de secrets serveur (API_SECRET_KEY,
   SERPAPI, STRIPE_WEBHOOK_SECRET) stoppée.
7. **CLAUDE.md doc drift corrigé** : `_speakResponseAndLoop`/500ms/idle →
   `_speakFullResponse`/1200ms/listening ; `_listenWithVad` → écoute event-driven
   `_onSpeechFinal` ; TTS speed 1.0 → 0.95 ; chaîne TTS → Orpheus 3B ajouté ;
   Oralize + speakNaturally documentés tier-aware/fail-safe ; dart-define extension
   sans OPENROUTER_API_KEY.

### Fichiers modifiés
- `lib/features/chat/data/model_router.dart` — mappings vocal + fallback vision null
- `lib/features/chat/data/oralize_service.dart` — isPro param, timeout 4s, LRU cache
- `lib/features/chat/data/openrouter_tts_service.dart` — garde-fou isPro synthesize
- `lib/features/chat/data/openrouter_vocal_service.dart` — synthesizeVocal isPro
- `lib/features/chat/presentation/tts_natural_service.dart` — isPro fail-safe + threading
- `terminal/Dockerfile` — retrait défaut TTYD_PASS
- `terminal/start-ttyd.sh` — garde-fou fail-closed
- `docker-compose.yml` — TTYD_PASS obligatoire
- `scripts/build_extension.sh` — whitelist clés client-safe
- `CLAUDE.md` — doc drift vocal/TTS/extension corrigé
- `DECISIONS.md` — ADR-025
- `TASKS.md` — session 2026-06-16 terminée

### Signalé à l'utilisateur (hors scope autonome — destructif/outward-facing)
- 🔴 Rotation clés Firebase + git filter-repo (clés dans l'historique git)
- 🔴 Auth CodeWhale Agent + backend `/agent/execute` (RCE non authentifié)
- 🔴 9 endpoints backend non authentifiés + SSRF blocklist + sandbox script (eval)
- 🔴 Changer TTYD_PASS sur le VPS (rebuild + redémarrer) — le repo est fail-closed,
  mais le conteneur existant tourne encore avec l'ancien mot de passe
- 🟡 Stripe webhook `req.rawBody` (signature)
- 🟡 APK release signé en debug

### Vérification
- `flutter analyze` non exécutable (binaires SDK sans permission d'exécution dans
  l'environnement). Vérification par traçage exhaustif des appelants : tous les
  paramètres ajoutés sont optionnels avec défaut, sauf `{required bool isPro}` sur
  `_speakWithOpenRouterTts` (unique appelant mis à jour). Vision null-return →
  `AiException` propre confirmé (`chat_notifier.dart:3552-3562`). Aucun appelant
  test/ cassé.

### Session 2026-06-16 (suite) — Bloc 0 : Quick wins P0 release

Suite de l'audit Phase 1 (5.5/10). Exécution autonome du Bloc 0 — correctifs
mécaniques + architecturaux bloquant la bêta. Détails : ADR-026 (DECISIONS.md).

#### Corrections appliquées
- **Paywall barrel** : `paywall_screen.dart` → barrel conditional import. Mobile =
  RevenueCat (avant dead code), web/extension = Stripe checkout.
  `paywall_screen_web.dart` recréé en screen Stripe réel (plus "info message").
- **Projets** : route `/projects/:id` ajoutée + `ProjectDetailScreen` nouveau
  (`ProjectKey` immutable, `StreamProvider.family`). Lien projet↔conversation
  CANONIQUE via `Conversation.projectId` (query `conversations` where
  userId+projectId), pas via `Project.conversationIds` (source unique). Provider
  cassé (collection fantôme `projects/{id}/conversations`) supprimé.
- **Prefs sync LWW** : `mergeWithLocal` réécrit last-write-wins (timestamp) + leaf
  `local_pref_timestamp.dart` (évite import circulaire) + `markUpdated()` câblé dans
  setTheme/setSpeed/SystemPrompt save+reset + listener `main.dart`. Auto-push +
  live-reload différés post-bêta (gap documenté dans le docstring).
- **Signature release** : build.gradle lit `key.properties` + garde-fou fail-fast
  (GradleException si keystore absent). `android/key.properties.example` créé.
- **Version** : pubspec 1.0.0+1 → 1.1.0+1 (aligne `constants.dart`/UI).
- **Constants** : URLs Stripe checkout + noms de collections centralisés dans
  `AppConstants` ; projects_screen 0 collection hardcodée (100% AppConstants) ;
  `.env.example` +SERPAPI/OPENWEATHERMAP.
- **Mécanique** : `\$`→`$` (image_upload io+web : toString, debugPrint, throw),
  streak `${data.streak}` + accent "Série", `api_load_test` pid recursion → `io.pid`.

#### Fichiers
- `lib/features/monetization/subscription/paywall_screen.dart` (barrel) +
  `paywall_screen_web.dart` (nouveau) + `paywall_screen_mobile.dart` (URLs AppConstants)
- `lib/features/projects/presentation/projects_screen.dart` + nouveau
  `project_detail_screen.dart` + `lib/app/router.dart`
- `lib/core/prefs/local_pref_timestamp.dart` (nouveau) +
  `lib/features/settings/data/preferences_sync_service.dart` + `lib/main.dart` +
  `lib/core/providers/app_providers.dart` + `lib/features/settings/presentation/settings_screen.dart`
- `android/app/build.gradle` + `android/key.properties.example` (nouveau)
- `lib/core/constants.dart` + `.env.example` + `pubspec.yaml`
- `lib/features/chat/data/image_upload_service_io.dart` / `_web.dart` +
  `lib/features/retention/data/streak_service.dart` + `test/load/api_load_test.dart`
- `DECISIONS.md` (ADR-026) + `TASKS.md` + `CLAUDE.md` (drift corrigé)

#### Vérification
- Grep : 0 collection hardcodée dans projects_screen, 0 `\$` restant, pid recursion
  gone, 0 URL Stripe hardcodée hors constants.dart, barrel paywall + route
  `/projects/:id` OK.
- `flutter analyze`/`flutter test` non exécutables ici (binaires SDK 644 sans permission
  d'exécution) — vérification par traçage statique. Recommandation : lancer en local.
- Actions manuelles restantes (hors scope autonome) : keystore `keytool` + upload
  Play Store ; rotation clés Firebase + git filter-repo (signalé ADR-025) ; ttyd VPS
  rebuild (signalé ADR-025).

---

### Session 2026-06-16 (suite 2) — Bloc 1 : Sécurité backend P0

Suite de l'audit Phase 1 (5.5/10). Bloc 1 = durcissement backend en couches
(defense-in-depth). Détails : ADR-027 dans `DECISIONS.md`.

#### Problèmes résolus
1. **RCE non auth** (`/script/exec`, `/config/*`, `/agent/*`, `/insights/audit`) →
   auth two-tier : `CLIENT_API_KEY` (soft, `X-API-Key`, transition-open) gates routes
   APK-facing ; `API_SECRET_KEY` (opérateur, fail-closed 403 si vide, jamais dans l'APK)
   gates RCE/admin. `hmac.compare_digest` (constant-time). `/chat/completions` = Firebase
   JWT (indépendant).
2. **SSRF** (scrape/crawl/download/search_smart suivaient redirects sans validation) →
   `backend/core/net_guard.py` : `assert_safe_url` (scheme allow-list + blocklist
   loopback/privé/cloud-metadata `169.254.169.254`) + `safe_get`/`safe_get_sync`
   (redirect off, re-validation per-hop, max 4).
3. **Sandbox scripts IA** (`script_executor.py`) : validateur AST `_ScriptValidator`
   (`_ALLOWED_MODULES`/`_DANGEROUS_NAMES`/`_DANGEROUS_ATTRS`) + env minimal `_SANDBOX_ENV`
   (pas de clés héritées) + `tempfile.TemporaryDirectory` cwd + timeout 15s.
4. **Injection shell** (`config_agent.py`) : `create_subprocess_exec` argv + `_validate_domain`.
5. **Conteneurs root** → non-root (uid 10001 backend, 10002 codewhale ; `/workspace` chown).
6. **docker.sock** retiré de codewhale (escalade root-equivalent) ; **port Ollama 11434**
   non publié (endpoint LLM non auth exposé internet) ; **CORS** serré
   (`allow_credentials = not wildcard`).
7. **Fuite `.env` APK** : `.env` retiré des `assets` `pubspec.yaml` (shipait clé opérateur
   + clé OpenRouter payante + Stripe webhook dans l'APK extractible). Clés via
   `--dart-define` uniquement. `main.dart` gardait déjà `dotenv.load` en try/catch.
8. **Secret opérateur commité** : `scripts/server_init.sh` ne contient plus la valeur
   réelle `311788a1…` → placeholders générés via `openssl rand -hex 32` (fallback
   `/dev/urandom`). `.env.example` sépare client (CLIENT_API_KEY) vs VPS-only (API_SECRET_KEY).

#### Wiring client Flutter
- `AppConstants.backendApiKey` (lit `CLIENT_API_KEY` `--dart-define`) → `X-API-Key` sur
  `SearchServiceGlobal`, `ScriptExecutionService`, `WorkerChatClient`.
- `WorkerChatClient` migré `Bearer $_apiSecretKey` (opérateur — ne devait jamais être
  client-side) → `X-API-Key: $_apiKey` (soft). Documenté legacy.
- `chat_notifier.dart` : message "Backend non configuré" `API_SECRET_KEY` → `CLIENT_API_KEY`.
- `script_execution_service.dart` : 401/403 de `/script/exec` → message "réservé à
  l'opérateur" (pas un 401 brut).

#### Fichiers
- Backend : `core/auth.py` + `core/config.py` + `core/net_guard.py` (nouveau) +
  `main.py` + `agents/{script_executor,config_agent,agent_router,data_insights,
  search_engine,search_smart,download_service,crawl_service,chat_router}.py` +
  `backend/Dockerfile` + `codewhale-agent/Dockerfile` + `docker-compose.yml`
- Flutter : `lib/core/constants.dart` + `lib/features/chat/data/{search_service_global,
  script_execution_service,worker_chat_client}.dart` +
  `lib/features/chat/presentation/chat_notifier.dart` + `lib/main.dart`
- Config/build : `.env.example` + `pubspec.yaml` + `scripts/server_init.sh` +
  `scripts/build_extension.sh`
- Docs : `DECISIONS.md` (ADR-027) + `TASKS.md` + `CLAUDE.md` + `MEMORY.md`

#### Vérification
- Grep : 0 `_apiSecretKey` restant (worker_chat_client migré), `backendApiKey` câblé sur
  les 3 clients, header `X-API-Key` = header lu backend (`auth.py:91`), 0 `- .env` dans
  pubspec, 0 valeur `311788a1…` dans le repo, `CLIENT_API_KEY` dans le switch dart-define.
- Gating backend vérifié : `/script/exec`+`/config/*`+`/agent/*`+`/insights/audit` →
  `require_operator_key` ; routes APK-facing → `require_client_api_key` ;
  `/chat/completions` → Firebase JWT.
- `flutter analyze` non exécutable ici (binaires SDK 644) — traçage statique. Lancer en local.
- Actions VPS manuelles (signalées) : rotation `API_SECRET_KEY` (valeur `311788a1…` était
  live) + `git filter-repo` ; définir `CLIENT_API_KEY` dans `.env` VPS + `--dart-define` APK.

---

### Session 2026-06-16 (suite 3) — Bloc 2 : Robustesse vocale (machine à états)

Réécriture propre de la `VoiceConversationNotifier` (machine half-duplex tour-par-tour
`listening → thinking → speaking → listening`) — 5 races + 1 bug sémantique. Détails :
ADR-028 dans `DECISIONS.md`.

#### Problèmes résolus
1. **Barge-in « repeat » cassé** : `_speakFullResponse` du repeat était skip silencieusement
   par le garde `_isProcessingResponse && state==speaking` (speak d'origine encore en vol).
   En plus, le speak d'origine « réveillé » par `stopSpeaking()` rouvrait le micro +
   écrasait l'état après son délai 1200ms (race).
2. **Pas de token d'annulation de tour** : continuations async (reopen micro post-TTS,
   délai 1200ms) pouvaient se déclencher sur un tour obsolète (barge-in/stop) et corrompre
   l'état courant.
3. **`_lastProcessedTime!` forcé-unwrapped** → crash potentiel si invariant rompu.
4. **Pas de reset systématique** : `stop()`/`startConversation()` ne clearaient pas
   `_isProcessingResponse`/`_lastProcessedTranscript`/`_lastRequestTime` → drapeaux stale
   inter-sessions (Notifier family persistant) pouvaient bloquer `_handleChatState`.
5. **Pas de sync erreur STT** : spec « Max 3 échecs STT → error » non implémentée ;
   `voice_service.dart` `onError` ne faisait que `isListening=false` → machine bloquée en
   `listening` sur micro instable, sans récupération ni borne.
6. **`BargeInIntent.stop` mal routé** (bonus découvert en réécrivant le switch) : classifieur
   définit `stop` = « arrêt immédiat » (`stop|chut|tais-toi|arrête|pause|silence|…`) mais le
   code routait vers `_sendToLLM` → « chut » envoyé au LLM déclenchait une nouvelle réponse
   (l'utilisateur voulait du silence).

#### Solution — token de génération (idiomatique Dart, zéro dép externe)
- `_generation` (int) incrémenté à chaque frontière de tour (start, barge-in, stop, dispose).
  Chaque continuation async capture `gen` et **bail si `gen != _generation`**.
- `_resetTurnState()` : bump génération + clear tous drapeaux stale. Appelé à
  start/stop/dispose (anti-pollution inter-sessions).
- Garde `_isProcessingResponse` lié à la génération : libéré dans `whenComplete`
  **seulement si** `_generation == gen` (le tour qui l'a posé le libère).
- Barge-in : bump génération + libère garde + `stopSpeaking()` avant dispatcher. Le speak
  d'origine bail → ne rouvre pas le micro. `repeat` → `_respeakLastAssistant()` (procède,
  fin du skip silencieux).
- `_lastProcessedTime` null-check défensif.
- Sync erreur STT : nouveau `onSttError` stream dans `voice_service.dart` (émis depuis
  `onError` native + catch `_startSttListen`). `VoiceConversationNotifier` écoute après
  démarrage réussi ; `_onSttError` compte, **tente reprise** (redémarrage micro 400ms) si
  `state==listening`, **error après 3** (anti-boucle). Reset compteur sur speech final.
- `BargeInIntent.stop` corrigé : nouvelle `_returnToListening()` — coupe TTS + repasse en
  listening + rouvre micro **sans round-trip LLM** (l'utilisateur reprend la parole).

#### Fichiers
- `lib/features/chat/presentation/voice_conversation_service.dart` (réécriture propre)
- `lib/features/chat/presentation/voice_service.dart` (ajout `onSttError` stream :
  controller + getter + emit `onError` + emit catch `_startSttListen` + close onDispose)

#### Vérification
- API publique 100% conservée : enum `VoiceConversationState` (5 valeurs), champs
  `VoiceConversationStatus`, méthodes `startConversation/stop/toggle/setBargeInEnabled`,
  `voiceConversationProvider`. Seuls consommateurs (`chat_screen.dart`,
  `aurora_splash.dart`) n'accèdent qu'à l'API publique → rétro-compatible (grep vérifié).
- Switch barge-in exhaustif sur les 5 `BargeInIntent` (repeat/topicChange/stop/
  correction/none). 0 référence externe aux méthodes privées modifiées.
- `flutter analyze` non exécutable ici (binaires SDK 644) — traçage statique. Lancer en local.
- À valider sur device (Xiaomi 12) : 5 tours, barge-in >3 mots (repeat/topicChange/stop),
  reprise micro après erreur STT, pas de monologue, TTS fluide.

---

### Session 2026-06-16 (suite 4) — Bloc 3 (1-2/≥5) : Extraction TravelParamsParser + WebSearchTrigger

Deux premiers clusters de la décomposition du god object `ChatNotifier` (4270 lignes — la
plus grosse dette d'archi du projet, P1 audit Phase 1). Le cluster 1 (parsing vol/météo)
était en plus **dupliqué** ; le cluster 2 (gatekeeper recherche web) était simplement mal
placé. Détails : ADR-029 (cluster 1) + ADR-030 (cluster 2) dans `DECISIONS.md`.

#### Cluster 1 — TravelParamsParser (dédup parsing vol/météo)
**Problèmes** : duplication de source (`ChatNotifier` FR/EN + `normalizeDate` sûr vs
`SearchIntentExtractor` 6-lang + `normalizeDate` non sûr — bug latent `'date-0a-not'`) ;
god object 4270 lignes.
**Solution** : nouveau `lib/features/chat/data/travel_params_parser.dart` (299 lignes, classe
utilitaire, méthodes statiques pures). Regex mois = surensemble 6 langues. `normalizeDate`
sûr (`int.parse`+try/catch). `parseMonth` délègue au top-level de `language_service.dart`.
Stop-words = union (46).
**Wiring** : `chat_notifier.dart` 4270→4042 (−228) — 4 sites d'appel → `TravelParamsParser.*` ;
5 anciennes statiques publiques deviennent shims déléguants (rétro-compat tests :
`enhanced_search_test.dart` inchangé). `search_intent_extractor.dart` ~1168→1004 (−164) —
`_extractFlightParams` délègue en tête + garde repli fuzzy ; 3 méthodes mortes supprimées
(`_tryParseFlightParamsGeneric`/`_normalizeDate`/`_sanitizeFlightQuery`).

#### Cluster 2 — WebSearchTrigger (gatekeeper recherche web)
**Problème** : `_needsWebSearch` (~80 lignes, heuristique multilingue déclencheurs/exclusions)
+ `_extractSearchQuery` (~16 lignes, strip salutations + tronque) vivaient en méthodes privées
statiques dans le god object — 100% pures mais non testables isolément.
**Solution** : nouveau `lib/features/chat/data/web_search_trigger.dart` (128 lignes, classe
utilitaire, méthodes statiques pures). Même pattern que TravelParamsParser.
**Wiring** : `chat_notifier.dart` 4042→3943 (−99) — 3 sites d'appel → `WebSearchTrigger.*` ;
2 méthodes privées supprimées (pas de shim — privées, 0 réf test). Commentaire pointeur laissé
pour traçabilité.
**Alternatives rejetées** : shim statique (inutile — méthodes privées, pas d'API publique) ;
fusion avec `SearchIntentExtractor` (cohésions distinctes : type de recherche vs gatekeeper ;
mélanger aurait surchargé ses 9 keyword maps par langue).

#### Réévaluation du plan Bloc 3 (post-cluster-2)
- `QuotaService` — **déjà extrait** : les services dédiés `quota_service.dart` /
  `file_quota_service.dart` / `search_quota_service.dart` / `voice_quota_service.dart`
  existent déjà dans `data/`. `chat_notifier` ne garde que l'orchestration state-coupled des
  appels + `_PendingMessage` retry → pas une cible statique propre. Item retiré.
- `classifyTask` — **non dupliqué** : vit uniquement dans `model_router.dart`. L'item
  « dédup classifyTask » de l'audit Phase 1 était une erreur. Item retiré.
- Reste : `SlashCommandDispatcher` (~2200 lignes, le plus state-coupled — abordé en dernier,
  requiert `flutter analyze` local pour vérif), `BrowserActionDispatcher`,
  `SearchOrchestrator` (partie state-coupled).

#### Vérification (cumul 2 clusters)
- 0 référence externe aux méthodes privées supprimées (grep vérifié pour les 5 méthodes
  cluster 1 + 2 cluster 2). Shims `ChatNotifier.*` préservent la surface de test publique.
- `flutter analyze` non exécutable ici (binaires SDK 644) — traçage statique exhaustif.
  `flutter analyze` + `flutter test` à lancer en local avant release.

#### Fichiers touchés (cumul)
- `lib/features/chat/data/travel_params_parser.dart` (nouveau, 299 lignes)
- `lib/features/chat/data/web_search_trigger.dart` (nouveau, 128 lignes)
- `lib/features/chat/presentation/chat_notifier.dart` (4270→3943, −327 lignes, 5 shims + 2 suppressions)
- `lib/features/chat/data/search_intent_extractor.dart` (−164 lignes, 3 méthodes mortes supprimées)
- `DECISIONS.md` (ADR-029 + ADR-030) + `CLAUDE.md` (Core Structure + Enhanced Search + Web Search + Key Flows + resolved ×2)

### Session 2026-06-17 — Bloc 4 : Tests critiques (fonctions pures extraites)

L'extraction Bloc 3 rendait enfin **testables isolément** des fonctions qui vivaient en méthodes
privées dans `ChatNotifier` — jamais couvertes. Bloc 4 = combler ce trou + lever la limite
« `flutter test` inexécutable » (binaires SDK en 644, artefact d'extraction).

#### Déblocage SDK (réversible, local)
- `chmod +x` sur `bin/cache/dart-sdk/bin/*` (sauf `.snapshot`/`.dart`) + `bin/cache/artifacts/**/*`
  (sauf `.dat`/`.ttf`/`.json`/`.txt`/`.md`/`.snapshot`). Clés : `dart`, `dartaotruntime`,
  `impellerc`. Pattern de run fiable : nohup bg + `kill -0 $PID` wait (PIDs exacts), SANS
  `pgrep -f "flutter.*test"` (self-match wait-loop), SANS `timeout` interne (SIGTERM avant output
  cold-start), SANS `sleep N; cmd` chaîné (harness bloque).

#### Tests écrits (68, net-new)
- `test/features/chat/data/travel_params_parser_test.dart` — **46 tests** (9 groupes) :
  `parseFlightParams` (4 patterns + cas négatifs), mois ES/DE/IT/PT (valide ADR-029),
  `extractCity` (4 patterns + repli minuscules + villes composées), `extractZipCode`,
  `normalizeDate` (sûr), `parseMonth` (6 langues + casse + défaut), `isValidCityPair`.
- `test/features/chat/data/web_search_trigger_test.dart` — **22 tests** (6 groupes) :
  `needsWebSearch` (déclencheurs/exclusions multilingues + `?` + exclusion prioritaire) +
  `extractSearchQuery` (strip salutations + tronque 200).

#### 3 bugs réels exposés par les tests (tous pré-existants à l'extraction)
1. **Absorption mot-clé capitalisé** (`Flug Berlin Hamburg` → `from="Flug Berlin"`) → fix
   `_travelKeywords` (Set 6-lang) + `_stripLeadingKeyword` post-traitement `parseFlightParams`.
   Mots-clés minuscules jamais capturés (`[A-ZÀ-Ÿ]` exige majuscule) ; villes composées préservées.
2. **Dérive regex↔map** (PT `setembro`→janvier) → `monthPattern` capturait `[Ss]etembro` mais la
   map `parseMonth` (`language_service.dart`) n'avait pas l'entry → 1 (défaut). Fix : ajout
   `'setembro': 9` + commentaire **contrat regex↔map** (orthographe capturable DOIT avoir une
   entry, directe ou via homonyme inter-langue : `august` EN==DE, `marzo` ES==IT, `agosto`
   ES==IT==PT, `novembre` FR==IT, `abril` ES==PT). `setembro` = seul manquant à orthographe unique.
3. **Repli météo minuscule cassé** (`météo paris`→null) → cause racine = `\b([a-zà-ÿ])`
   capitalisait chaque accent. En Dart (regex ECMAScript) `\w` = `[A-Za-z0-9_]` seulement —
   les accents sont non-mot, donc `\b` marque une frontière à chaque accent → `météo`→`MÉTÉO`
   (chaque `é` capitalisé) et `[Mm]étéo` (sensible à la casse) ne matchait plus. Fix :
   `_capitalizeWords` (`(^|[\s-])([a-zà-ÿ])` préserve délimiteur) — capitalise la 1ʳᵉ lettre
   après début/espace/tiret sans toucher aux accents internes (`météo`→`Météo`, `août`→`Août`,
   `paris-londre`→`Paris-Londre` — tiret reste délimiteur, requis par tests vol hyphen).
   Partagé par replis `parseFlightParams`+`extractCity` (DRY). Mots-clés météo patterns 1&2
   passés en `[Mm]`-brackets (ville reste `[A-ZÀ-Ÿ]` — `caseSensitive:false` sur tout le motif
   aurait capturé des minuscules comme ville : « temps fait »→« Fait »).

#### Vérification
- **Nouveaux tests : 68/68** (46 + 22) après les 3 fixes.
- **Régression : 33/33** — `enhanced_search_test.dart` (28, shims `ChatNotifier.*` qui délèguent)
  + `search_service_parsing_test.dart` (5). 3 fixes + refactor `_capitalizeWords` + entry
  `setembro` ne régressent aucune expectation existante.
- **`flutter analyze`** : compile OK, 0 erreur/0 warning, 162 lints `info` pré-existants (style
  uniquement). Limite « SDK 644 » des ADR-029/030 **levée**.
- Fichiers : 2 nouveaux tests + `travel_params_parser.dart` (Bugs 1&3 + `_capitalizeWords`) +
  `language_service.dart` (Bug 2) + `DECISIONS.md` (ADR-029 vérif) + `TASKS.md` + `MEMORY.md` +
  `CLAUDE.md`. ADR-029 mis à jour (limite levée + section Vérification).

---

## 2026-06-17 — Bloc 5 : Perf backend async I/O ✅ (ADR-031)

### Sujet
L'audit Phase 1 (ADR-027) avait relevé **6 sites d'I/O bloquant** dans des routes
FastAPI `async`. Un appel sync dans une coroutine `async` gèle **tout** l'event
loop pour toute sa durée — chaque requête concurrente (chat streaming, /scrape,
/search_smart, /download_media, /crawl) est gelée aussi. Le pire :
`script_executor.execute_script` utilisait `subprocess.run(timeout=15)` → gel de
**15 s** de l'event loop par exécution de sandbox. Routes `/download_media`
(yt-dlp, 10-30 s) et `/crawl` (BFS multi-page sync) tout aussi bloquantes.

### Décisions clés (ADR-031)
- **`execute_script`** : `subprocess.run` → `asyncio.create_subprocess_exec` +
  `wait_for(communicate, timeout)` + `proc.kill()`+`await proc.wait()` sur
  `asyncio.TimeoutError`. Event loop libre pendant le run. Reap explicite + garde
  `ProcessLookupError` → **zéro zombie**. Pattern déjà dans `config_agent.py`.
- **`scrape_url`** + **`_scrape_page`** : parse BeautifulSoup CPU-bound (50-200 ms)
  extrait vers helpers module-level sync `_extract_scrape_data` /
  `_parse_scraped_page` → dispatch `asyncio.to_thread`. Helpers purs = testables
  isolément (pas de réseau, pas de closure, lit les globals module).
- **`main.py`** routes `/download_media` + `/crawl` : stopgap
  `asyncio.to_thread(service.extract_media/crawl, …)`. Signatures préservées.
  Réécriture full-async (httpx.AsyncClient + asyncio.gather) = follow-up (bloc séparé).
- **`config_agent.exec_migrate_docker_data`** (`open`/`os.makedirs`) : **DIFFÉRÉ
  avec rationale** — I/O sub-ms pris en sandwich entre des `systemctl` minute-longs
  déjà awaited. Wrapper un fichier sub-ms = cérémonie zéro gain. « Zéro patch aveugle ».

### Bug découvert + corrigé (auto-test, le moment clé)
- 1ʳᵉ implémentation : `except asyncio.TimeoutExpired:` → **`asyncio.TimeoutExpired`
  n'existe PAS**. `asyncio.wait_for` lève `asyncio.TimeoutError` (alias du builtin
  `TimeoutError`) ; `TimeoutExpired` n'existe que sur l'API **sync** `subprocess`.
  Conséquence : `AttributeError` catché par le `except Exception` externe → (a)
  message d'erreur confus `"module 'asyncio' has no attribute 'TimeoutExpired'"`
  au lieu du timeout attendu, ET (b) `proc.kill()` **jamais atteint** → **zombie
  leak** (child busy-loop `while True: pass` à 100 % CPU indéfiniment).
- **Révélation** : le test `test_execute_script_does_not_block_event_loop` +
  un check zombie post-run ont exposé le bug. **2 zombies à 100 % CPU** (PIDs
  406250/406251, ~75 s) leakés au 1ᵉʳ run nettoyés manuellement (`kill -9`) —
  **preuve que le reap explicite + garde ProcessLookupError est critique**, pas
  un détail cosmétique.
- **Fix** : `except asyncio.TimeoutError:` + garde `try: proc.kill() except
  ProcessLookupError: pass` (race : proc déjà mort au kill) + `await proc.wait()`.
- **Leçon** : en Python 3.12, **toujours** `asyncio.TimeoutError` pour `wait_for`.
  Ne jamais confondre avec `subprocess.TimeoutExpired` (sync only). Vérif empirique :
  `hasattr(asyncio, "TimeoutExpired")` → `False`.

### Vérification
- **Nouveaux tests : 12/12** (`backend/tests/test_async_io.py` : 5 helpers purs
  sans réseau, 1 signatures async préservées, 6 execute_script end-to-end dont
  `test_execute_script_does_not_block_event_loop` — ticker concurrent prouve le
  non-blocage de l'event loop, et `test_execute_script_timeout_reaps_child_fast` —
  timeout respecté < 4 s + reap).
- **Régression suite backend : 20 passed** (12 nouveaux + 8 pré-existants),
  2 failed **pré-existants** (`test_chat_streaming_mock`/`test_chat_non_streaming_mock`
  — `unhashable type: dict` dans `chat_router` + mock non-awaité, hors-périmètre),
  2 collection errors **pré-existants** (template tests — chemin relatif `templates`,
  hors-périmètre). **Zéro régression introduite.**
- **Post-run orphan check : 0 zombie** (le reap durci fonctionne).
- Fichiers : `script_executor.py` (subprocess async + reap), `search_engine.py`
  (+ helper), `search_smart.py` (+ helper), `main.py` (2 routes stopgap),
  `backend/tests/test_async_io.py` (nouveau, 12 tests) + DECISIONS (ADR-031) +
  TASKS + CLAUDE.md.

---

## Session 2026-06-17 — Mission autonome « corrige tout » (multi-agent + orchestrateur)

### Contexte
Session 68d36b15 (suite du Bloc 5 ADR-031). Mission multi-bloc : continuer le
nettoyage post-audit Phase 1. Cinq sous-blocs exécutés en parallèle par 3
agents file-disjoints (A = Dart edit-only quota ; B = backend pytest async ;
C = Dart edit-only IATA) + 1 orchestrateur intégrateur. Tous les tests
Flutter + backend verts au final, `flutter analyze` à 0/0.

### Bloc 6 — Cluster 4 : `chat_text_helpers` extraction (ADR-029 suite)
**Problème** : après extraction des clusters 1-3 du god object
`chat_notifier.dart` (TravelParamsParser, WebSearchTrigger, ~327 lignes), il
restait ~80 lignes de **7 helpers texte purs** éparpillés (document/export,
browser-action, recherche produit, erreur IA) — 100% sans dépendance state
mais privés au notifier → non testables.
**Solution** : `lib/features/chat/data/chat_text_helpers.dart` (nouveau, 85
lignes) — `normalizeDocFormat`, `extractDocumentTitle`, `escapeForJson`,
`stripActionCommands`, `parseJsonLoose`, `buildProductSearchQuery`,
`formatAiError`. Méthodes publiques statiques pures (comme
`TravelParamsParser` / `WebSearchTrigger`).
**Wiring** : `chat_notifier.dart` 3943→3862 (−81 lignes). 7 sites d'appel
migrés. Refactor via script Python audité `/tmp/refactor_chat_notifier.py`
(2 passes : extraction puis renommage des call-sites) avec asserts
`count==1` + write gated (rollback-able).
**Tests** : `test/features/chat/data/chat_text_helpers_test.dart` 39/39
vert (3 groupes : doc/export ×14, browser-action ×12, recherche+erreur
IA ×13). Test miroir du contrat réel des helpers, pas de mocks.

### Bug parsing vols réel (corrigé + couvert par test)
**Reproduction** : `parseFlightParams("trouve un billet paris-londre direct
du 29/05")` retournait `null`. Cause : le repli `_sanitizeFlightQuery` +
`_capitalizeWords` produisait `Paris-Londre 29/05` (le stop-word `du` était
strippé) qu'**aucun pattern A/B/C/D** ne matchait. Pattern B
(`(?:d[ue]|le)\s+`) exigeait `du` ou `le` — mais le strip l'avait déjà
retiré.
**Fix** : pattern B relaxé `(?:d[ue]|le)\s+` → `(?:d[ue]|le)?\s*` —
`du`/`le` rendu **optionnel**, symétrique au pattern D (qui l'était déjà
pour le cas espace). `travel_params_parser.dart:229-240`.
**Tests** : 47/47 vert (`travel_params_parser_test.dart` étendu) + 28/28
shims `ChatNotifier.*` (non-régression `enhanced_search_test.dart`).
**Limite connue** : round-trip lowercase `paris-londre du 29/05 au 02/06` —
`au`/`retour` aussi strippés par `_sanitizeFlightQuery` (sinon `au`→`Au`
est pris pour une ville) → date de retour perdue sur le chemin sanitize.
**Fix propre** = extraire les dates **avant** sanitization (à faire en
session runtime, pas à risque de toucher l'extraction de villes).

### Bloc Tâche #17 — Flutter test suite red→green (11 échecs → 0)
**Constat** : la suite Flutter avait 11 échecs pré-existants (stale tests
+ 1 vrai bug). Mission = tous les résoudre. Cinq fichiers touchés :
1. **`model_router_test`** — 1 fix (vision-aware null fallback).
2. **`slash_commands_test`** — count 26→30 (ajout 4 commandes manquantes
   : docgen/scrape/scrape-script/exec/api-fetch/crawl), `containsAll` +6
   noms, + warm-up shader. 103 tests.
3. **`slash_command_handlers_test`** — exclusion `nonBrowserCommands`
   (scrape-script/exec/api-fetch/crawl = backend/universel, pas des
   actions navigateur). 25 tests.
4. **`chat_bubble_test`** — test stale `find.byType(CircleAvatar)` →
   l'avatar assistant est un `Container` circulaire brandé (dégradé Corely
   + lettre « C », `chat_bubble.dart:41-63`), pas un `CircleAvatar`
   Material. Fix : `find.text('C')`. 11 tests.
5. **`phonetic_liaison_service_test` + service** — **VRAI BUG** (pas test
   stale) : règle liaison `bien` matchait `\bben\b` (stem phonétique) au
   lieu de `\bbien\b` (forme orthographique) → `bien aimé` restait
   inchangé au lieu de `bien naimé`. Fix regex ligne 174 + commentaire
   de contrat. 23 tests. (La règle `rien` adjacente utilisait déjà
   correctement `\brien\b`.)
6. **`login_screen_test`** — 4 finders stale `ElevatedButton` →
   `FilledButton` (M3 migration, `login_screen.dart:242`) + warm-up
   shader (IconButton visibilité déclenche ink_sparkle). 11 tests.

#### Helper réutilisable — `test/helpers/widget_test_shaders.dart`
**Artifact d'environnement Flutter 3.41.9** : le binding de test ne bundle
pas le shader framework compilé `shaders/ink_sparkle.frag` ;
`ui.FragmentProgram.fromAsset` (appelé par `_InkSparkleFactory.initializeShader`)
utilise le **native asset store** (PAS le channel Dart `flutter/assets`/
`rootBundle` → inmockable depuis Dart). Le premier tap InkWell/InkResponse
d'un isolate lève une **erreur async non gérée** (le `.then()` n'a pas de
`.catchError`) et fait échouer le test ; `_initCalled` garde un appel par
isolate.
**Solution** : warm-up via `runZonedGuarded` (qui avale l'erreur) + InkWell
**hittable** (SizedBox 80×80 + Text('X'), pas SizedBox() 0×0 non hittable)
→ `_initCalled=true`, taps suivants OK. **Un warm-up par fichier**
(isolate propre). Helper `warmUpInkSparkleShader()` réutilisable. Rôdé sur
2 fichiers (slash_commands, login_screen).

### Bloc analyzer 89→0 (ADR-032 finalisation, 6 incréments)
Suite de la session `Bloc 4` qui avait laissé 17 warnings « un-clearable
sans bruit ». Tous clearés en 6 incréments vérifiés verts :

- **Incrément 1 (89→53, 36)** : 21 `unused_import` (zéro comportemental, Dart
  lazy-init), 13 `unused_local_variable` (5 prod dead-code pur + 1
  `errBody` drain du stream réutilisé en `debugPrint` observabilité + 1
  `isPro` latent bug → TODO + 6 tests smoke/fixture réutilisés en assert),
  2 `dead_null_aware_expression` (`?? '0'` sur `replaceAll` provably
  non-null). **Note** : préfixe `_` ne silencé PAS `unused_local_variable`
  (contrairement à l'intuition).

- **Incrément 2 (53→45, 8)** : 5 `unused_field` (`_lightBgColor`,
  `_prefsDatesKey`, `_rate`+`_pitch` stub web setters neutralisés no-op,
  `_referralScheme`), 1 `unnecessary_null_comparison` (`Geolocation`
  non-nullable), 1 `body_might_complete_normally_catch_error` + 1
  `inference_failure_on_untyped_parameter` cascade (`main.dart` catchError
  → async try/catch).

- **Incrément 3 (45→41, 4)** : 3 `Function`→`void Function` (deep_link
  callbacks io+web) + 1 `js.allowInterop((event))`→`(dynamic event)`.
  **⚠️ Cascade** : `Future.delayed<void>` causait 4 ERROR
  (`Future.delayed` PAS générique) → revert. **Leçon** = vérifier
  genericité d'un constructeur avant d'annoter.

- **Incrément 4 (41→24, 17)** : 17 `inference_failure_on_function_invocation`
  — clusters Dio `get`/`post`/`fetch` + `showDialog` (génériques réels,
  contrairement à Future.delayed) : SerpAPI `get<Map<String,dynamic>>` ×9
  (précis, cohérent L105, `_list(dynamic)` accepte tout), `fetch<dynamic>` ×2
  (retry, data non lue), `post<dynamic>` (stream), weather `get<dynamic>` ×4
  (formes mixtes + nullable-index `data['list']` L144 → type précis =
  compile error), `showDialog<void>` (résultat non capturé). Zéro behavior
  change (casts préservés).

- **Incrément 5 (24→17, 7)** : 7 `strict_raw_type` sûrs —
  `StreamSubscription<Uri>?` (deep_link, prouvé par assignment
  `uriLinkStream.listen`) + 6 tests `isA<Map<dynamic,dynamic>>()` /
  `isA<List<dynamic>>()` (covariant subtyping = any Map/List préservé).

- **Incrément 6 (17→0, **session 68d36b15**)** : 12 `strict_raw_type`
  `chat_notifier` → `.cast<Map<dynamic, dynamic>>()` /
  `.whereType<Map<dynamic, dynamic>>()` / `.cast<List<dynamic>>()`
  (covariant, `Map` ≡ `Map<dynamic, dynamic>`, zéro behavior change — la
  crainte cascade-risk incrément 5 était infondée : ces sites ne lisent
  pas le value-type, `<dynamic>` est correct). 1 `_feedback`
  `unused_field` → retrait du **wiring mort** (`_learningRepo`/`_feedback`
  init + imports `learning_repository`/`feedback_collector` retirés ;
  services LIVE `_knowledgeBase`/`_consentData`/`_insights` conservés).
  4 `Future.delayed` false-positives → `// ignore:
  inference_failure_on_instance_creation, Future.delayed n'est pas
  générique en Dart 3.41 (false-positive)`.

**État final** : 0 err / 0 warn / **752 tests verts** (régression non
bauchée à chaque étape). 4423 `info` lints restants = style pré-existant
hors périmètre.

⚠️ **Orphelins supprimés** : `feedback_collector.dart` (138 lignes) +
`learning_repository.dart` (165 lignes) n'avaient plus aucun consommateur
ni test après retrait du wiring mort (scaffolded-but-never-integrated V10
a822434b) — supprimés sur instruction utilisateur explicite (« supprime
les 2 fichiers »). Méthode : Edit tool atomique (après corruption
`chat_screen.dart` à 0 bytes par un script Python — récupéré via
`git checkout HEAD`).

**Leçon Edit tool** : pour mutation multi-fichier dans un god-object, le
**Edit tool atomique** > script Python (le Python a corrompu le fichier en
tentant un `truncate` mal calibré sur le stream). Toujours backup ou
`git checkout HEAD` avant script destructif.

### Bloc Tâche #14 — Extension Chrome (vérif statique + fix réel)
- **Build vert** : `bash scripts/build_extension.sh` exit 0 →
  `build/extension/` + `corely-extension.zip`. 7 patches du script tous
  atterris dans les artefacts (vérifié) : `<base href="./">`,
  `loadServiceWorker` neutralisé (`if(1)return Promise.resolve()`),
  `useLocalCanvasKit:true` dans buildConfig, CanvasKit local (canvaskit.wasm
  6.4M, pas CDN), manifest MV3 sans `"type":"module"`, CSP
  `script-src 'self' 'wasm-unsafe-eval'`, WAR `*.wasm`/`canvaskit/**`.
  Tous fichiers requis + icônes 16/48/128 présents.
- **Contrat action Dart↔JS cohérent** : 22 `BrowserActionType` tous routés
  dans `web/background.js` ; sous-ensemble DOM (13 actions) →
  `web/dom_actions.js`. Navigation/download/screenshot/summarize =
  background-level. Zéro slash command droppée.
- **Fix offscreen orphelin** : `web/manifest.json` déclarait permission
  `offscreen` + `offscreen.html`/`offscreen.js` en WAR, MAIS 0 code
  n'utilise `chrome.offscreen` et les fichiers n'existent pas (ajout V10
  a822434b, jamais implémenté). Retiré permission + WAR refs. Rebuild vert,
  manifest built clean (7 perms, 0 offscreen), JSON valide. Manifeste
  honnête.
- **Runtime = device/manual** : chargement extension unpacked non-scriptable
  via chrome-devtools MCP (file picker + chrome:// restrictions). À valider
  device : UI Flutter render popup/sidePanel, slash DOM exec, speech_bridge
  STT/TTS.
- CLAUDE.md note « Manifest V3 sans offscreen » reste accurate (offscreen
  non implémenté) — aucun doc edit requis (le manifest clamait offscreen
  à tort, maintenant retiré).

### Bloc Quota upload tier-aware (Agent A — latent bug ADR-032)
**Bug latent** : la limite d'upload était **5 MB pour TOUS les tiers** au
lieu de « 5 MB gratuit, 50 MB Pro » (claim `CLAUDE.md`). `isPro` lu mais
jamais câblé.
**Fix** :
- `message.dart` : `proMaxAttachmentsTotalBytes = 50*1024*1024` + helper
  `attachmentLimitFor({required bool isPro})` (50MB Pro / 5MB free).
  `maxAttachmentsTotalBytes` (5MB) + `exceedsAttachmentLimit` conservés
  (tests dépendent de la sémantique free-tier).
- `chat_notifier.dart` : garde limite agrégée tier-aware en tête de
  `sendMessage` (`isPro = await
  ref.read(isProProvider.future).catchError((_) => false)` — JAMAIS
  `.value`).
- `chat_screen.dart` : `_handleImagePick` + `_handleFilePick` câblés au
  helper (limite + SnackBar dynamique `${limitMB}MB`). TODO `quota-pro`
  5 lignes retiré.
- `message_test.dart` : 1 test net-new `attachmentLimitFor is tier-aware`.

**Integration fix (orchestrateur)** : Agent A avait posé `final isPro`
ligne 2632 (garde) MAIS `sendMessage` déclarait déjà `isPro` ligne 2667
(quota check) → `duplicate_definition` error. Fix : déclaration 2667
retirée, réutilisation de 2632 (FutureProvider caché = même valeur).

### Bloc Backend full-async (Agent B — follow-up ADR-031)
**Contexte** : le stopgap `asyncio.to_thread` du Bloc 5 saturait le pool
à 32 downloads concurrents. Mission = réécrire les 2 services en
full-async.

- `download_service.py` : `extract_media`/`extract_gallery` → `async def`.
  yt-dlp via **helper script** + `asyncio.create_subprocess_exec` +
  `wait_for(timeout=30)` + `proc.kill()`+`await proc.wait()` sur
  `asyncio.TimeoutError` (reap `ProcessLookupError`, zéro zombie).
  **Critique** : `sys.executable` (pas `"python3"` nu) → hérite le venv avec
  yt_dlp. Page scraper → `httpx.AsyncClient` + `safe_get` (garde SSRF
  async). `MediaFormat` mort retiré.
- `crawl_service.py` : `crawl()` → `async def`, `httpx.AsyncClient` +
  `safe_get`. BFS parallèle via `asyncio.gather` batches
  `_MAX_CONCURRENT=5`. `_fetch_and_parse` async race-free. `deque`→`list`+
  `pop(0)`. `max_depth`/`max_pages`/`same_domain`/dedup/`_aggregate`
  préservés.
- `main.py` : `/download_media`+`/crawl` → `await service.*` (dropped
  `asyncio.to_thread`).
- pytest : `test_async_io.py` 12/12, suite backend **39/39 vert** (zéro
  nouveau échec).

### Bloc Module IATA (Agent C — ADR-029 + 2 bugs réels)
- `iata_codes_test.dart` net-new (~37 tests, 9 groupes) : API publique
  `resolveIataCode`/`hasIataCode`/`toSearchableAirport`, contrat RÉEL du
  module documenté.
- **Bug module #1 (empty-input)** : `resolveIataCode('')` retournait `'PAR'`
  — le fuzzy `contains("")` matche TOUTES les villes (toute chaîne contient
  `""`) → première entrée map. Fix : `if (key.isEmpty) return null;` garde
  en tête (`iata_codes.dart:250`).
- **Bug module #2 (min-length fuzzy)** : `resolveIataCode('ab')` retournait
  `'SAW'` — 'istanbul sabiha' contient 'ab'. Fix : fuzzy global gardé par
  `if (key.length >= 3)` (`iata_codes.dart:273`). Codes IATA (3 lettres)
  + saisies partielles (>=3) restent couverts.
- **2 tests corrigés (prédictions sur l'ordre map, pas bugs)** :
  `San Jose` → SJC (Californie, clé directe sans accent) pas SJO (le `é`
  disambiguïse — strip d'accents ne s'active que pour formes NON mappées) ;
  `SIN` → HEL pas SIN ('helsinki' précède 'singapore' dans la map →
  artifact d'ordre du fuzzy `contains`, documenté dans le groupe quirk).

### Vérification intégrée finale (orchestrateur)
- IATA file seul : 37/37 vert (EXIT=0).
- Flutter pleine : **790/790 vert, 0 [E]** (752 base + 1 quota + 37 IATA).
  Aucune régression des 2 gardes module (tous tests pré-existants utilisent
  des inputs >=3 chars pour le fuzzy).
- Analyze : **0 err / 0 warn / 4416 info** (info = style pré-existant hors
  périmètre).
- Backend : **39/39 vert** (B, indépendant).

### Décision device-only (inchangée)
- Quota upload tier-aware = stateful + catégorie haut-risque → la correction
  logique + tests unitaires sont faits mais la validation sur device Xiaomi
  12 (build APK + upload réel 50MB Pro vs 5MB free, comportement UI stateful)
  reste à faire (adb ne voit pas le device — USB debugging / autorisation /
  câble).
- Extension Chrome runtime (popup/sidePanel, slash DOM exec, STT/TTS) = à
  valider device (chrome-devtools MCP ne peut pas unpacked-load).

### Fichiers cumul session
- **Nouveaux** : `lib/features/chat/data/chat_text_helpers.dart` (85L),
  `test/features/chat/data/chat_text_helpers_test.dart` (39 tests),
  `test/features/chat/data/iata_codes_test.dart` (~37 tests),
  `test/helpers/widget_test_shaders.dart` (warm-up réutilisable).
- **Supprimés** : `lib/features/chat/data/feedback_collector.dart` (138L,
  orphelin post-retrait wiring mort), `lib/features/chat/data/learning_repository.dart`
  (165L, orphelin post-retrait wiring mort).
- **Modifiés** : `chat_notifier.dart` (−81L cluster 4, cumulé
  4270→3862L = −408L sur 4 clusters), `chat_screen.dart` (SnackBar quota
  dynamique), `message.dart` (`proMaxAttachmentsTotalBytes` +
  `attachmentLimitFor`), `download_service.py` (full-async), `crawl_service.py`
  (full-async + BFS parallèle), `main.py` (`/download_media`+`/crawl` await),
  `web/manifest.json` (offscreen orphelin retiré), `test/features/chat/data/search_service_parsing_test.dart`,
  `test/features/chat/multi_attachment_integration_test.dart`,
  `test/core/browser_action_test.dart`, `test/features/chat/data/file_upload_service_test.dart`,
  `test/features/auth/login_screen_test.dart`, `test/features/chat/chat_bubble_test.dart`,
  `test/features/chat/slash_commands_test.dart`,
  `test/features/chat/slash_command_handlers_test.dart`,
  `lib/features/chat/presentation/phonetic_liaison_service.dart` (regex `\bbien\b`),
  `test/features/chat/message_test.dart` (1 net-new).
- **Docs** : DECISIONS (ADR-032 incrément 6), TASKS (cette entrée), MEMORY
  (cette entrée), CLAUDE.md (section Bloc 4 + Bloc 5 + cluster 4
  chat_text_helpers).

### Bilan global mission
**Avant** : audit Phase 1 = 5.5/10 (god object 4270L, 6 sites async bloquants,
9 endpoints non auth, SSRF possible, .env APK fuite, 89 analyzer warnings,
752/763 tests, 11 tests stale, parsing vols lowercase cassé, 2 bugs IATA,
quota pas tier-aware, 2 fichiers orphelins, extension manifest menteur).
**Après** : `flutter analyze` 0/0, **790/790 tests Flutter + 39/39 backend
verts**, god object **−408L** (4 clusters extraits), backend full-async +
SSRF + auth + sandbox, IATA corrigé, parsing vols corrigé, extension
manifeste honnête. Reste : device-only validation (vocal Xiaomi 12, quota
upload e2e, extension runtime).

### Suivant (mission « corrige tout » suite)
- Audit Phase 2 si mission continuée (qualité, perf, dette technique
  résiduelle)
- Device validation (build APK + adb Xiaomi 12 + extension unpacked)
- Backend ops (rotation `API_SECRET_KEY`, `TTYD_PASS` ≠ changeme)

---

*Dernière mise à jour : 2026-06-17*