# CorelIA — Décisions Architecturales (ADR)

Ce fichier documente les décisions architecturales importantes prises durant le développement d'CorelIA.

---

## ADR-001 : Flutter + Riverpod pour le Cross-Platform

**Date** : 2026-01-15
**Statut** : Accepté

### Contexte
Besoin d'une application mobile (Android/iOS) et d'une extension Chrome avec 95% de code partagé.

### Décision
Utilisation de **Flutter 3.24+** avec **Riverpod** comme state management.

### Alternatives Considérées
- React Native + Redux (moins de partage avec extension web)
- PWA pure (moins bonnes performances mobile)
- Kotlin/Swift natif (pas de partage de code)

### Conséquences
- ✅ 95% de code partagé
- ✅ Performance native
- ✅ Extension Chrome via Flutter Web
- ⚠️ Taille APK/IPA plus grande
- ⚠️ Firebase non supporté sur Linux desktop

---

## ADR-002 : Firebase comme Backend

**Date** : 2026-01-15
**Statut** : Accepté

### Contexte
Besoin d'un backend temps réel avec auth, database, et serverless functions.

### Décision
Utilisation complète de **Firebase** :
- Auth : Email, Google, Apple, Anonymous
- Firestore : Base de données temps réel
- Cloud Functions : Logique server-side (quotas, webhooks)
- FCM : Notifications push

### Alternatives Considérées
- Supabase (open-source, mais moins mature)
- AWS Amplify (plus complexe, vendor lock-in)
- Backend personnalisé Node.js (plus de maintenance)

### Conséquences
- ✅ Développement rapide
- ✅ Sync temps réel automatique
- ✅ Scale automatique
- ⚠️ Vendor lock-in Firebase
- ⚠️ Coûts potentiels à grand scale

---

## ADR-003 : DeepSeek-V3 + OpenRouter pour l'IA

**Date** : 2026-01-20
**Statut** : Accepté

### Contexte
Besoin de fournir une IA gratuite aux utilisateurs + options Pro.

### Décision
- **Gratuit** : DeepSeek-V3 via API directe (deepseek-chat)
- **Pro** : OpenRouter pour accéder à Mistral Large 2, Llama 3.3 70B

### Alternatives Considérées
- OpenAI API (payant, pas de tier gratuit viable)
- Anthropic Claude (payant)
- Auto-hébergement (trop complexe)

### Conséquences
- ✅ Tier gratuit viable avec DeepSeek
- ✅ Flexibilité Pro via OpenRouter
- ✅ Pas de coûts d'infrastructure IA
- ⚠️ Dépendance aux APIs tierces
- ⚠️ Latence réseau pour les appels API

---

## ADR-004 : RevenueCat + Stripe pour la Monetization

**Date** : 2026-01-22
**Statut** : Accepté

### Contexte
Besoin de gérer les abonnements Pro sur mobile et web.

### Décision
- **Mobile** : RevenueCat (abstrait StoreKit + Google Play Billing)
- **Web/Extension** : Stripe Checkout + webhooks

### Alternatives Considérées
- RevenueCat partout (ne supporte pas le web)
- Stripe partout (nécessite apps natives pour mobile)
- Solutions propriétaires Apple/Google (28-30% de commission)

### Conséquences
- ✅ RevenueCat gère les receipts et la validation
- ✅ Stripe pour le web avec contrôle total
- ⚠️ Deux systèmes à maintenir
- ⚠️ Synchronisation des états d'abonnement

---

## ADR-005 : Quotas Server-Side via Cloud Functions

**Date** : 2026-01-25
**Statut** : Accepté

### Contexte
Besoin de limiter les requêtes des utilisateurs gratuits (20/jour).

### Décision
Implémentation du quota dans une **Cloud Function** (`checkQuota`) plutôt qu'en local.

### Alternatives Considérées
- Quota client-side (facilement bypassable)
- Quota Firestore avec transactions (plus complexe)

### Conséquences
- ✅ Impossible à contourner côté client
- ✅ Reset automatique quotidien
- ⚠️ Latence ajoutée (appel réseau)
- ⚠️ Mode dégradé nécessaire si Function indisponible

---

## ADR-006 : Architecture MVVM Simplifiée

**Date** : 2026-02-01
**Statut** : Accepté

### Contexte
Besoin d'une architecture maintenable pour une équipe potentiellement grande.

### Décision
Pattern **MVVM** avec Riverpod :
- **Model** : Entités dans `domain/`
- **ViewModel** : Notifiers Riverpod
- **View** : Widgets Flutter

### Alternatives Considérées
- Clean Architecture complète (trop de boilerplate)
- BLoC (plus verbeux)
- Provider simple (moins testable)

### Conséquences
- ✅ Code testable et maintenable
- ✅ Séparation claire des responsabilités
- ⚠️ Courbe d'apprentissage Riverpod
- ⚠️ Plus de fichiers que le pattern MVC

---

## ADR-007 : Chrome Extension via Flutter Web

