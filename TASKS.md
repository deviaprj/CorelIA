# TASKS.md — Suivi AironBot

Dernière mise à jour : 2026-05-06 — Rewarded ads quota recovery + fix bip micro

## Terminé (sessions précédentes)

- [x] **Microphone** — Instance STT fraîche par `startListening()`, `ListenMode.dictation`, deadlock corrigé
- [x] **TTS vitesse** — Réduite à 0.65, pitch 1.10
- [x] **Vision / Images** — Routage prioritaire AVANT Pro/Free, fallback `deepseek-chat`, erreurs formatées
- [x] **Pièces jointes UX** — `AttachmentData` + `SendCallback`, chip preview + ✕
- [x] **Web Search** — `useSearch: true` par défaut, `enable_search: true` dans body DeepSeek
- [x] **Chat bloqué** — `isStreaming: false` forcé dans tous les blocs catch
- [x] **Analyse fichiers** — BOM UTF-8/UTF-16, nom du fichier dans le contexte système
- [x] **Documentation** — CLAUDE.md, MEMORY.md, TASKS.md

## Terminé (session 2026-05-06)

- [x] **Edge TTS + EmotionParser** — `EdgeTtsService` (WebSocket, voix françaises), `EmotionParser` (balises prosodiques), conditional import web/mobile
- [x] **TTS naturel refactorisé** — `TtsNaturalService` avec Edge TTS primaire + flutter_tts fallback, `AudioPlayerFactory`
- [x] **Splash aurora réactif** — `AuroraSplash` avec AnimationControllers, réaction micro, couleurs par émotion
- [x] **Voice conversation + émotion** — `VoiceConversationNotifier` parse les balises, splash change de couleur
- [x] **TTS bridge extension** — `speech_bridge.js` pont TTS avec Web Speech API + mapping émotion
- [x] **Fix bip micro** — Instance STT initialisée une seule fois dans `_initSttOnce()`, réutilisée sans destruction
- [x] **Rewarded ads quota recovery** — `SearchQuotaService` (5/j), `VoiceQuotaService` (10/j), `addBonus()` sur tous les quotas, `QuotaExceededDialog` avec vidéo récompensée, câblage complet chat_notifier + chat_screen
- [x] **Tests** — 45 tests TTS/Edge/emotion + 13 tests quotas/bonus, 241 passants (4 échecs préexistants dotenv)

## En cours

- [ ] **Vérification bip micro sur appareil** — Tester que le fix STT reuse élimine les bips
- [ ] **Vérification rewarded ad flow** — Tester le dialog quota sur appareil (AdMob test IDs)
- [ ] **Vérification `deepseek-chat` vision** — Test live pour confirmer le support `image_url`

---

## 1. AMÉLIORATION DU DIALOGUE VOCAL

### 1.1 TTS Expressif (Edge TTS + balises prosodiques)
- [ ] Intégrer `edge_tts` Dart package ou wrapper HTTP pour Microsoft Edge TTS (gratuit, voix françaises : `fr-FR-HenriNeural`, `fr-FR-DeniseNeural`)
- [ ] Remplacer `flutter_tts` par `EdgeTtsService` dans `TtsNaturalService` (garder `flutter_tts` comme fallback local)
- [ ] Ajouter support des balises prosodiques `[joyeux]`, `[triste]`, `[sérieux]`, `[excité]` dans les réponses DeepSeek (prompt système + parsing côté client)
- [ ] Mapper balises prosodiques → paramètres TTS (rate, pitch, voice)
- [ ] Streaming audio depuis Edge TTS (HTTP chunked) pour réduire la latence
- [ ] Cache TTS : hash du texte → fichier audio local (`path_provider` + `just_audio`)
- [ ] Extension Chrome : pont TTS dans `speech_bridge.js` via `chrome.tts` ou `SpeechSynthesis`

### 1.2 Pipeline Vocal Complet (STT → LLM → TTS)
- [ ] Ajouter extraction d'émotions dans le prompt système DeepSeek : balises `[joyeux]`, `[triste]`, `[sérieux]`, `[excité]`
- [ ] Parser les balises dans `VoiceConversationNotifier._speakResponseAndLoop()` et les retirer du texte avant TTS
- [ ] Transmettre l'émotion détectée au service splash pour changement de couleur/gradient
- [ ] Mode barge-in : permettre d'interrompre le TTS en parlant (détection volume micro)

### 1.3 STT Whisper (fallback/amélioration)
- [ ] Évaluer `whisper.dart` ou appel API OpenAI Whisper comme alternative à `speech_to_text`
- [ ] Mobile : `speech_to_text` reste primaire (natif, offline), Whisper comme fallback
- [ ] Extension Chrome : conserver `webkitSpeechRecognition` (déjà en place)
- [ ] Option dans les paramètres pour choisir le moteur STT (natif vs Whisper)