**Date** : 2026-02-05
**Statut** : Accepté

### Contexte
Besoin d'une extension Chrome avec la même UX que l'app mobile.

### Décision
Build Flutter Web + adaptation Manifest V3 :
- Suppression du Service Worker Flutter
- Ajout de `background.js`, `content_script.js`
- Utilisation de `chrome.storage.local` pour le storage

### Alternatives Considérées
- Extension native JavaScript/TypeScript (100% de code en plus)
- PWA installable (moins d'intégration Chrome)

### Conséquences
- ✅ 95% de code partagé avec mobile
- ✅ Même UX partout
- ⚠️ Taille de l'extension (~2-3 MB)
- ⚠️ Adaptations Manifest V3 nécessaires

---

## ADR-008 : Secure Storage pour les API Keys

**Date** : 2026-02-10
**Statut** : Accepté

### Contexte
Les utilisateurs peuvent fournir leur propre clé API DeepSeek.

### Décision
- **Mobile** : `flutter_secure_storage` (Keychain/Keystore)
- **Web** : `shared_preferences` (avec préfixe `airon_secure_`)

### Alternatives Considérées
- Stockage local non sécurisé
- Chrome.storage.sync pour l'extension

### Conséquences
- ✅ Clés chiffrées sur mobile
- ✅ Synchronisation possible sur web
- ⚠️ Web storage non sécurisé (limitation documentée)

---

## ADR-009 : Contexte IA Limité aux 20 Derniers Messages

**Date** : 2026-02-15
**Statut** : Accepté

### Contexte
Besoin de limiter le contexte envoyé à l'IA pour contrôler les coûts.

### Décision
Envoyer les **20 derniers messages** (pas les 20 premiers).

### Implémentation
```dart
final history = state.messages
    .where((m) => m.role != Role.system && !m.isStreaming)
    .toList()
    .reversed
    .take(AppConstants.maxContextMessages)
    .reversed
    .map((m) => m.toApiMap())
    .toList();
```

### Conséquences
- ✅ Contexte pertinent (messages récents)
- ✅ Coûts API maîtrisés
- ⚠️ Perte du contexte ancien
- ⚠️ Bug initial : `.take()` prenait les premiers messages (corrigé)

---

## ADR-010 : AdMob pour la Monétisation Gratuite

**Date** : 2026-02-20
**Statut** : Accepté

### Contexte
Les utilisateurs gratuits doivent voir des publicités.

### Décision
- **Bannières** : En bas de l'écran de chat
- **Interstitials** : Après X conversations
- **Rewarded** : +5 requêtes gratuites

### Alternatives Considérées
- Pas de pubs (modèle 100% freemium)
- Pubs natives uniquement

### Conséquences
- ✅ Revenus même sur le tier gratuit
- ✅ Rewarded pour l'engagement
- ⚠️ UX dégradée pour les gratuits
- ⚠️ Gestion spécifique par plateforme

---

## ADR-011 : Recherche Enrichie avec Fallback DuckDuckGo

**Date** : 2026-05-14
**Statut** : Accepté

### Contexte
La recherche enrichie (vols, hôtels, produits, météo) nécessite des APIs externes (SerpAPI, OpenWeatherMap) qui peuvent être absentes du `.env`. Sans fallback, les utilisateurs recevaient des réponses génériques "je n'ai pas accès aux systèmes de réservation".

### Décision
Architecture de fallback en 3 niveaux :
1. **API dédiée** (SerpAPI, OWM) si clé disponible
2. **DuckDuckGo HTML scraping** avec décodage des URLs de redirection (`uddg` param)
3. **Liens directs** toujours générés (Skyscanner, Google Flights, Kayak, Opodo, Booking, Airbnb) avec les paramètres extraits

Les résultats sont injectés comme message système dans le contexte IA (`enhancedContext` → `_buildStream()`) pour que l'IA les présente naturellement.

### Pattern d'extraction de paramètres
- **2-stage parsing** : tentative originale → sanitization (45 stop words) → capitalisation → retry
- **Regex sans raw strings** : concaténation pour interpoler les variables dans les patterns
- **Multilingue** : patterns de déclenchement dans 6 langues, noms de mois localisés

### Alternatives Considérées
- SerpAPI obligatoire (ne fonctionne pas sans clé)
- Backend cloud uniquement (dépendance réseau, latence)
- Pas de recherche enrichie (expérience utilisateur dégradée)

### Conséquences
- ✅ Recherche enrichie fonctionnelle sans aucune clé API
- ✅ IA présente les résultats de façon naturelle
- ✅ Liens comparateurs toujours générés
- ⚠️ DuckDuckGo scraping fragile (dépend du markup HTML)
- ⚠️ Pas de résultats structurés (prix, disponibilité) sans SerpAPI
- ⚠️ Extraction de paramètres limitée aux vols/hôtels/produits/météo

---

## ADR-012 : Architecture Search-First avec Liens Directs Comparateurs

**Date** : 2026-05-15
**Statut** : Accepté (remplace l'approche DuckDuckGo scraping de l'ADR-011)

### Contexte
L'approche ADR-011 (DuckDuckGo HTML scraping) produisait des résultats trop génériques. Les utilisateurs recevaient des réponses vagues comme "Les résultats ne donnent pas de tarif précis pour ces dates exactes" au lieu de vrais liens vers les comparateurs. La construction directe d'URLs de comparateurs avait été abandonnée car les URLs étaient malformées (mauvais codes IATA, formats de date incorrects).

### Décision
**Architecture "search-first" en 2 niveaux** :
1. **SerpAPI** pour données structurées si clé disponible (google_flights, google_hotels, google_shopping, google_events, google_local)
2. **Liens directs** vers les comparateurs TOUJOURS générés avec paramètres pré-remplis :
   - Vols : Google Flights, Skyscanner, Kayak, Kiwi, Expedia, Opodo, Momondo
   - Hôtels : Booking, Expedia, Hotels.com, Agoda, Trivago, TripAdvisor, Airbnb, Abritel, Trip.com, GoVoyages
   - Restaurants : TripAdvisor, TheFork, Google Maps
   - Locations : Airbnb, Abritel, Booking, Casamundo, HomeToGo
   - Occasion : eBay, Rakuten, Back Market, Vinted, Leboncoin

**Suppression du DuckDuckGo scraping** comme source primaire — les liens directs sont toujours plus pertinents.

### Extraction de paramètres généralisée
- **SearchIntentExtractor** : 9 types d'intents, 6 langues
- **SearchMemory** : apprentissage des patterns de recherche réussies
- **Validation** : `_isValidCityPair()` pour détecter les extractions erronées et fallback vers `parseFlightParams`
- **Sanitization + Capitalization** : fallback automatique pour les requêtes lowercase

### IATA Codes
- ~300 aéroports majeurs mappés
- Fuzzy matching 3 niveaux : direct → contains → per-word → prefix 5 caractères
- Exemple : "londre direct du" → mot "londre" → prefix "londr" match "londres" → LON

### Conséquences
- ✅ Utilisateurs obtiennent TOUJOURS des liens cliquables vers les comparateurs
- ✅ Pas de dépendance au markup HTML de DuckDuckGo
- ✅ Les URLs utilisent les IATA codes résolus pour une meilleure compatibilité
- ✅ Extraction de paramètres robuste avec validation et fallback
- ⚠️ Sans SerpAPI, pas de prix/offres structurés (seulement les liens)
- ⚠️ Les URLs de comparateurs peuvent changer (mais les formats choisis sont stables)
- ⚠️ ~300 aéroports couverts — les petits aéroports régionaux peuvent manquer

---

## ADR-013 : Extraction de Paramètres Vols — Double Fallback

**Date** : 2026-05-15
**Statut** : Accepté

### Contexte
Les requêtes utilisateur sont souvent en lowercase avec des mots parasites : "trouve un billet aller retour paris-londre direct du 29/05/2026 au 01/06/2026". Les regex d'extraction (`cityName = [A-ZÀ-Ÿ][a-zà-ÿ]+`) échouent sur le lowercase. Le fallback `_extractCities` extrayait des mots parasites ("Trouve", "Billet", "Aller", "Retour", "Direct") comme noms de ville.

### Décision
Triple protection :
1. **`_tryParseFlightParamsGeneric`** : essai sur message original → si échec, sanitize (45 stop words) + capitalize → réessai
2. **`_extractCities`** : patterns rendus case-insensitive, `direct`/`directs` ajoutés aux stop words
3. **`_isValidCityPair`** dans `_performEnhancedSearch` : rejette les villes de >3 mots ou contenant des termes parasites → fallback `parseFlightParams` (qui a déjà le sanitize+capitalize)

### Conséquences
- ✅ Requêtes lowercase fonctionnent
- ✅ Mots parasites filtrés à 3 niveaux
- ⚠️ Si les 3 niveaux échouent, pas de recherche de vol

---

---

## ADR-014 : Robustesse DuckDuckGo — Multi-Endpoint + Patterns Fallback

**Date** : 2026-05-21
**Statut** : Accepté

### Contexte
Le scraping HTML de DuckDuckGo échouait fréquemment car DuckDuckGo change son markup HTML et bloque certaines requêtes selon l'User-Agent. Un seul endpoint (`html.duckduckgo.com/html/`) et un seul User-Agent n'étaient pas suffisants.

### Décision
Architecture multi-endpoint avec failover :
1. **3 endpoints** tentés en cascade : `html.duckduckgo.com/html/` → `lite.duckduckgo.com/lite/` → `duckduckgo.com/html/`
2. **Rotation User-Agent** : Android, iOS, Desktop pour éviter le blocage
3. **Protection HTML** : tronquage à 500KB avant regex (prévention catastrophic backtracking)
4. **Pattern `uddg`** : support du paramètre de redirection `uddg` utilisé par les nouveaux layouts DuckDuckGo
5. **5 patterns regex** en cascade : encodé `/l/?u=` → direct → `uddg` → fallback classique → ultra-souple

### Conséquences
- ✅ Recherche web fonctionnelle même si un endpoint ou un layout change
- ⚠️ Plus de trafic réseau potentiel (3 endpoints max)
- ⚠️ Les patterns regex restent fragiles face à des changements majeurs de markup

---

## ADR-015 : Extraction XML Namespace-Agnostic pour Office Documents

**Date** : 2026-05-21
**Statut** : Accepté

### Contexte
L'extraction de texte DOCX et PPTX utilisait `findAllElements('w:p')` et `findAllElements('a:t')`, ce qui dépendait du préfixe de namespace exact (`w:`, `a:`, `p:`). Certains fichiers Office utilisent des préfixes différents ou des déclarations de namespace non standard, causant une extraction vide.

### Décision
Remplacer la recherche par préfixe par une recherche par **localName + namespaceUri** :
- DOCX : `name.local == 'p' && namespaceUri.contains('wordprocessingml')`
- PPTX : `name.local == 't'` (tous les nœuds texte), `name.local == 'sp'` (shapes)
- Fallback : si extraction structurée échoue, extraire tous les nœuds `t` sans restriction
- Gestion d'erreurs : `XmlException` et `ArchiveException` capturés avec message clair

### Conséquences
- ✅ Extraction fonctionnelle quel que soit le préfixe de namespace
- ✅ Meilleure tolérance aux fichiers corrompus ou mal formés
- ⚠️ Légèrement plus de code (itérateur descendants manuel)

---

## ADR-016 : Scraping Intelligent Cross-Plateforme via Backend Cloud

**Date** : 2026-05-21
**Statut** : Accepté

### Contexte
Les commandes slash (`/summarize`, `/extract`, `/links`, `/metadata`) ne fonctionnaient que sur l'extension Chrome car elles dépendaient de `ExtensionBridge` + `dom_actions.js` injecté dans l'onglet navigateur. Sur mobile/web, ces commandes retournaient une erreur ou un résultat vide. De plus, la recherche enrichie (vols, hôtels, produits) générait uniquement des liens vers des comparateurs sans scraper les prix/offres réels.

### Décision
**Architecture backend-first pour le scraping et la recherche structurée** :
1. **Backend `/scrape`** : endpoint FastAPI qui scrape n'importe quelle URL avec BeautifulSoup. Supporte les sélecteurs CSS personnalisés ou l'auto-extraction (metadata, prix, cartes, liens).
2. **Backend `/search_smart`** : orchestrateur qui (a) classifie l'intent avec un LLM, (b) construit des URLs de comparateurs, (c) scrape en parallèle plusieurs sources, (d) agrège les résultats structurés.
3. **Dart `SearchServiceGlobal`** : client unifié qui appelle `/search_smart` et `/scrape`, puis formate les résultats en markdown selon l'intent (vols, hôtels, produits, restaurants, événements, météo).
4. **Slash commands universels** : `/summarize <url>`, `/extract <url> [selector]`, `/links <url>`, `/metadata <url>`, `/scrape <url>` fonctionnent sur toutes les plateformes. Si une URL est fournie, le backend est appelé. Si aucune URL n'est fournie (extension uniquement), le comportement DOM local est conservé.
5. **Sélecteurs "learned"** : dictionnaire `_LEARNED_SELECTORS` en mémoire Python qui mappe les domaines connus (backmarket.fr, booking.com, skyscanner.fr, etc.) vers les sélecteurs CSS pertinents pour l'extraction de prix et titres.

### Alternatives Considérées
- Scraping côté client avec `dio` + `html` package (bloqué par CORS sur web, fragile sur mobile)
- APIs tierces uniquement (SerpAPI) — coûteux et couverture limitée
- Pas de support mobile pour les commandes slash DOM — expérience dégradée

### Conséquences
- ✅ Commandes slash fonctionnent sur mobile, web, extension
- ✅ Résultats de recherche avec vrais prix et offres extraits des comparateurs
- ✅ Pas de dépendance CORS côté client
- ⚠️ Dépendance au backend cloud `api.zentic.fr` (mais le fallback "liens directs" reste disponible côté client si le backend est down)
- ⚠️ Latence réseau ajoutée (~1-3s pour le scraping multi-source)
- ⚠️ Les sélecteurs CSS des sites peuvent changer — nécessite un mécanisme de mise à jour des `_LEARNED_SELECTORS`

---

## ADR-017 : Vocal Turn-Taking — VAD Prosodique, Barge-In par Intention, et Hésitations TTS

**Date** : 2026-05-22
**Statut** : Accepté

### Contexte
Le mode conversation vocal mains-libres de Corely fonctionnait mais manquait de fluidité humaine. L'IA attendait la fin complète du texte avant de parler, coupait l'utilisateur sur un simple bruit pendant le TTS, et avait une voix robotique sans respiration.

### Décision
Architecture en 4 couches pour un turn-taking humain :

1. **VAD Prosodique** (`ProsodyVadAnalyzer`) :
   - Remplace le timer fixe (1.5s) par une analyse multi-facteurs : ponctuation finale + silence 400ms, pas de ponctuation + silence 900ms, chute d'énergie mic sous 15% du pic sur 300ms, safety cap 12s.
   - Distingue `breathingPause` (silence 200-400ms + énergie qui remonte) de `endOfPhrase` pour éviter de couper l'utilisateur en plein milieu d'une phrase.
   - Pas d'accès au buffer audio brut (limitation `speech_to_text`), donc utilisation de `onSoundLevelChange` comme proxy d'énergie vocale.

2. **Streaming TTS par phrase** :
   - `VoiceConversationNotifier._speakStreamingSentences()` parle les phrases complètes dès qu'elles arrivent du LLM (SSE streaming).
   - Si aucune fin de phrase n'est trouvée après 120 caractères, parle le fragment quand même (évite l'attente indéfinie).
   - Seuils réduits : 12 chars première phrase, 20 chars suivantes.