### 1.4 Détection de silence améliorée
- [ ] Remplacer le polling `_listenWithVad()` (150ms) par des callbacks événementiels
- [ ] VAD basé sur l'amplitude RMS du micro via `record` package (déjà en dépendance)
- [ ] Seuil configurable de silence pour la coupure automatique

---

## 2. ANALYSE DE DOCUMENTS ET D'IMAGES

### 2.1 Vision via Ollama (modèle multimodal local)
- [ ] Créer `OllamaVisionService` dans `lib/features/chat/data/` : appelle `http://<host>:11434/api/generate` avec modèle multimodal (`llava:13b` ou `minicpm-v`)
- [ ] Mobile : Ollama sur PC du réseau local → champ de configuration IP dans les paramètres
- [ ] Extension : Ollama accessible via `localhost:11434`
- [ ] Fallback cloud gratuit si Ollama indisponible : OpenRouter GPT-4o-mini (déjà en place) ou Google Gemini Flash (gratuit tier)
- [ ] Modifier le routage dans `_getVisionStream()` : Ollama priorité (si configuré), sinon OpenRouter, sinon DeepSeek vision
- [ ] Détection automatique d'Ollama au démarrage (ping `GET /api/tags`)

### 2.2 Analyse de documents améliorée
- [ ] PDF scannés : OCR via `google_mlkit_text_recognition` (mobile) ou Tesseract.js (extension)
- [ ] Images intégrées dans documents : extraire images du PDF/DOCX (`archive`) → modèle vision → description dans contexte DeepSeek
- [ ] Améliorer extraction DOCX : préserver les paragraphes (sauts de ligne)
- [ ] Améliorer extraction XLSX : préserver structure tabulaire et en-têtes
- [ ] Ajouter support PPTX (extraction `ppt/slides/slide*.xml`)
- [ ] Augmenter limite contexte de 15000 à 30000 caractères avec résumé automatique si dépassement

### 2.3 Drag & Drop pour l'extension
- [ ] Ajouter `dragover` / `drop` event listeners dans `content_script.js`
- [ ] Transférer fichiers via `chrome.runtime.sendMessage` vers le side panel Flutter
- [ ] Même flux `AttachmentData` côté extension

---

## 3. RECHERCHE INTERNET OPTIMISÉE

### 3.1 Cache intelligent
- [ ] Créer `SearchCacheService` dans `lib/features/chat/data/` avec TTL configurable (défaut : 15 min)
- [ ] Stocker en mémoire (LRU, max 100 entrées) + `SharedPreferences` pour persistance inter-sessions
- [ ] Clé de cache : hash SHA-256(query + langue)
- [ ] Invalidation automatique à l'expiration du TTL
- [ ] Vérifier la connexion réseau avant appel (`connectivity_plus`, déjà en dépendance)

### 3.2 Requêtes optimisées
- [ ] Debouncer de recherche (500ms) pour éviter les appels multiples similaires
- [ ] DuckDuckGo Instant Answer API comme source supplémentaire (plus fiable que HTML scraping)
- [ ] Dédoublonner les résultats (même URL ou titre similaire)

### 3.3 Optimisation réseau mobile
- [ ] Réduction du contexte injecté : résumer les résultats si > 2000 tokens au lieu de tronquer
- [ ] Mode hors-ligne : retourner les résultats en cache si pas de connexion

---

## 4. EXTENSION GOOGLE CHROME (enrichissement)

### 4.1 Synchronisation des conversations
- [ ] Vérifier que `watchConversations()` et `watchMessages()` (Firestore snapshots) sont branchés dans l'extension
- [ ] Auth Firebase dans l'extension (même projet Firebase que mobile)
- [ ] Sync des préférences via Firestore `user_preferences` + `chrome.storage.sync`

### 4.2 Résumé de page courante
- [ ] Bouton "Résumer cette page" dans l'interface de l'extension
- [ ] Injecter Readability.js dans `content_script.js` pour extraire le contenu pertinent
- [ ] Envoyer le contenu à DeepSeek avec prompt de résumé
- [ ] Afficher le résumé dans le chat avec la source (URL + titre)

### 4.3 Remplissage automatique de formulaires (autofill)
- [ ] Système de "recettes" CSS dans `web/recipes/` :
  - [ ] Kayak (vols) : sélecteurs pour origine, destination, dates, passagers
  - [ ] Booking (hôtels) : sélecteurs pour ville, dates, nombre de personnes
  - [ ] Amazon (shopping) : sélecteurs pour recherche, filtres
- [ ] `autofill_service.js` : parse la demande → match URL → injecte les valeurs → soumet
- [ ] Permission `tabs` pour l'ouverture d'onglets

### 4.4 Extraction et téléchargement de médias
- [ ] Fonction "Lister les médias de cette page" dans l'interface
- [ ] Scanner le DOM : `<video>`, `<iframe>`, sources JSON, `<img>`, `background-image`
- [ ] Reconstruire les URLs fragmentées (m3u8, DASH) quand possible
- [ ] Liste cliquable avec miniatures dans le side panel
- [ ] Téléchargement via `chrome.downloads.download()` (ajouter permission `downloads`)
- [ ] Avertissement droits d'auteur avant chaque téléchargement

### 4.5 Activation vocale ("Assistant")
- [ ] Permission `offscreen` dans `manifest.json` pour `webkitSpeechRecognition` en continu
- [ ] Détection du mot-clé "Assistant" en arrière-plan
- [ ] Toggle dans les paramètres de l'extension pour activer/désactiver l'écoute permanente
- [ ] Relay vers le side panel Flutter via `chrome.runtime.sendMessage`

### 4.6 Contournement des pubs
- [ ] Intégrer EasyList (sous-ensemble) dans `content_script.js` pour masquer les intrusifs
- [ ] Readability pour nettoyer le contenu avant envoi au LLM
- [ ] Toggle dans les paramètres de l'extension

---

## 5. ÉCRAN DE SPLASH ANIMÉ PAR LA VOIX

### 5.1 Forme réactive au volume
- [ ] Remplacer les 15 `AuroraParticle` aléatoires par une forme centrale unique (cercle/losange organique)
- [ ] `AnimationController` + `AnimatedBuilder` pour animation fluide 60fps
- [ ] Brancher l'amplitude RMS du micro (`record` package) pour faire pulser la forme
- [ ] Diamètre variable avec le volume : silence = taille min, voix forte = taille max
- [ ] Interpolation `Curves.easeInOutCubic` pour transitions douces

### 5.2 Gradient animé et émotions
- [ ] Gradient animé autour de la forme centrale (onde concentrique)
- [ ] Mapper les balises prosodiques aux palettes de couleurs :
  - Joyeux : jaune/orange
  - Triste : bleu/violet
  - Sérieux : gris/vert foncé
  - Excité : rouge/orange vif
  - Neutre : bleu/cyan
- [ ] Transitions de couleurs douces (1-2 secondes entre les palettes)
- [ ] L'onde suit le volume : plus le volume est élevé, plus l'onde est intense

### 5.3 Réduction du jitter visuel
- [ ] State persistant pour les animations (ne pas régénérer les particules à chaque `build()`)
- [ ] Lissage de l'amplitude RMS (moyenne mobile sur 3-5 frames)
- [ ] Désactiver l'overlay pendant les transitions d'état rapides (thinking → speaking)

---

## 6. SYNCHRONISATION MULTI-APPAREILS

### 6.1 Conversations en temps réel
- [ ] Vérifier que `watchConversations()` et `watchMessages()` sont actifs dans l'extension
- [ ] Gestion des conflits : dernier message gagne en cas de modification concurrente
- [ ] Optimiser la bande passante : Firestore snapshots natifs gèrent les deltas, vérifier l'activation

### 6.2 Préférences et historique
- [ ] Collection Firestore `user_preferences` : thème, langue, modèle préféré, paramètres vocaux, toggles
- [ ] Sync via `chrome.storage.sync` (extension) + `SharedPreferences` + Firestore (mobile)
- [ ] Écouteur de changements distants pour les mises à jour en temps réel

### 6.3 Authentification partagée
- [ ] Vérifier que l'extension utilise le même Firebase Auth (même projet)
- [ ] Support Google Sign-In dans l'extension Flutter Web
- [ ] Gestion des tokens entre side panel et background service worker

---

## Priorités d'implémentation

1. **P0** — TTS Expressif (1.1) : impact immédiat sur l'UX vocal, Edge TTS gratuit et rapide à intégrer
2. **P0** — Splash animé (5.1, 5.2) : refactor de l'existant, pas de nouvelle dépendance critique
3. **P1** — Vision Ollama (2.1) : ajoute une capacité visuelle locale, fallback cloud déjà en place
4. **P1** — Recherche web optimisée (3.1, 3.2) : cache + debouncer améliore l'expérience mobile
5. **P2** — Extension enrichie (4.2, 4.4) : résumé de page + extraction média
6. **P2** — Pipeline prosodique (1.2) : nécessite Edge TTS en place d'abord
7. **P3** — Autofill (4.3) : complexe, nécessite maintenance des recettes CSS
8. **P3** — Sync multi-appareils (6) : déjà partiellement en place via Firestore
9. **P4** — Activation vocale (4.5) : nécessite offscreen document + permissions
10. **P4** — OCR et documents avancés (2.2) : l'extraction texte actuelle couvre les cas courants