3. **Barge-in par intention** (`BargeInIntentClassifier`) :
   - Classification regex en 5 intentions (stop, topicChange, correction, repeat, none) sans appel LLM.
   - Single-word shortcuts : "stop" → stop, "non" → correction, "encore" → repeat.
   - Behaviors spécifiques : `repeat` relit `_lastSpokenText` sans appeler le LLM ; `topicChange` préfixe "Changement de sujet : " ; autres interrompent et envoient un nouveau message.
   - Audio barge-in (micro pendant TTS) : exige `micLevel > 0.12` pendant > 200ms pour éviter les pics parasites.

4. **Hésitations naturelles** (`VocalHesitationInjector`) :
   - Post-processing TTS déterministe, pas d'injection dans le prompt LLM.
   - Règles probabilistes : prefix "euh, " / "hmm, " (40% × intensity), mid-sentence "euh" après virgule (25% × intensity), pause "..." mid-sentence si > 80 chars (20% × intensity).
   - Jamais dans les URLs ou le markdown.

### Alternatives Considérées
- **Timer fixe** (1.5s) : trop lent, coupe les utilisateurs en pleine phrase.
- **Barge-in audio simple** (n'importe quel son coupe le TTS) : coupait sur un simple bruit ou parole sans sens.
- **Injection hésitations dans le prompt LLM** : non déterministe, difficile à contrôler, modifie la qualité de la réponse texte.
- **StyleTTS 2 / ElevenLabs native** : excellente qualité mais coûteux (ElevenLabs) ou nécessite un serveur GPU (StyleTTS 2). L'injection déterministe est un bon compromis gratuit immédiat.

### Conséquences
- ✅ Latence utilisateur→IA réduite à < 300ms (streaming par phrase + VAD intelligent)
- ✅ Conversations infinies sans interruption involontaire
- ✅ Voix plus humaine avec hésitations et pauses
- ✅ Barge-in explicite détecté sans appel LLM (pas de coût supplémentaire)
- ⚠️ `speech_to_text` ne donne pas de buffer audio brut → le VAD est approximatif (proxy mic level)
- ⚠️ Edge TTS streaming (WebSocket) est complexe à intégrer et mobile-only

---

## ADR-018 : Simplification Radicale du Mode Vocal — Tour-par-Tour Half-Duplex

**Date** : 2026-05-22
**Statut** : Accepté (remplace l'ADR-017)

### Contexte
L'architecture V15/VAD prosodique (ADR-017) s'est révélée fondamentalement instable sur Android. Après 3+ tentatives de correction (VAD amélioré, dedup, retry micro), les symptômes persistants étaient :
- Détection aléatoire de fin de phrase (silence mal mesuré car STT Android rafraîchit les partiels toutes les ~100ms)
- TTS décousu (phrases dans le désordre, coupées, milieu manquant) — race conditions entre les `Completers` globaux de flutter_tts
- Monologue (STT capte l'écho du TTS et envoie la réponse vocale de l'IA à l'IA)
- Micro mort après le premier tour (redémarrage STT échoue silencieusement)
- Architecture trop complexe : 4 couches concurrentes (VAD custom, streaming TTS par phrases, full-duplex, barge-in audio) sur un plugin `speech_to_text` conçu pour la dictée ponctuelle

### Décision
**Architecture tour-par-tour half-duplex simplifiée** :

1. **Pas de VAD custom** : suppression de `ProsodyVadAnalyzer`, timer 50ms, `_speechFinalEmitted`. Utilisation de `result.finalResult` natif du STT uniquement.
2. **Pas de streaming TTS par phrases** : suppression de `_speakStreamingSentences()`, `_speakRemaining()`, `_findSentenceEnd()`. La réponse complète est parlée d'un bloc via `speakNaturally()`.
3. **Half-duplex explicite** : le micro est coupé AVANT le TTS (`stopListening()`), puis rouvert APRÈS le TTS (`startListening()`). Plus d'écho capturé, plus de monologue.
4. **Barge-in par speech final** : pendant le TTS, un nouveau `SpeechFinalEvent` (transcript > 3 mots pour éviter l'écho) déclenche `stopSpeaking()` + nouveau message LLM.
5. **Gestion explicite du cycle** : `VoiceConversationNotifier` contrôle entièrement les transitions listening → thinking → speaking → listening. Le `VoiceServiceNotifier` ne redémarre pas automatiquement le micro.

### États simplifiés
```
idle → listening → thinking → speaking → listening → ...
                    ↑__________________________________|
```

### Fichiers supprimés
- `prosody_vad_analyzer.dart` (169 lignes)

### Fichiers modifiés
- `voice_service.dart` : STT continu simplifié, pas de VAD, `setConversationMode()` gère le redémarrage, `onStatus` n'agit pas en mode conversation
- `voice_conversation_service.dart` : machine à états tour-par-tour, `_speakFullResponse()` parle le bloc complet, barge-in via speech final
- `tts_natural_service.dart` : suppression `speakStreaming()`, `setHesitationEnabled()`
- `chat_screen.dart`, `aurora_splash.dart` : suppression état `processingStt`

### Ce qu'on perd
- Streaming temps réel du TTS (on attend la fin du stream LLM)
- Full-duplex (micro coupé pendant le TTS)
- Hésitations TTS naturelles (désactivées, pas supprimées du code)

### Ce qu'on gagne
- Conversation vocale fiable à N tours sans blocage
- TTS fluide et complet (pas décousu)
- Pas de monologue (pas d'écho capturé)
- Code beaucoup plus simple (-466 lignes net)

### Alternatives Considérées
- Continuer à patcher l'architecture V15 (3+ patchs échoués — loi du debugging : après 3 échecs, questionner l'architecture)
- Utiliser un plugin STT différent (`speech_to_text` est le seul mature sur Flutter)
- Implémenter le VAD côté natif Kotlin (complexe, pas de partage avec iOS/web)
- Passer à un modèle de conversation vocale basé sur des pauses fixes (1.5s) sans VAD custom (rejeté : trop lent)

### Conséquences
- ✅ Mode vocal fiable et testable
- ✅ Pas de race conditions STT/TTS
- ✅ Code maintenable (-466 lignes)
- ⚠️ Latence légèrement supérieure (on attend la fin du stream LLM avant de parler)
- ⚠️ Pas de barge-in instantané (il faut attendre que le STT détecte `finalResult`)
- ⚠️ Pas de full-duplex (micro coupé pendant le TTS)

## ADR-019 : Algorithme de Récompense Publicitaire Progressif (AdRewardTracker)

**Date** : 2026-05-23
**Statut** : Accepté

### Contexte
Le modèle actuel de vidéos récompensées (1 vidéo = +5 messages) est trop généreux et ne maximise pas le LTV. Les utilisateurs regardent une vidéo et obtiennent 5 messages, mais il n'y a pas d'incitation à revenir ni de progression dans l'engagement.

### Décision
**Algorithme progressif à 3 tiers** :
- **Tier 0** (nouveau/jour 1) : 1 vidéo = +5 messages
- **Tier 1** (après 1 vidéo dans la journée) : 2 vidéos = +5 messages
- **Tier 2** (après 3 vidéos dans la journée) : 3 vidéos = +5 messages
- **Anti-spam** : 30s minimum entre deux vidéos
- **Reset** : minuit local via `DateTime.now().day` comparison
- **Persistance** : `SharedPreferences` pour `ad_tier`, `ad_last_watched_timestamp`, `ad_videos_watched_today`

### Conséquences
- ✅ LTV augmenté : les utilisateurs engagés regardent plus de pubs
- ✅ Pas de frustration initiale : 1 vidéo au début reste facile
- ✅ Anti-gaming : 30s cooldown + reset minuit
- ⚠️ Complexité accrue par rapport à 1 vidéo fixe
- ⚠️ Nécessite `SharedPreferences` persistant

---

## ADR-020 : Services de Rétention (Streaks, Profil, Stats, Question du Jour)

**Date** : 2026-05-23
**Statut** : Accepté

### Contexte
Le taux de rétention D7/D30 est critique pour atteindre 1M+ utilisateurs. Actuellement, Corely n'a aucun mécanisme de gamification ou d'habitude quotidienne.

### Décision
4 services de rétention implémentés :

1. **StreakService** (`lib/features/retention/data/streak_service.dart`) :
   - Compteur de jours consécutifs d'ouverture de l'app
   - Bonus +2 messages gratuits après 3 jours de streak
   - Persistance `SharedPreferences` (`streak_count`, `streak_last_open_date`)

2. **UserProfileService** (`lib/features/retention/data/user_profile_service.dart`) :
   - Nom d'affichage et centres d'intérêt de l'utilisateur
   - Utilisés pour personnaliser le prompt système et les questions du jour

3. **UsageStatsService** (`lib/features/retention/data/usage_stats_service.dart`) :
   - Compteur de messages envoyés
   - Temps économisé estimé (hypothèse : 2 min/message vs recherche manuelle)
   - Affichage dans l'écran de profil

4. **DailyQuestionService** (`lib/features/retention/data/daily_question_service.dart`) :
   - Notification locale à 9h00 (fuseau local)
   - Question personnalisée basée sur les intérêts de l'utilisateur
   - Canal "Corely Daily" avec icône personnalisée

### Conséquences
- ✅ Rétention D7/D30 améliorée via habitude quotidienne
- ✅ Personnalisation accrue → engagement ↑
- ✅ Stats visibles → sentiment de valeur ↑
- ⚠️ Notifications locales nécessitent permission sur Android 13+
- ⚠️ Pas de backend Firebase pour la rétention (100% local pour l'instant)

---

*Dernière mise à jour : 2026-05-23*

## ADR-021 : Téléchargement Universel de Médias + Crawler Récursif (Session V17)

**Date** : 2026-05-24
**Statut** : Accepté

### Contexte
Les utilisateurs demandent fréquemment de télécharger des vidéos depuis YouTube et d'autres sites, ou de récupérer tous les médias d'une page web. Les commandes `/download` et `/links` ne supportaient que les fichiers directs (MP4, PDF). De plus, il n'existait aucun moyen de crawler récursivement un site pour en extraire les vidéos, images et liens.

### Décision
**Architecture backend-first avec yt-dlp + BFS crawler** :

1. **Backend `/download_media`** (`backend/agents/download_service.py`) :
   - **yt-dlp** pour 1000+ sites (YouTube, Vimeo, TikTok, Twitch, etc.) — extraction metadata + formats sans téléchargement binaire
   - **Page scraper fallback** pour sites sans yt-dlp : BeautifulSoup extrait `<video>`, `<iframe>`, `og:video`, JSON-LD `VideoObject`, `<img>`, CSS backgrounds
   - Paramètre `media_type` : `auto` (détecte), `video`, `image`, `audio`

2. **Backend `/crawl`** (`backend/agents/crawl_service.py`) :
   - **BFS** : queue `(url, depth)`, `max_depth` (1-5), `max_pages` (1-50)
   - **Same-domain filter** : optionnel, activé par défaut
   - **Extracts par page** : vidéos (5 extracteurs), images (3 extracteurs), liens
   - **Dédoublonnage global** par URL sur toutes les pages

3. **Flutter `SearchServiceGlobal`** :
   - `downloadMedia(url, mediaType)` → POST `/download_media` (30s timeout)
   - `crawl(url, maxDepth, maxPages)` → POST `/crawl` (45s timeout)
   - Appelé par `_handleSlashDownload()`, `_handleSlashLinks()` (fallback video), `_handleSlashCrawl()`

4. **Slash commands** :
   - `/download <url> [filename]` : appelle `downloadMedia()` si domaine vidéo (YouTube, Vimeo, etc.), sinon téléchargement direct
   - `/links <url> [filter]` : DOM local (extension) ou backend `/scrape`. Si `filter=video` et aucun lien, fallback `downloadMedia()`
   - `/crawl <url> [max_depth] [max_pages]` : nouveau, appelle `crawl()` et stocke les vidéos dans `_lastLinksForDownload` pour `/download` bulk

### Alternatives Considérées
- **Téléchargement côté client avec dio** : impossible sur web (CORS), impossible pour les sites protégés (YouTube blocks direct video URLs)
- **APIs tierces** (SaveFrom, Y2Mate) : instables, rate-limitées, pas de contrôle
- **Pas de yt-dlp** : uniquement BeautifulSoup → échoue sur les SPAs (YouTube)

### Conséquences
- ✅ Support de 1000+ sites via yt-dlp
- ✅ Crawler récursif type HTTrack pour archivage média
- ✅ Cross-platform (mobile + extension) grâce au backend
- ⚠️ yt-dlp peut être lent sur les chaînes YouTube (extraction complète de la playlist/chaîne)
- ⚠️ Dépendance au backend cloud pour les commandes universelles
- ⚠️ Pas de téléchargement binaire — seulement les URLs et metadata sont retournées (le client télécharge séparément)

## ADR-022 : Vocal V16 — Fix Cycle Tour-par-Tour + Slash Commands Mobile/Extension

**Date** : 2026-05-26
**Statut** : Accepté

### Contexte
Le mode vocal V16 (half-duplex tour-par-tour) avait une régression bloquante : après 1-2 échanges, le micro semblait écouter mais ne détectait plus rien. Par ailleurs, les commandes slash étaient disponibles sur mobile mais la plupart ne fonctionnaient pas (besoin du backend ou de l'extension Chrome).

### Décisions

**1. Fix vocal : `_conversationMode` ne doit pas être reset dans `stopListening()`**
- `VoiceServiceNotifier.stopListening()` mettait `_conversationMode = false`. Au redémarrage du micro après le TTS, `startListening()` utilisait alors `pauseFor: 5s` au lieu de `30min`. Après 5s de silence, le STT s'arrêtait et ne redémarrait pas.
- Fix : `stopListening()` ne touche plus à `_conversationMode`. La remise à zéro complète reste dans `setConversationMode(false)` appelé par `VoiceConversationNotifier.stop()`.
- Délai anti-écho augmenté de 400ms à 800ms : le STT Android (`SpeechRecognizer`) a besoin d'un temps de repos entre `stop()` et `listen()` pour éviter les états corrompus.

**2. Slash commands mobile : seule `/docgen` autorisée**
- La garde `!isExtension && parsed.command.name != 'docgen'` bloque toutes les autres commandes avec message explicite.
- `SlashCommands.mobileVisibleCommandNames = {'docgen'}` — la palette n'affiche que `/docgen` sur mobile.

**3. Extension slash commands : backend universel pour video/image**
- Suppression du regex `isVideoSite` (YouTube, Vimeo, TikTok, etc.) au profit d'une condition universelle : `filter == 'video' || filter == 'image'` → appel backend `downloadMedia` sur TOUS les sites.
- Le backend `download_service.py` est déjà universel : yt-dlp pour 1000+ sites + BeautifulSoup scraper pour tout le reste (`<video>`, `<iframe>`, `og:video`, JSON-LD, `<img>`, CSS backgrounds).
- `manifest.json` : ajout de `<all_urls>` dans `host_permissions` (nécessaire pour `chrome.scripting.executeScript`) + `dom_actions.js` dans `content_scripts` (évite l'injection dynamique qui échoue).

### Conséquences
- ✅ Mode vocal fiable à N tours sans blocage
- ✅ Mobile propre : seule `/docgen` visible et fonctionnelle
- ✅ Extension robuste : permissions correctes, scraper universel
- ⚠️ Dépendance au backend pour `/links video` et `/links image` (mais fallback DOM si backend down)

---

## ADR-019 : Design System Cofely — Source de Vérité Unique

**Date** : 2026-05-28
**Statut** : Accepté

### Contexte
Le projet avait deux identités visuelles en coexistence : l'ancien thème CorelIA (`#6C63FF` violet, `Icons.auto_awesome`) visible sur le login screen et l'onboarding, et le nouveau thème Cofely (`#003F5C` bleu foncé, logo "C") visible sur les écrans principaux (chat, settings). Les icônes Android et web étaient encore les icônes Flutter génériques.

### Décision
**Centralisation complète du design system dans `lib/app/cofely_theme.dart`** :
- `CofelyTokens` class avec constantes statiques : `primary`, `accent`, `onAccent`, `avatarGradient`, `userBubble`, `botBubble`
- `lightTheme` et `darkTheme` via `ThemeData` Material 3
- Zéro hardcoded `#6C63FF` dans le codebase

**Refonte login screen** : dégradé en-tête sombre + carte formulaire blanche arrondie — pattern "hero header + card" plus moderne que le formulaire centré à plat.

**Refonte onboarding** : gradients bleus Cofely (3 palettes : sombre/medium/accent). Page 1 avec logo "C" textuel dans cercle semi-transparent au lieu d'une icône Material générique.

**Génération icônes via Python PIL** :
- Script reproductible dans l'historique : `make_gradient_bg()` → `draw_c_on()` → masque rounded_rectangle ou ellipse
- Icônes maskable avec padding 10% safe zone (compatible Android adaptive icons)
- Les nouvelles icônes coexistent avec `mipmap-anydpi-v26/` (adaptive icon XML) — ne pas supprimer les XML adaptatifs si présents

### Règles de cohérence à respecter
- Toujours utiliser `CofelyTokens.primary` / `CofelyTokens.accent` — jamais de valeur hexadécimale hardcodée dans les widgets
- `DialogTheme` (PAS `DialogThemeData`) pour Material 3
- `Chip` n'a pas de paramètre `tooltip` en Flutter 3.x
- Import chemin relatif : `'../../../app/cofely_theme.dart'` (ajuster selon profondeur)

### Alternatives Considérées
- `ThemeExtension` Flutter (plus flexible mais complexité accrue)
- Constantes inline dans chaque widget (anti-pattern, maintenance impossible)
- Package de design system externe (sur-ingénierie pour ce projet)

### Conséquences
- ✅ Cohérence visuelle totale sur tous les écrans (login, onboarding, chat, settings, vocal)
- ✅ Icônes launcher Android et favicon web en cohérence avec l'identité Cofely
- ✅ Un seul endroit pour modifier les couleurs brand
- ⚠️ Script Python de génération d'icônes non versionné (à extraire dans `scripts/`)

---

*Dernière mise à jour : 2026-05-28*
