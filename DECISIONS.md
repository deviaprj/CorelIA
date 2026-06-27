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

## ADR-023 : Infrastructure Cloud — Hetzner VPS + Caddy Reverse Proxy

**Date** : 2026-06-13
**Statut** : Accepté

### Contexte
Le backend FastAPI et les services associés (CodeWhale Agent, Ollama, Open WebUI) nécessitaient un hébergement cloud stable. Le Cloudflare Worker précédent était un proxy limité ; il fallait un serveur dédié pour le scraping, les scripts IA et les services stateful (Redis, Ollama).

### Décision
Déploiement sur **Hetzner VPS** (`167.233.100.132`) avec stack Docker Compose :
- **Caddy** : Reverse proxy + TLS automatique (Let's Encrypt)
- **Backend FastAPI** (`api.zentic.fr`) : Python 3.12, uvicorn 4 workers, Redis rate limiting
- **CodeWhale Agent** (`agent.zentic.fr`) : Microservice FastAPI autonome avec tool calling
- **Redis** : Cache + rate limiting LRU
- **Ollama** : LLM local (Mistral, Llama, etc.) — GPU optionnel
- **Open WebUI** (`chat.zentic.fr`) : Interface chat multi-LLM (profil `full`)
- **ttyd** (`terminal.zentic.fr`) : Terminal web avec Claude Code + Codewhale + tmux
- **Watchtower** : Auto-update containers (profil `full`)

### Sécurité
- Clés API via `.env` monté en read-only dans les conteneurs
- TTYD authentification basique via variables d'environnement (jamais en dur dans Dockerfile)
- Healthchecks Python natifs (pas de `curl` dans `python:3.12-slim`)
- Dépendances optionnelles non bloquantes (Ollama non requis pour l'agent)

### Conséquences
- ✅ Backend cloud stable et scalable
- ✅ Terminal web accessible depuis n'importe où
- ✅ Scraping côté serveur (pas de CORS client)
- ⚠️ Maintenance ops requise (updates système, certificats)
- ⚠️ Coûts serveur mensuels (Hetzner VPS ~24€/mois)

---

## ADR-024 : CodeWhale Agent — Microservice Autonome avec Tool Calling

**Date** : 2026-06-13
**Statut** : Accepté

### Contexte
Besoin d'un agent IA capable d'exécuter des tâches complexes (analyse de code, refactoring, recherche web) de manière autonome dans un environnement isolé. L'agent doit être accessible via API REST et compatible avec le backend CorelIA.

### Décision
Microservice **CodeWhale Agent** dans `codewhale-agent/` :
- FastAPI avec endpoints `/agent/run`, `/agent/status/{id}`, `/agent/result/{id}`, `/agent/stream/{id}`
- Stockage in-memory des tâches (TaskStore) avec events SSE
- Tool calling OpenAI/DeepSeek format : `read_file`, `write_file`, `list_directory`, `run_command`, `search_web`, `git_diff`, `git_log`, `task_complete`
- Sandbox : path traversal protection, timeout 60s sur les commandes shell
- Workspace isolé dans `/workspace`

### Alternatives Considérées
- Exécution directe dans le backend FastAPI (trop monolithique, pas isolé)
- GitHub Actions (pas temps réel, pas de persistance workspace)
- AutoGen/CrewAI (trop lourds, pas de contrôle fin des outils)

### Conséquences
- ✅ Tâches longues asynchrones sans bloquer le backend
- ✅ Tool calling extensible (ajouter des outils = modifier une liste)
- ✅ Workspace persistant entre les appels
- ⚠️ Stockage in-memory uniquement (pas de Redis/DB pour les tâches)
- ⚠️ Pas d'authentification sur l'agent (à ajouter via API key)

---

## ADR-025 : Audit 2026-06-16 — Tier-aware Oralize/TTS, fail-safe defaults, routage vocal restauré, fallback vision-aware, durcissement ttyd + whitelist extension

### Contexte
Audit chirurgical post-déploiement (reprise de session) a révélé 7 défauts de
logique/coût/sécurité où le code divergeait des intentions documentées :

1. **Routage vocal mort** (`model_router.dart`) : `task:vocal` et `task:vocalFast`
   n'avaient pas de mapping dans `resolveModel()` → `voice_conversation_service.dart`
   passait `modelOverride:'task:vocal'` qui était silencieusement ignoré. Le mode
   vocal routait via la chaîne générale (deepseek-v4-flash) au lieu des modèles
   joviaux (arcee/trinity, neversleep/ring-2.6-1t) conçus pour la conversation.
2. **Oralize Pass non tier-aware** (`oralize_service.dart`) : `oralize()` n'avait
   pas de paramètre `isPro` → tous les utilisateurs (gratuits inclus) déclenchaient
   un appel LLM DeepSeek Flash (~$0.00003/appel) facturé à l'opérateur, sans revenu
   sur le gratuit. De plus timeout bloquant à 8s (trop long en half-duplex vocal).
3. **Défaut `isPro` fail-unsafe** (`tts_natural_service.dart`) : `speakNaturally(
   {bool isPro = true})` — défaut au chemin payant. Un appelant oubliant `isPro`
   déclenchait OpenRouter TTS (facturation opérateur) au lieu du flutter_tts gratuit.
4. **Fallback vision non-vision-aware** (`model_router.dart`) : le dernier recours
   `_registry['deepseek-v4-pro']` était retourné même pour `TaskType.vision`, alors
   que `deepseek-v4-pro` n'a PAS `supportsVision` → image envoyée à un modèle
   non-vision → réponse garbage. Le code propre (`throw AiException`) était mort.
5. **ttyd mot de passe `changeme` en prod** (`Dockerfile` + `docker-compose.yml`) :
   `ENV TTYD_PASS=changeme` en dur dans le Dockerfile, et le service `terminal`
   du compose ne surchargeait PAS `TTYD_PASS` → le conteneur tournait avec le
   défaut `changeme` en production. TASKS.md prétendait le contraire (drift doc).
6. **Fuite de secrets serveur dans l'extension** (`build_extension.sh`) : le script
   dumpait TOUT `.env` via `--dart-define`, y compris `OPENROUTER_API_KEY`
   (clé opérateur payante), `API_SECRET_KEY`, `SERPAPI_API_KEY`, `STRIPE_WEBHOOK_SECRET`
   dans le ZIP public du Chrome Web Store — extraction triviale.

### Décision
Corrections production-ready, une fonction = une chose bien faite :

- **Routage vocal restauré** : ajout des mappings `task:vocal`/`task:vocalFast` →
  `TaskType.vocal`/`vocalFast`. Les modèles payants de la chaîne (gpt-4o-mini)
  restent filtrés pour les gratuits via le gate `isPro` existant.
- **Oralize tier-aware** : `oralize(text, {bool isPro = false})` — `!isPro`
  court-circuite l'appel LLM (retourne markdown brut, `cleanMarkdown` fait le
  reste). Timeout 8s → 4s (ne bloque pas le tour vocal). Cache corrigé FIFO → LRU
  (touch sur hit).
- **`isPro` fail-safe partout** : `speakNaturally({bool isPro = false})` + garde-fou
  defense-in-depth `OpenRouterTtsService.synthesize({bool isPro = false})` qui
  retourne `null` si `!isPro` (empêche tout futur appel direct de facturer).
  Threading `isPro` à travers `_speakWithOpenRouterTts` (`{required bool isPro}`).
- **Fallback vision-aware** : `resolveModel` retourne `null` pour `TaskType.vision`
  si le dernier recours n'est pas vision-capable → `_getVisionStream` déclenche
  le `throw AiException('Analyse d'image indisponible…')` (code maintenant vivant).
- **ttyd fail-closed** : retrait du `ENV TTYD_PASS=changeme` du Dockerfile ;
  `start-ttyd.sh` refuse de démarrer (exit 1) si `TTYD_PASS` est vide ou
  `"changeme"` ; `docker-compose.yml` thread `TTYD_PASS=${TTYD_PASS:?…}` (compose
  refuse de démarrer si absent/ vide). Defense-in-depth sur 3 couches.
- **Whitelist extension** : `build_extension.sh` n'embarque que les clés
  client-safe (`DEEPSEEK_API_KEY`, `ADMOB_*`, `REVENUECAT_*`, `APP_ENV`). Les
  secrets serveur sont explicitement ignorés (echo de traçabilité). `OPENROUTER_API_KEY`
  est exclu : l'extension est toujours en mode DEMO (`isProProvider` → false), donc
  OpenRouter n'y est jamais appelé — la clé n'est pas nécessaire côté extension.

### Alternatives Considérées
- *Patcher le routage vocal avec un 3e if* : non, c'était un mapping manquant, pas
  un bug de logique — ajout simple et définitif.
- *Garder Oralize pour tous (coût négligeable)* : rejeté — $0.00003 × volume gratuit
  × 1M+ users cible = non-négligeable sur le long terme, et aucun revenu associé.
- *Thread isPro seulement à speakNaturally (pas de garde dans synthesize)* : rejeté,
  defense-in-depth — un futur appelant direct de `synthesize` ne doit pas facturer.
- *Whitelist sans exclure OPENROUTER_API_KEY* : rejeté, contradiction avec CLAUDE.md
  résolue par constat que l'extension est toujours DEMO/`isPro=false`.

### Conséquences
- ✅ Mode vocal utilise enfin les modèles joviaux (conformité avec la doc V16).
- ✅ Coût opérateur : $0 pour les utilisateurs gratuits (Oralize + TTS). Pro
  inchangé (accès complet OpenRouter + Oralize LLM + TTS OpenRouter).
- ✅ Vision : erreur propre et explicite au lieu de réponse garbage quand tous les
  modèles vision sont en cooldown/indisponibles pour un utilisateur gratuit.
- ✅ ttyd : ne peut plus démarrer avec un mot de passe faible (fail-closed sur 3
  couches). L'opérateur DOIT définir `TTYD_PASS` dans `.env` (action VPS manuelle
  restante : rebuild + redémarrer le conteneur, changer le mot de passe existant).
- ✅ Extension : plus aucune fuite de clé opérateur payante dans le ZIP public.
- ⚠️ Non résolu (hors scope autonome, signalé à l'utilisateur) : rotation des clés
  Firebase + git filter-repo, auth CodeWhale Agent, endpoints backend non authentifiés
  + SSRF + sandbox script, signature debug APK release, Stripe webhook rawBody.
  (Note : la signature release APK est désormais résolue par ADR-026 — garde-fou
  fail-fast dans build.gradle.)
- ⚠️ Analyseur Dart non exécutable dans l'environnement local (binaires SDK sans
  permission d'exécution) — vérification par traçage exhaustif des appelants à la
  place. Tous les paramètres ajoutés sont optionnels avec défaut, sauf
  `{required bool isPro}` sur `_speakWithOpenRouterTts` dont l'unique appelant a été
  mis à jour.

---

## ADR-026 : Bloc 0 (2026-06-16) — Quick wins P0 release : paywall barrel, route Projets, prefs LWW, signature release fail-fast, alignement version

### Contexte
Suite à l'audit Phase 1 (score 5.5/10), exécution autonome du Bloc 0 — correctifs
mécaniques et architecturaux rapides bloquant la release bêta. 6 problèmes où le
code divergeait de la spec ou cassait silencieusement :

1. **Paywall mobile mort** : `router.dart` importait `paywall_screen.dart` qui était
   en réalité l'implémentation web (message "abonnements disponibles sur l'app
   mobile") sur TOUTES les plateformes. Le paywall RevenueCat mobile
   (`paywall_screen_mobile.dart`) était dead code → monétisation Pro mobile
   inopérante, l'utilisateur mobile voyait un message absurde l'invitant à aller sur
   mobile.
2. **Route Projets cassée + collection fantôme** : `_openProject` naviguait vers
   `/projects/{id}` mais aucune route GoRouter n'existait → navigation morte. De plus,
   `projectConversationsProvider` interrogeait `projects/{projectId}/conversations`
   (top-level) qui n'existe JAMAIS (les projets sont sous `users/{uid}/projects/{id}`)
   → query toujours vide. Lien projet↔conversation non implémenté côté UI.
3. **Prefs sync inerte** : `PreferencesSyncService.mergeWithLocal` n'était JAMAIS
   appelé (listener vide dans `main.dart`) + la logique LWW était absente (pas de
   comparaison de timestamp). Synchronisation multi-appareils des préférences morte.
4. **APK release signé en debug** : `build.gradle` signait le release avec la clé
   debug → rejet Play Store + clé extractable. (Item alors listé "non résolu" dans
   ADR-025 — résolu ici.)
5. **Drift version** : `pubspec.yaml` 1.0.0+1 mais `constants.dart.appVersion` = 1.1.0
   et l'UI affiche "v1.1.0" → versionName APK discordant.
6. **Bugs mécaniques d'interpolation** : `\$` dans des strings Dart normaux →
   `'ImageUploadException: $message'` littéral au lieu de la valeur (image_upload
   io+web) ; `streak_service.dart` `$data.streak` interpolait l'objet StreakData
   (toString = "Instance of...") ; `api_load_test.dart` `static int get pid => pid`
   récursion infinie → StackOverflowError ; URLs Stripe test hardcodées dans
   paywall_mobile ; noms de collections hardcodés dans projects_screen ; `.env.example`
   manquait SERPAPI/OPENWEATHERMAP que `constants.dart` lisait déjà.

### Décision
Corrections production-ready, une fonction = une chose bien faite :

- **Paywall barrel conditional import** : `paywall_screen.dart` devient un barrel
  `export 'paywall_screen_mobile.dart' if (dart.library.html) 'paywall_screen_web.dart'`.
  Mobile (dart:io) → RevenueCat + fallback Stripe ; web/extension (dart:html) → Stripe
  checkout. Le router importe le barrel, la sélection se fait à la compilation.
  `paywall_screen_web.dart` recréé en screen Stripe checkout réel (bouton →
  `AppConstants.stripeCheckoutMonthlyUrl` avec fallback `${appWebUrl}/checkout?plan=`).
- **Route Projets + ProjectDetailScreen** : ajout route GoRouter `/projects/:id`.
  Nouvel écran `project_detail_screen.dart` avec `projectDocProvider` +
  `projectConversationsStreamProvider` (`StreamProvider.family` paramétré par
  `ProjectKey` — value type immutable `@immutable` avec `==`/`hashCode` via
  `Object.hash`). **Lien canonique projet↔conversation via `Conversation.projectId`**
  (query top-level `conversations` where `userId == uid AND projectId == projectId`)
  — PAS via le `Project.conversationIds` redondant (source de vérité unique, pas de
  double écriture à synchroniser). Provider cassé supprimé.
- **Prefs sync LWW corrigé** : `mergeWithLocal` réécrit en last-write-wins document-level
  (compare `remote.updatedAt` vs `prefs_local_updated_at`). Leaf file
  `local_pref_timestamp.dart` (unique dépendance shared_preferences) pour éviter
  l'import circulaire (PreferencesSyncService → main.dart → app_providers).
  `markUpdated()` câblé dans les 3 setters locaux (setTheme, setSpeed,
  SystemPromptNotifier.save/reset). Listener `main.dart` appelle enfin `mergeWithLocal`
  sur changement remote.
- **Scope-down délibéré (prefs sync)** : auto-push local→remote + reload provider en
  mémoire différés post-bêta (gap documenté dans le docstring de `mergeWithLocal`).
  Évite d'introduire une demi-feature propice aux boucles de feedback dans un chemin
  bêta — respecte "zéro patch aveugle" et "signaler les blocages".
- **Signature release fail-fast** : `build.gradle` lit `key.properties` ;
  `signingConfigs.release` utilisé par `buildTypes.release` ; garde-fou
  `tasks.matching{ it.name ==~ /assemble.*Release|bundle.*Release/ }` lance une
  `GradleException` si le keystore est absent — échoue vite au lieu de signer
  silencieusement en debug. `android/key.properties.example` documente le format
  (gitignored `key.properties`/`*.keystore`).
- **Alignement version** : pubspec 1.0.0+1 → 1.1.0+1 (concorde `constants.dart`/UI).
- **Centralisation constants** : URLs Stripe checkout (`stripeCheckoutMonthlyUrl`/
  `stripeCheckoutYearlyUrl` via `_env` + fallback debug), noms de collections
  (`colUsers`/`colConversations`/`colMessages`/`colProjects`/`colReferrals`) —
  projects_screen migré 100% vers AppConstants (0 collection hardcodée restante).
  `.env.example` +SERPAPI_API_KEY/OPENWEATHERMAP_API_KEY.
- **Bugs mécaniques** : `\$`→`$` (image_upload io+web : toString, debugPrint, throw),
  streak `${data.streak}` + accent "Série", `api_load_test` pid → `io.pid` top-level
  (comment documentant l'ancien bug).

### Alternatives Considérées
- *Lien projet↔conversation via `Project.conversationIds`* : rejeté, double source de
  vérité → risque de désynchronisation (ajout conversation = update projet aussi).
  Query sur `Conversation.projectId` = source unique, idempotente, pas de migration
  de données (le champ existait déjà).
- *Prefs sync : implémenter auto-push + live-reload maintenant* : rejeté pour bêta,
  demi-feature propice aux boucles de feedback (push déclenche merge déclenche push).
  Préféré : corriger le LWW flaggé correctement + wirings, documenter le gap,
  terminer la feature complète post-bêta avec garde anti-boucle.
- *Keystore : laisser debug-sign en silence avec warning* : rejeté, rejet Play Store
  silencieux + clé extractable = faille de sécurité. Fail-fast préférable (échec
  build > build livré cassé).
- *projectConversationsProvider : patcher la query* : rejeté, la collection interrogée
  n'existait pas → suppression + réimplémentation canonique via `projectId`.
- *Garder les URLs Stripe test hardcodées* : rejeté, drift env (URLs de prod différentes
  des URLs test) → centralisation dans `AppConstants` avec fallback debug.

### Conséquences
- ✅ Monétisation Pro mobile fonctionne (RevenueCat paywall enfin utilisé sur mobile,
  avant dead code).
- ✅ Navigation Projets→détail→conversations fonctionnelle (route + écran + lien
  canonique via `projectId`).
- ✅ Préférences : merge remote→local LWW opérationnel + timestamps wirés. Auto-push
  et live-reload = gap connu post-bêta (documenté dans le docstring).
- ✅ APK release signé correctement ou échoue vite (jamais debug-signé
  silencieusement) — supersedes l'item "non résolu" d'ADR-025.
- ✅ Version pubspec = constants = UI (1.1.0 cohérent).
- ✅ 0 collection hardcodée dans projects_screen (tout via AppConstants).
- ✅ Bugs d'interpolation résolus (messages d'erreur/logging affichent enfin les
  valeurs au lieu de template strings littéraux).
- ⚠️ Actions manuelles restantes (hors scope autonome) : créer le keystore via
  `keytool` + upload Play Store ; rotation clés Firebase + git filter-repo (signalé
  ADR-025) ; ttyd VPS rebuild (signalé ADR-025).
- ⚠️ Analyseur Dart non exécutable dans l'environnement local (binaires SDK 644 sans
  permission d'exécution) — vérification par traçage statique + grep. Recommandation :
  exécuter `flutter analyze` + `flutter test` en local avant release.

---

## ADR-027 : Bloc 1 (2026-06-16) — Sécurité backend P0 : auth two-tier, SSRF net_guard, sandbox AST, conteneurs non-root, durcissement compose, fuite .env APK

**Date** : 2026-06-16
**Statut** : Accepté

### Contexte
L'audit Phase 1 (score 5.5/10) avait classé la sécurité backend en priorité P0. Le
backend cloud (`api.zentic.fr`) est un *bonus, pas une dépendance* (CLAUDE.md) — mais
puisqu'il est exposé à internet, toute faille est exploitable par quiconque. 10
problèmes où le code divergeait des intentions sécuritaires :

1. **RCE non authentifié** : `/script/exec` exécutait un script Python généré par LLM
   sans aucune authentification → quiconque peut exécuter du code arbitraire sur le VPS.
   `/config/diagnose`+`/migrate` et `/agent/execute`+`/status`+`/result` idem (subprocess,
   RCE-adjacent). `/insights/audit` exposait le journal d'audit sans gate.
2. **SSRF ouvert** : `scrape_url`, `_scrape_page`, `_extract_page_media`, `crawl`,
   `_fetch_and_parse` utilisaient `httpx` avec `follow_redirects=True` et aucune
   validation d'URL → un attaquant peut faire fetcher `http://169.254.169.254/...`
   (cloud-metadata), `http://localhost:port-internal`, ou suivre des redirects vers
   l'espace privé.
3. **Sandbox script IA absente** : `script_executor.py` faisait `exec()` du code généré
   par DeepSeek dans le process du backend, avec l'environnement complet (clés API
   héritées) → prompt injection = exfiltration des clés + RCE dans le contexte backend.
4. **Injection shell** : `config_agent.py` construisait des commandes shell via f-string
   avec entrée utilisateur (domaine) → injection de commandes possible.
5. **Conteneurs root** : backend + codewhale tournaient en root → blast radius maximal si
   échappement (sandbox, prompt injection).
6. **docker.sock monté** : codewhale montait `/var/run/docker.sock` → accès root-equivalent
   au host (spawn d'un conteneur privilégié = root host).
7. **Port Ollama publié** : `11434:11434` exposait un endpoint LLM non authentifié à
   internet → quiconque peut faire inférence aux frais de l'opérateur.
8. **CORS invalide** : `allow_origins=["*"]` + `allow_credentials=True` est rejeté par les
   navigateurs et, si accepté, autorise tout site à appeler l'API avec credentials.
9. **Fuite .env dans l'APK** : `pubspec.yaml` déclarait `.env` comme asset → tout `.env`
   (`API_SECRET_KEY` opérateur, `OPENROUTER_API_KEY` payant, `STRIPE_WEBHOOK_SECRET`)
   était empaqueté dans l'APK et extractible (unzip + read).
10. **Secret opérateur commité** : `scripts/server_init.sh` contenait en dur
    `API_SECRET_KEY=311788a1…` (valeur réelle de 32 octets) dans le repo.

### Décision
Durcissement production-ready en couches (defense-in-depth), une fonction = une chose :

- **Auth two-tier** (`backend/core/auth.py`, `config.py`) :
  - `CLIENT_API_KEY` — *soft gate*. Embarquée dans l'APK via `--dart-define`
    (`AppConstants.backendApiKey`), extractable par conception (même classe de risque
    que `DEEPSEEK_API_KEY`). Header `X-API-Key` (ou `?api_key=`). **Transition-open** :
    si vide, les routes restent ouvertes pendant le rollout (pas de cassage).
  - `API_SECRET_KEY` — *opérateur, fail-closed*. Server-side uniquement, JAMAIS dans
    l'APK/extension. Si vide → 403 (défaut sûr). Gates RCE/admin.
  - Comparaison **constant-time** `hmac.compare_digest` (anti-timing).
  - `/chat/completions` = Firebase JWT (`verify_firebase_token`), indépendant des deux
    clés (le chat reste auth-par-utilisateur, pas par clé partagée).
  - Gating par `Depends()` :
    - `require_client_api_key` : `/scrape`, `/search_smart`, `/download_media`,
      `/crawl`, `/script/scrape`, `/script/api-fetch`, `/insights/ingest|trends|demographics`.
    - `require_operator_key` : `/script/exec`, `/config/diagnose|migrate`,
      `/agent/execute|status|result`, `/insights/audit`.
    - Public (read-only metadata) : `/health`, `/skills`, `/agent/health`, `/config/health`.
- **SSRF** (`backend/core/net_guard.py` — nouveau module) :
  - `assert_safe_url(url)` : scheme allow-list `{http,https}`, blocklist
    `{localhost, ip6-*, metadata.google.internal}`, rejet IP privée via
    `ip_address.is_private/is_loopback/is_link_local/is_reserved/is_multicast/is_unspecified`
    **incluant `169.254.169.254`** (cloud-metadata).
  - `safe_get`/`safe_get_sync` : `follow_redirects=False` per-request + re-validation de
    chaque hop `Location` via `urljoin`+`assert_safe_url`, max 4 redirects.
  - Câblé sur les 4 sites de fetch (`search_engine`, `search_smart`, `download_service`,
    `crawl_service`) + pre-check `assert_safe_url` dans `script_executor`
    (`scrape_with_script`, `api_fetch_with_script`) et `crawl` (seed + per-link).
- **Sandbox scripts IA** (`backend/agents/script_executor.py` — réécrit) :
  - `_ScriptValidator(ast.NodeVisitor)` walk `Import`/`ImportFrom`/`Call`/`Attribute`/
    `Name` contre `_ALLOWED_MODULES` / `_DANGEROUS_NAMES` / `_DANGEROUS_ATTRS`.
  - `_SANDBOX_ENV` minimal (pas de clés API héritées du process backend).
  - `tempfile.TemporaryDirectory` comme cwd (pas d'accès FS arbitraire).
  - Timeout 15s. `exec()` dans le sandbox, pas dans le process principal.
- **config_agent shell-injection fix** : `asyncio.create_subprocess_exec` (forme argv,
  pas de shell) + `_validate_domain` strict (regex hostname). Plus aucun f-string dans une
  commande shell.
- **Conteneurs non-root** (`Dockerfile` ×2) : `USER app` (uid 10001 backend),
  `USER agent` (uid 10002 codewhale), `chown -R` `/workspace`/`/app` (le named volume
  `codewhale-workspace` hérite l'ownership `agent`, sinon root → agent ne peut écrire).
- **docker-compose** :
  - `docker.sock` **retiré** de codewhale (escalade root-equivalent ; codewhale n'orchestre
    plus de conteneurs siblings — si besoin futur, passer par un proxy étroitement scopé).
  - Port Ollama 11434 **non publié** (interne au bridge `corelia-net` uniquement).
  - `CORS_ORIGINS` threadé (prod serré) ; `allow_credentials = not _is_wildcard_origin`
    (corrige le combo invalide wildcard+credentials).
  - `CLIENT_API_KEY` + `API_SECRET_KEY` ajoutés à l'env backend (via `.env` VPS).
- **Wiring client Flutter** :
  - `AppConstants.backendApiKey` (lit `CLIENT_API_KEY` via `--dart-define`) → header
    `X-API-Key` sur `SearchServiceGlobal`, `ScriptExecutionService`, `WorkerChatClient`
    (Dio `BaseOptions.headers`).
  - `WorkerChatClient` migré de `Authorization: Bearer $_apiSecretKey` (clé opérateur —
    ne devait jamais être client-side) vers `X-API-Key: $_apiKey` (soft). Documenté
    legacy (la route active `/chat/completions` est Firebase-JWT, pas ce client).
  - `chat_notifier.dart` : message "Backend non configuré" corrigé `API_SECRET_KEY` →
    `CLIENT_API_KEY` (+ mention `--dart-define`).
  - `script_execution_service.dart` : 401/403 de `/script/exec` → message clair
    "réservé à l'opérateur" au lieu d'un 401 brut.
- **Fuite .env APK** : `.env` retiré des `assets` `pubspec.yaml`. Clés client via
  `--dart-define` uniquement (aligné sur l'approche extension). `main.dart` gardait déjà
  `dotenv.load` en try/catch → asset absent = non-fatal, `_env()` retombe sur
  `--dart-define`. Comment explicite dans le catch.
- **Secret commité retiré** : `scripts/server_init.sh` ne contient plus la valeur réelle
  `311788a1…`. Remplacée par placeholders `__GENERATE_*__` injectés post-heredoc via
  `openssl rand -hex 32` (fallback `/dev/urandom`) — chaque déploiement frais obtient une
  clé forte unique. `.env.example` documente la séparation client (CLIENT_API_KEY) vs
  VPS-only (API_SECRET_KEY).

### Alternatives Considérées
- *Secret partagé unique (garder API_SECRET_KEY côté client)* : rejeté — aucune
  séparation entre soft gate (routes APK) et opérateur (RCE). Two-tier obligatoire.
- *Allowlist IP pour `/script/exec` au lieu d'une clé* : rejeté — IPs mobiles dynamiques,
  non gérables. Une clé opérateur (jamais client-side) est la primitive correcte.
- *Garder .env comme asset + filtrer les clés serveur au build* : rejeté — convention non
  enforceable (un dev ajoute une clé serveur au .env → fuite). Retrait de l'asset = garantie.
- *Whitelist `CLIENT_API_KEY` dans `build_extension.sh`* : rejeté — l'extension n'embarque
  pas `BACKEND_URL` (autonomie CLAUDE.md) → n'appelle jamais le backend → embarquer une clé
  douce inutilisée serait une fuite sans bénéfice. Documenté dans le script.
- *Docker socket proxy au lieu de retirer le socket* : rejeté — codewhale n'a pas besoin
  d'orchestrer des siblings ; retrait total > proxy à maintenir.
- *Garder `follow_redirects=True` + blocklist seulement sur l'URL initiale* : rejeté — un
  redirect 302 vers `http://169.254.169.254` contourne. Re-validation per-hop obligatoire.

### Conséquences
- ✅ RCE backend fermé : `/script/exec`, `/config/*`, `/agent/*` nécessitent la clé
  opérateur (fail-closed). `/script/scrape`+`/api-fetch` (constrained à une URL + sandbox)
  restent accessibles via la clé douce.
- ✅ SSRF fermé : cloud-metadata, loopback, privé inatteignables même via redirects.
- ✅ Sandbox : un script IA malveillant ne peut ni exfiltrer les clés (env minimal), ni
  sortir du temp dir, ni dépasser 15s, ni importer des modules dangereux.
- ✅ Injection shell config_agent éliminée (argv, domaine validé).
- ✅ Blast radius conteneur : non-root, pas de docker.sock, pas de port LLM exposé.
- ✅ CORS valide (credentials uniquement sur origins explicites).
- ✅ APK n'embarque plus `.env` → clé opérateur + clé payante + Stripe webhook ne fuient plus.
- ⚠️ **Changement de comportement (cassable)** : `/script/exec` n'est plus joignable depuis
  l'APK. Le client affiche un message clair ("réservé à l'opérateur"). `/scrape-script` et
  `/api-fetch` (cas d'usage APK légitimes) restent disponibles. Documenté côté client.
- ⚠️ **Dev workflow change** : `flutter run`/build mobile doit passer les clés via
  `--dart-define` (BACKEND_URL, CLIENT_API_KEY, DEEPSEEK_API_KEY, …). `.env` n'est plus
  auto-chargé depuis l'asset bundle. Convention déjà en place côté extension.
- ⚠️ **Actions VPS manuelles (hors scope autonome, signalées)** :
  1. **Rotation `API_SECRET_KEY`** : la valeur `311788a1…` était live. Si encore dans le
     `.env` VPS, la tourner + `docker compose up -d --force-recreate backend
     codewhale-agent`. Git history la contient encore → `git filter-repo` si purge.
  2. Définir un `CLIENT_API_KEY` fort dans le `.env` VPS (server_init.sh le génère pour
     les nouveaux deploys ; un deploy existant doit l'ajouter manuellement) puis le
     passer en `--dart-define` côté APK build.
- ⚠️ Analyseur Dart non exécutable ici (binaires SDK 644) — vérification par traçage
  statique exhaustif : 0 `_apiSecretKey` restant, `backendApiKey` câblé sur les 3 clients,
  header `X-API-Key` = header lu côté backend (`auth.py:91`), 0 `- .env` dans pubspec,
  0 valeur `311788a1…` dans le repo. `flutter analyze`/`test` à lancer en local.

---

## ADR-028 : Bloc 2 (2026-06-16) — Robustesse vocale : machine à états à token de génération

**Statut** : Accepté · **Date** : 2026-06-16 · **Bloc** : 2 (Robustesse vocale)

### Contexte
La `VoiceConversationNotifier` (machine à états half-duplex tour-par-tour :
`listening → thinking → speaking → listening`) présentait 5 races/bugs de robustesse
identifiés à l'audit Phase 1 :

1. **Barge-in « repeat » cassé** : `_handleBargeInDuringSpeaking` appelait
   `_speakFullResponse(lastAssistant.content)` pendant que le `_speakFullResponse`
   d'origine était encore en vol (`_isProcessingResponse == true`, `state == speaking`).
   Le garde `_isProcessingResponse && state.state == speaking` (ligne 232) **skip
   silencieusement** → la répétition ne se faisait jamais. Pire, le `_speakFullResponse`
   d'origine, « réveillé » par `stopSpeaking()`, continuait son flux et **rouvrait le micro +
   écrasait l'état** après son délai 1200ms, race contre le nouveau tour.
2. **Pas de token d'annulation de tour** : les continuations async (réouverture micro
   post-TTS, délai 1200ms) pouvaient se déclencher sur un tour obsolète (supplanté par un
   barge-in ou un stop) et corrompre l'état du tour courant.
3. **`_lastProcessedTime!` forcé-unwrapped** (ligne 149) — crash potentiel si l'invariant
   `_lastProcessedTranscript` ↔ `_lastProcessedTime` venait à se rompre.
4. **Pas de reset systématique** : `stop()`/`startConversation()` ne clearaient pas
   `_isProcessingResponse`, `_lastProcessedTranscript`, `_lastRequestTime`, etc. → des
   drapeaux stale survivaient d'une session à l'autre (Notifier family persistant) et
   pouvaient bloquer `_handleChatState` indéfiniment.
5. **Pas de sync d'erreur STT** : la spec CLAUDE.md dit « Max 3 échecs STT consécutifs →
   état error » mais ce n'était **pas implémenté**. `voice_service.dart` `onError` ne
   faisait que `state = isListening=false` ; la conversation n'en était jamais informée →
   la machine se bloquait en `listening` (isListening=false mais VoiceConversationState
   toujours listening) sur un micro instable, sans récupération ni borne.

Bonus — **bug sémantique latent** découvert en réécrivant le switch barge-in :
6. **`BargeInIntent.stop` mal routé** : le classifieur définit `stop` comme « Demande d'arrêt
   immédiat » (patterns `stop|chut|tais-toi|arrête|pause|silence|coupe|terminé|fini|ça
   suffit`), mais le code routait `stop` → `_sendToLLM(transcript)`. Résultat : l'utilisateur
   disant « chut »/« arrête » pour faire taire l'assistant envoyait le mot « chut » au LLM
   et déclenchait une **nouvelle réponse** — l'utilisateur voulait du silence, obtenait le
   contraire.

### Décision
Réécriture propre de `voice_conversation_service.dart` (situation ≥3 correctifs → clean
rewrite, per règle Mission B) + ajouts ciblés à `voice_service.dart`.

1. **Token de génération** (`_generation`, int incrémenté à chaque frontière de tour) :
   chaque continuation async de `_speakFullResponse` capture `gen = _generation` au départ
   et **bail si `gen != _generation`** (tour supplanté). Le micro n'est rouvert, l'état
   n'est écrasé, que par le tour courant. Idiomatique Dart, zéro dépendance externe.
2. **`_resetTurnState()`** : bump `_generation` + clear de tous les drapeaux stale
   (`_isProcessingResponse`, `_lastProcessedTranscript`, `_lastProcessedTime`,
   `_lastBargeInTranscript`, `_lastRequestTime`, `_sttFailureCount`). Appelé à chaque
   frontière : `startConversation`, `stop`, `ref.onDispose`. Anti-pollution inter-sessions.
3. **Garde `_isProcessingResponse` lié à la génération** : posé avec `gen` capturé dans
   `_handleChatState`, libéré dans `whenComplete` **seulement si** `_generation == gen`
   (le tour qui l'a posé le libère ; un barge-in/stop obsolète ne le retouche pas). Empêche
   le double-déclenchement pendant la fenêtre thinking→speaking sans risque de libération
   intempestive par un tour supplanté.
4. **Barge-in fixé** : `_handleBargeInDuringSpeaking` bump `_generation` + libère
   `_isProcessingResponse` + `stopSpeaking()` avant de dispatcher. Le `_speakFullResponse`
   d'origine bail via le check de génération → ne rouvre pas le micro. `repeat` appelle
   `_respeakLastAssistant()` qui re-parle le dernier message assistant (la génération
   étant bumpée et le garde libéré, `_speakFullResponse` procède — fin du skip silencieux).
5. **`_lastProcessedTime` null-check** : `if (transcript == _lastProcessedTranscript &&
   _lastProcessedTime != null)` avant `difference(_lastProcessedTime!)`. Plus de crash
   potentiel.
6. **Sync erreur STT** : nouveau `StreamController<String> _sttErrorController` +
   `onSttError` dans `voice_service.dart`, émis depuis `onError` STT (native) et le catch de
   `_startSttListen`. `VoiceConversationNotifier` écoute après le démarrage réussi (le
   check 500ms initial reste responsable de l'échec de démarrage). `_onSttError` compte les
   échecs consécutifs, **tente une reprise** (redémarrage micro après 400ms) tant que
   `state == listening` et le micro n'est pas déjà reparti, et **bascule en état error après
   3** (anti-boucle infinie). Reset du compteur à 0 sur un speech final exploitable (STT
   fonctionne).
7. **`BargeInIntent.stop` corrigé** : nouvelle méthode `_returnToListening()` — coupe le
   TTS (déjà fait), repasse en `listening` et rouvre le micro **sans round-trip LLM**.
   L'utilisateur qui dit « chut »/« arrête » reprend la parole au lieu de déclencher une
   nouvelle réponse. Moins destructif que `stop()` complet (l'utilisateur peut ensuite
   terminer via le toggle UI).

### Alternatives Considérées
- **A. `CancellationToken` dédié (classe custom)** — plus explicite mais Dart n'a pas
  d'annulation first-class ; aurait nécessité une classe wrapper pour un gain nul vs le
  simple `int _generation`. Rejeté : complexité additionnelle sans bénéfice.
- **B. Garder `_isProcessingResponse` bool sans lien à la génération** — insuffisant :
  le `whenComplete` d'un tour supplanté pouvait libérer le drapeau pendant qu'un nouveau
  tour l'avait posé (race LLM ultra-rapide). Rejeté : la liaison à la génération est
  nécessaire pour la correction.
- **C. Pour `stop` : appeler `stop()` (fin de conversation)** — trop destructif : « arrête »
  / « pause » veulent dire « laisse-moi parler », pas « termine la session ». Rejeté :
  `_returnToListening()` préserve la session.
- **D. Pour `stop` : ignorer (rien faire)** — laisserait le TTS finir, contraire à « arrêt
  immédiat ». Rejeté : `_returnToListening()` coupe bien le TTS via `stopSpeaking()`.
- **E. Compteur STT sans reprise (error immédiat au 1er échec)** — trop agressif : un micro
  peut glitcher transitoirement. Rejeté : reprise jusqu'à 3 est plus résilient.
- **F. Exposer l'erreur STT via un callback plutôt qu'un stream** — cassait la cohérence
  avec `onSpeechFinal` (déjà un stream) et compliquait le wiring Riverpod. Rejeté :
  `onSttError` stream est homogène.

### Conséquences
**✅ Corrigé**
- Barge-in `repeat` fonctionne désormais (fin du skip silencieux).
- Aucune continuation async ne peut rouvrir le micro / écraser l'état d'un tour obsolète.
- `stop()`/`startConversation()` repartent d'un état propre (plus de drapeaux stale).
- Micro instable mid-conversation → reprise automatique, puis error borné après 3 (plus de
  blocage infini en `listening`).
- « chut »/« arrête » coupe le TTS et rend la parole à l'utilisateur (plus de nouvelle
  réponse intempestive).
- API publique 100% conservée : enum `VoiceConversationState` (5 valeurs), champs
  `VoiceConversationStatus` (`.state/.transcript/.error/.emotion/.bargeInEnabled`),
  méthodes `startConversation/stop/toggle/setBargeInEnabled`, `voiceConversationProvider`.
  Vérifié : `chat_screen.dart` + `aurora_splash.dart` (seuls consommateurs) n'accèdent qu'à
  l'API publique — rétro-compatible.

**⚠️ À valider sur device (Xiaomi 12)**
- 5 tours complets, barge-in >3 mots (repeat/topicChange/stop), reprise micro après erreur
  STT, pas de monologue, TTS fluide. Cf. CLAUDE.md « Tester mode vocal V16 ».

**⚠️ Limite**
- `flutter analyze` non exécutable ici (binaires SDK 644) — vérification par traçage statique
  (enum exhaustif, 0 référence externe aux méthodes privées, API publique conservée).
  `flutter analyze` + `flutter test` à lancer en local avant release.

---

## ADR-029 : Bloc 3 (2026-06-16) — Décomposition chat_notifier (1/≥5) : extraction TravelParamsParser + déduplication du parsing vol/météo

**Statut** : Accepté · **Date** : 2026-06-16 · **Bloc** : 3 (Décomposition god object)

### Contexte
`ChatNotifier` (`lib/features/chat/presentation/chat_notifier.dart`) est un god object de
**4270 lignes** mêlant gestion d'état Riverpod, routing IA, parsing de langage naturel,
commandes slash, orchestration de recherche, quota, TTS, et actions navigateur. L'audit
Phase 1 l'a classé P1 (le plus gros dette d'architecture du projet). La décomposition est
planifiée en extractions successives par clusters cohérents : `TravelParamsParser`
(parsing vol/météo, statique pur), puis `QuotaService`, `SearchOrchestrator`,
`SlashCommandDispatcher` (le plus couplé à l'état), `BrowserActionDispatcher`.

Le cluster **parsing vol/météo** présentait en plus une **duplication de source** — deux
implémentations parallèles du même parsing, avec chacune un défaut différent :

1. **`ChatNotifier`** (presentation/chat_notifier.dart, ~229 lignes) — regex mois **FR/EN
   seulement**, mais `normalizeDate` **sûr** (`int.parse` + `try/catch` → retourne la chaîne
   brute sur entrée invalide ; test attend `normalizeDate('not-a-date') == 'not-a-date'`).
2. **`SearchIntentExtractor`** (data/search_intent_extractor.dart, ~164 lignes) — regex mois
   **6 langues** (FR/EN/ES/DE/IT/PT), mais `normalizeDate` **non sûr** (string `padLeft` sans
   parsing → produisait `'date-0a-not'` pour `'not-a-date'`, bug latent jamais exposé car
   seulement appelé sur des matches regex `numericDate` valides).

Les deux vivaient côte à côte sans se partager la logique. Les tests
(`test/features/chat/enhanced_search_test.dart`) appellent les statiques `ChatNotifier.*`
(`parseFlightParams`, `extractCity`, `extractZipCode`, `normalizeDate`, `parseMonth`) → toute
extraction devait préserver cette surface publique.

### Décision
Extraire une **source unique** `TravelParamsParser` (`lib/features/chat/data/travel_params_parser.dart`,
299 lignes, classe utilitaire à constructeur privé, méthodes 100% statiques et pures) qui
prend le **meilleur des deux** chemins et corrige leurs défauts respectifs :

- **Regex mois = surensemble 6 langues** (FR/EN/ES/DE/IT/PT). Les cas FR/EN passent à
  l'identique (les patterns vol exigent structure `ville-tiret-ville + date` → aucun nouveau
  faux positif introduit par l'élargissement).
- **`normalizeDate` sûr** (`int.parse` + `try/catch`) — préserve
  `normalizeDate('not-a-date') == 'not-a-date'`. Le bug latent du `padLeft` est éliminé.
- **`parseMonth` délègue** au `parseMonth` top-level de `language_service.dart` (déjà source
  unique partagée par les deux anciens chemins) via `import ... as lang`.
- **Stop-words = union** des deux listes (45 de `ChatNotifier` + `'un'` de
  `SearchIntentExtractor` = 46). Retirer `'un'` aurait régressé `SearchIntentExtractor`
  (« un vol Paris-Londres » → « Un Paris-Londres » → `Un` capturé comme ville départ) ;
  l'ajouter ne régresse pas `ChatNotifier` (les cas de test négatifs n'ont pas la structure
  ville-ville+date).

**Wiring** :
- `chat_notifier.dart` — 4 sites d'appel (branche vols + branche météo) utilisent
  `TravelParamsParser.*` directement. Les 5 anciennes méthodes statiques publiques
  (`parseFlightParams`, `extractCity`, `extractZipCode`, `normalizeDate`, `parseMonth`)
  deviennent des **shims une-ligne** qui délèguent → rétro-compatibilité des tests préservée
  (mêmes signatures `ChatNotifier.*`).
- `search_intent_extractor.dart` — `_extractFlightParams` délègue à
  `TravelParamsParser.parseFlightParams` en tête, garde son repli fuzzy
  (`_extractCities`/`_extractDates`, auto-suffisant — n'appelle pas le `normalizeDate`
  supprimé). Les 3 méthodes mortes (`_tryParseFlightParamsGeneric`, `_normalizeDate`,
  `_sanitizeFlightQuery`) sont supprimées ; `_cleanQuery` et `_isStopWord` (encore
  utilisés) sont conservés.

### Alternatives
- **Shim sur `SearchIntentExtractor` au lieu de `ChatNotifier`** : rejeté — les tests
  appellent `ChatNotifier.*`, pas `SearchIntentExtractor.*`. Inverser aurait cassé la
  compat sans gain.
- **Garder `lang` comme paramètre** de `parseFlightParams(message, lang)` : rejeté — le
  paramètre `lang` de l'ancien `_tryParseFlightParamsGeneric(message, lang)` n'était
  **jamais utilisé** dans le corps (regex mois hardcodée). Le drop simplifie l'API.
- **Fusionner les listes de stop-words au plus petit commun** (45, sans `'un'`) : rejeté —
  régressait `SearchIntentExtractor` (voir ci-dessus). L'union (46) est sûre pour les deux.

### Conséquences
**✅ Corrigé / Amélioré**
- **Source unique** : un seul parser vol/météo au lieu de deux. Toute évolution future
  (nouveau pattern, nouvelle langue) se fait à un seul endroit.
- **Bug latent éliminé** : `normalizeDate` n'est plus jamais appelé sur une entrée invalide
  avec l'implémentation `padLeft` non sûre (le path `SearchIntentExtractor` qui l'appelait
  sur des matches regex valides ne masquait le bug que par chance).
- **Couverture 6 langues** étendue au path `ChatNotifier` (était FR/EN). Amélioration nette
  sans régression test.
- **chat_notifier.dart : 4270 → 4042 lignes** (−228 net, −270 au diff). La décomposition est
  amorcée ; le cluster le plus propre (statique pur) est extrait en premier comme preuve du
  pattern.
- **search_intent_extractor.dart : ~1168 → 1004** (−164). Trois méthodes mortes supprimées.
- **API publique conservée** : `ChatNotifier.parseFlightParams/extractCity/extractZipCode/
  normalizeDate/parseMonth` existent toujours (shims déléguants) → `enhanced_search_test.dart`
  compile sans modification. Vérifié par traçage statique : 0 référence externe aux méthodes
  privées supprimées, tous sites d'appel migrent vers `TravelParamsParser.*`.

**⚠️ Limite initiale (levée 2026-06-17)**
- À l'écriture, `flutter analyze`/`flutter test` étaient in exécutables (binaires SDK en 644,
  artefact d'extraction) → vérification par traçage statique exhaustif (grep des méthodes
  supprimées → 0 référence externe ; lecture des bodies `_extractFlightParams`/`_extractDates`
  → aucune dépendance aux méthodes supprimées ; lecture des shims → délégation correcte).
  **Levé au Bloc 4** (restauration des perms SDK `chmod +x bin/cache/{dart-sdk,artifacts}`) :
  `flutter analyze` compile sans erreur ni warning (162 lints `info` pré-existants — style
  uniquement, non bloquants) ; `flutter test` passe. Voir « Vérification » ci-dessous.

### Vérification (2026-06-17, Bloc 4) — tests + 3 bugs réels corrigés

L'extraction rendait enfin les fonctions **testables isolément** (elles étaient privées dans
le god object). 68 tests unitaires écrits (`test/features/chat/data/travel_params_parser_test.dart`
46 + `web_search_trigger_test.dart` 22). La 1ʳᵉ exécution a **exposé 3 bugs réels pré-existants**
(latents car non testés) — aucun n'est une régression de l'extraction, tous antérieurs. Corrigés
et vérifiés (`68/68` + `33/33` régression) :

1. **Absorption de mot-clé capitalisé** (`Flug Berlin Hamburg` → `from` capturé `"Flug Berlin"`) :
   la regex `cityName = [A-ZÀ-Ÿ][a-zà-ÿ]+…` capturait avidément un mot-clé de voyage capitalisé
   en tête. **Fix** : `_travelKeywords` (Set multilingue FR/EN/ES/DE/IT/PT) + `_stripLeadingKeyword`
   en post-traitement de `parseFlightParams` (appliqué sur les deux chemins original + repli, DRY).
   Les mots-clés minuscules ('vol') ne sont jamais capturés (`[A-ZÀ-Ÿ]` exige une majuscule) ;
   les villes composées (« New York », « Sao Paulo ») sont préservées (strip s'arrête au 1ᵉʳ
   mot non-clé).
2. **Dérive regex ↔ map** (PT `setembro` → janvier) : `TravelParamsParser.monthPattern`
   (source unique, 6 langues) capturait `[Ss]etembro`, mais la map `parseMonth` de
   `language_service.dart` n'avait pas l'entry `setembro` → retournait 1 (défaut). **Fix** :
   ajout `'setembro': 9` + commentaire documentant le **contrat regex ↔ map** (toute
   orthographe capturable DOIT avoir une entry, directe ou via homonyme d'une autre langue).
   Audit confirmé : `setembro` était le SEUL manquant à orthographe unique (les autres gaps
   DE/IT/PT sont sauvés par collisions inter-langues : `august` EN==DE, `marzo` ES==IT,
   `agosto` ES==IT==PT, `novembre` FR==IT, `abril` ES==PT).
3. **Repli météo minuscule cassé** (`météo paris` → null) : le repli capitalisait via
   `\b([a-zà-ÿ])`, mais en Dart (regex ECMAScript) `\w` = `[A-Za-z0-9_]` seulement — les accents
   sont non-mot, donc `\b` marquait une frontière à **chaque** accent → `météo` devenait `MÉTÉO`
   (chaque `é` capitalisé) et le mot-clé `[Mm]étéo` (sensible à la casse) ne matchait plus.
   **Cause racine** = la regex de capitalisation, pas le motif du mot-clé. **Fix** : extraction
   de `_capitalizeWords` (`(^|[\s-])([a-zà-ÿ])` en préservant le délimiteur) — capitalise la
   1ʳᵉ lettre après début/espace/tiret sans toucher aux accents internes (`météo`→`Météo`,
   `août`→`Août`, `paris-londre`→`Paris-Londre` — le tiret reste un délimiteur, requis par les
   tests de vol à trait d'union). Partagée par les replis de `parseFlightParams` **et**
   `extractCity` (DRY). Les mots-clés météo des patterns 1 & 2 sont aussi passés en
   insensibles à la casse via brackets `[Mm]étéo|[Mm]eteo|…` (la ville reste `[A-ZÀ-Ÿ]` —
   `caseSensitive:false` sur tout le motif aurait fait matcher des mots minuscules comme
   ville : « temps fait » dans « quel temps fait-il à Marseille » → capturait « Fait »).

**Résultat** : `flutter test` → **68/68** (travel_params_parser 46 + web_search_trigger 22).
Régression : `enhanced_search_test.dart` (28, shims `ChatNotifier.*`) +
`search_service_parsing_test.dart` (5) = **33/33** verts — les 3 fixes + le refactor
`_capitalizeWords` + l'entry `setembro` ne régressent aucune expectation existante. `flutter
analyze` : compile OK, 0 erreur/0 warning, 162 lints `info` pré-existants (style). Bugs
corrigés dans `travel_params_parser.dart` (Bugs 1 & 3 + `_capitalizeWords`) et
`language_service.dart` (Bug 2).

**📊 Progression Bloc 3** : 2/≥5 clusters extraits (TravelParamsParser + WebSearchTrigger —
cf. ADR-030). Réévaluation post-cluster-2 : `QuotaService` **déjà extrait** (services dédiés
`quota_service.dart` / `file_quota_service.dart` / `search_quota_service.dart` /
`voice_quota_service.dart` existent ; `chat_notifier` ne garde que l'orchestration state-coupled
des appels + `_PendingMessage` retry — pas une cible statique propre) ; `classifyTask` **non
dupliqué** (vit uniquement dans `model_router.dart` — l'item « dédup classifyTask » de l'audit
était une erreur). Reste : `SlashCommandDispatcher` (~2200 lignes, le plus couplé à l'état —
abordé en dernier, requiert `flutter analyze` local pour vérif), `BrowserActionDispatcher`,
`SearchOrchestrator` (partie state-coupled).

---

## ADR-030 : Bloc 3 (2026-06-16) — Décomposition chat_notifier (2/≥5) : extraction WebSearchTrigger (décision de recherche web)

**Statut** : Accepté · **Date** : 2026-06-16 · **Bloc** : 3 (Décomposition god object)

### Contexte
Suite logique de l'ADR-029. Le cluster **« faut-il déclencher une recherche web ? »** vivait
dans `ChatNotifier` sous forme de deux méthodes privées statiques :
- `_needsWebSearch(message)` (~80 lignes) — heuristique multilingue (FR/EN/ES/DE/IT/PT) :
  déclencheurs (factual/temporel : actualité, prix, météo, vols, « what is »…) vs exclusions
  (créativité/code/opinion : écris, code, poème, « write a », « what do you think »…) + règle
  des questions `?` (courte = recherche, > 100 chars = conversationnelle).
- `_extractSearchQuery(message)` (~16 lignes) — strippe les salutations + tronque à 200 chars.

Ces deux fonctions sont **100% pures** (aucun état, aucun `ref`, aucune IO). Elles n'avaient pas
été dupliquées (contrairement au cluster 1), mais leur place dans un god object de 4042 lignes
empêchait de les tester isolément et alourdissait la lecture.

### Décision
Extraire une classe utilitaire `WebSearchTrigger` (`lib/features/chat/data/web_search_trigger.dart`,
128 lignes, constructeur privé, méthodes statiques pures) — même pattern que `TravelParamsParser`.

**Wiring** :
- `chat_notifier.dart` 4042→3943 (−99) : les 3 sites d'appel (branche recherche enrichie +
  branche recherche web classique + extraction de requête) utilisent `WebSearchTrigger.*`
  directement. Les 2 méthodes privées sont **supprimées** (pas de shim : privées `_`-préfixées →
  invisibles hors bibliothèque, 0 référence test vérifiée par grep).
- Un commentaire pointeur indique le déplacement (traçabilité pour les futurs lecteurs).

### Alternatives
- **Shim statique comme pour TravelParamsParser** : rejeté — `_needsWebSearch`/
  `_extractSearchQuery` sont privées, donc aucune API publique à préserver (contrairement à
  `parseFlightParams` etc. qui étaient publics et appelés par `enhanced_search_test.dart`). Le
  shim aurait été du code mort.
- **Fusion avec `SearchIntentExtractor`** : rejeté — `SearchIntentExtractor.extract()` classifie
  le *type* de recherche (flights/hotels/products…) en supposant que la recherche a lieu ;
  `WebSearchTrigger.needsWebSearch()` est le *gatekeeper* décidé *avant* de chercher. Cohésion
  distincte, mélanger aurait surchargé `SearchIntentExtractor` (déjà riche : 9 keyword maps par
  langue). Mieux vaut deux classes à responsabilité unique (SRP).

### Conséquences
**✅ Amélioré**
- `chat_notifier.dart` 4270→3943 cumulé (−327 sur les 2 clusters, −7,6 %). 2/≥5 clusters.
- `WebSearchTrigger` testable isolément (pur) — les heuristiques multilingues de
  déclenchement/exclusion peuvent désormais avoir des tests unitaires dédiés sans
  `ProviderContainer`.
- Cohésion : toute la logique « gatekeeper de recherche web » au même endroit, 6 langues.

**⚠️ Limite**
- `flutter analyze` non exécutable ici (binaires SDK 644) — traçage statique (grep : 0
  référence restante aux méthodes privées supprimées ; 3 sites d'appel migrés ; 0 réf test).

---

## ADR-031 : Backend — Sortie des I/O bloquants de l'event loop async (Bloc 5)

**Date :** 2026-06-17 · **Statut :** Accepté

**Contexte :** L'audit Phase 1 (ADR-027) avait relevé 6 sites d'I/O bloquant dans
des routes FastAPI `async`. Un appel sync dans une coroutine `async` gèle **tout**
l'event loop pour toute sa durée — chaque requête concurrente (chat streaming,
`/scrape`, `/search_smart`, `/download_media`, `/crawl`) est gelée aussi. Le pire :
`script_executor.execute_script` utilisait `subprocess.run(timeout=15)` → gel de
**15 s** de l'event loop par exécution de sandbox. Les routes `/download_media`
(yt-dlp, 10-30 s) et `/crawl` (BFS multi-page sync) étaient tout aussi bloquantes.

**Décision :** Déplacer chaque I/O bloquant hors du thread de l'event loop, sans
changer les signatures publiques (routes + fonctions `async` préservées).

1. **`script_executor.execute_script`** — `subprocess.run` →
   `asyncio.create_subprocess_exec` + `asyncio.wait_for(proc.communicate(),
   timeout)` + `proc.kill()` + `await proc.wait()` sur `asyncio.TimeoutError`.
   Le child tourne dans son propre processus ; l'event loop reste libre pendant
   jusqu'à 15 s. Reap explicite + garde `ProcessLookupError` (race : proc déjà
   mort au kill) → **aucun zombie** ne survit à la requête. Pattern déjà établi
   dans `config_agent.py`.
   - ⚠️ **Subtilité** : `asyncio.wait_for` lève `asyncio.TimeoutError` (alias du
     builtin `TimeoutError`), **PAS** `asyncio.TimeoutExpired` (qui n'existe que
     sur l'API sync `subprocess`). La 1ʳᵉ implémentation avait
     `except asyncio.TimeoutExpired:` → `AttributeError` catché par le
     `except Exception` externe → message d'erreur confus **ET** child non-tué
     (zombie leak 100 % CPU). Le test `test_execute_script_does_not_block_event_loop`
     + le check zombie post-run ont révélé le bug, corrigé + durci (garde
     `ProcessLookupError`). 2 zombies à 100 % CPU leakés au 1ᵉʳ run ont été
     nettoyés manuellement (`kill -9`) — **preuve que le reap est critique**.

2. **`search_engine.scrape_url`** — le parse BeautifulSoup (CPU-bound, 50-200 ms
   sur pages lourdes, pure Python) extrait vers helper module-level sync
   `_extract_scrape_data(html, url, selectors)` → dispatch
   `await asyncio.to_thread(...)`. L'HTTP fetch reste async ; seul le parse CPU
   quitte le thread loop. Helper module-level = testable isolément (pas de
   closure, pas de réseau). `import re` remonté au niveau module (l'inline
   `import re` dans la fonction est supprimé).

3. **`search_smart._scrape_page`** — même extraction : helper sync
   `_parse_scraped_page(html, url, domain_key)` + `asyncio.to_thread`. Lit
   `_LEARNED_SELECTORS` (global module) — accessible depuis un helper
   module-level.

4. **`main.py` routes `/download_media` + `/crawl`** — stopgap
   `await asyncio.to_thread(service.extract_media/crawl, body.url)`. yt-dlp
   (10-30 s) et le crawl BFS multi-page ne gèlent plus l'event loop. Signature
   des routes préservée. La **réécriture full-async** (`httpx.AsyncClient` dans
   `DownloadService`/`CrawlService` + `asyncio.gather` pour crawl parallèle) est
   notée en follow-up — c'est un bloc séparé (refactor de 2 services, pas un
   stopgap one-line).

5. **`config_agent.exec_migrate_docker_data` (`open`/`os.makedirs`)** —
   **DIFFÉRÉ avec rationale** : I/O sub-ms (lecture/écriture
   `/etc/docker/daemon.json`) pris en sandwich entre `systemctl stop/start docker`
   qui durent **des minutes** et sont déjà correctement awaited via
   `create_subprocess_exec`. Wrapper un fichier sub-ms dans `asyncio.to_thread` =
   cérémonie zéro gain réel. Différé au nom du « zéro patch aveugle » (pas de
   complexité sans bénéfice mesurable). Documenté pour traçabilité.

### Conséquences
**✅ Amélioré**
- Event loop non bloqué : 15 s (sandbox), 10-30 s (yt-dlp), multi-page (crawl),
  50-200 ms (parse) ne gèlent plus les requêtes concurrentes. Throughput
  concurrent restauré pour un app visant 1M+ users.
- `execute_script` réape correctement son child (kill + wait + garde
  `ProcessLookupError`) → zéro zombie, zéro fuite CPU.
- Helpers parse module-level → testables isolément (12 tests net-new).
- Signatures publiques préservées (routes + fonctions `async`) → zéro breaking
  change pour les appelants (Dart `SearchServiceGlobal` inchangé).

**⚠️ Limite / follow-up**
- Stopgap `/download_media`+`/crawl` : `asyncio.to_thread` consomme un thread du
  pool par défaut (max 32) pour la durée du blocage. 32 downloads concurrents
  saturent le pool. La réécriture full-async était le follow-up (refactor des 2
  services, bloc séparé). **✅ Résolu (2026-06-17, orchestration multi-agent)** :
  `DownloadService` + `CrawlService` réécrits en `httpx.AsyncClient` +
  `asyncio.gather` (crawl parallèle batches `_MAX_CONCURRENT=5`). yt-dlp via
  `asyncio.create_subprocess_exec` + `sys.executable` (hérite le venv avec yt_dlp
  installé) + `wait_for(timeout=30)` + `proc.kill()`+`await proc.wait()` sur
  `asyncio.TimeoutError` (reap `ProcessLookupError`, zéro zombie). `main.py` routes
  `/download_media`+`/crawl` → `await service.*` (stopgap `asyncio.to_thread`
  retiré). Backend pytest **39/39 vert**.
- `DeprecationWarning` bs4 `text=` → `string=` (`search_engine.py:113`,
  `search_smart.py`) pré-existante, hors-périmètre Bloc 5, notée.

### Vérification (2026-06-17)
- `backend/tests/test_async_io.py` : **12 tests** — 5 helpers purs sans réseau
  (`_extract_scrape_data`/`_parse_scraped_page` : title, links, selectors,
  prices), 1 signatures (`scrape_url`/`_scrape_page`/`execute_script` toujours
  `async`), 6 `execute_script` end-to-end dont `test_execute_script_does_not_block_event_loop`
  (ticker concurrent prouve le non-blocage de l'event loop) et
  `test_execute_script_timeout_reaps_child_fast` (timeout respecté < 4 s +
  reap). **12/12 ✅**.
- Suite backend : **20 passed** (12 nouveaux + 8 pré-existants), 2 failed
  (**pré-existants** `test_chat_streaming_mock`/`test_chat_non_streaming_mock` —
  `unhashable type: dict` dans `chat_router` + mock non-awaité, hors-périmètre
  Bloc 5), 2 collection errors (**pré-existants** template tests — chemin
  relatif `templates`, hors-périmètre). **Zéro régression introduite.**
- **Résolution ultérieure (2026-06-17)** : les 4 issues « hors-périmètre » sont
  résolues — les fichiers template tests supprimés (`test_commander_template.py`,
  `test_vision_template.py` → collection errors disparues) et les échecs
  `test_chat_*_mock` levés. Suite backend désormais **39 passed / 0 failed / 0
  collection error** (1 warning résiduel = déprecation Starlette/httpx TestClient,
  tiers, non actionable sans changer de client). Cleanup concomitant : BS4
  `find_all(text=...)` → `find_all(string=...)` (`search_engine.py`,
  `search_smart.py`) — `text` est déprécié dans BS4.
- Post-run orphan check : **0 zombie** (le reap durci fonctionne).
- Fichiers : `script_executor.py` (subprocess async + reap), `search_engine.py`
  (+ helper), `search_smart.py` (+ helper), `main.py` (2 routes stopgap),
  `backend/tests/test_async_io.py` (nouveau, 12 tests).

---

## ADR-032 : Flutter — Réduction analyzer warnings 89→0 (buckets sûrs + dead-code + clusters génériques + incrément 6 covariant/suppression)

**Date** : 2026-06-17
**Statut** : Accepté
**Contexte** : `flutter analyze` signalait 89 warnings (0 erreur) projet-wide. Trois
buckets sont **analyzer-garantis sûrs** (comportement préservé par construction du
langage / du linter) : `unused_import` (21), `unused_local_variable` (13),
`dead_null_aware_expression` (2) = 36 warnings. Le reste (53) touche des catégories
stateful/risquées (override_on_non_overriding_member, argument_type_not_assignable sur
du Riverpod/Flutter runtime, etc.) — hors périmètre d'une correction autonome sans
vérif device.

**Décision** : éliminer les 36 warnings des 3 buckets sûrs, par cas, sans toucher au
comportement :

1. **21 `unused_import` — delete**. Zéro comportemental : Dart lazy-init les
   bibliothèques importées au 1er accès symbole, retirer un import non utilisé ne change
   rien. Cascade gérée : retirer la lecture `isProProvider` (→ TODO, cas 3) rendait
   `subscription_service.dart` (qui porte `isProProvider`) newly-unused à
   `chat_screen.dart:24` → import retiré aussi.

2. **13 `unused_local_variable` — par cas** (PAS un bucket uniforme) :
   - 5 prod dead-code pur (lecture de champ / `replaceAll` / `Theme.of(...)` dont le
     résultat n'est jamais lu, aucun side effect) → **delete** (`thumbnail`,
     `safeTitle`, `colorScheme`, `key`, `lower`).
   - 1 `errBody` (`worker_chat_client.dart`) = `await response.stream.bytesToString()`
     qui **draine le stream** (side effect) → **réutilisé** en `debugPrint`
     observabilité (matche le pattern 400-case existant ligne 100). Ne pas juste
     supprimer : on préserve le drain.
   - 1 `isPro` (`chat_screen.dart:487`) → **TODO inline, PAS supprimé bêtement**.
     Latent bug réel découvert : la limite d'upload est 5 MB pour **tous** les tiers
     (`maxAttachmentsTotalBytes` fixe `message.dart:9`), la doc dit « 50 MB Pro » mais
     `isPro` était lu pour rendre la garde tier-aware et **jamais câblé**. Quota =
     comportement stateful haut-risque → deferred (catégorie #11), documenté TODO +
     CLAUDE.md, corrigé au passage quota device-verifié.
   - 6 tests (3× `FileUploadService()` smoke, 3× fixtures HTML pour un parser privé) →
     **réutilisés en assertion réelle** (`expect(FileUploadService(), isNotNull)` /
     `expect(html, contains('href'))`). Note : le préfixe `_` (convention Dart
     d'exemption) **n'a PAS silencé** ce linter `unused_local_variable` —
     contrairement à l'intuition, il faut *utiliser* la variable.

3. **2 `dead_null_aware_expression`** — `?? '0'` sur
   `a.name.replaceAll(RegExp(r'[^\d]'), '')` qui est provably non-null (renvoie
   toujours `String`) → branche `??` morte retirée.

**Méthode** : script Python audité `/tmp/reduce_warnings.py` — line-number-driven,
verify-before-write (toutes les ancres `expect` vérifiées sur l'original avant
écriture), bottom-up per file (ligne la plus haute d'abord pour préserver les
numéros), all-or-nothing (1 échec verify = 0 fichier écrit). **Incident** : le script
a corrompu `chat_screen.dart` à 0 bytes (mécanisme peu clair — verify lisait
multi-ligne, apply_file a lu vide). **Récupération** : `git checkout HEAD --
lib/features/chat/presentation/chat_screen.dart` (version 872 lignes restaurée),
puis 4 edits `chat_screen` + 4 edits tests ré-appliqués via **Edit tool** (atomique,
single-edit, harness-tracked) — préféré aux scripts Python pour la mutation
multi-fichier.

**Conséquences** :
- Vérif post-édit : `flutter analyze` → **0 erreur / 53 warnings / 0 info-blocked**
  (les 4420 `info` résiduels = lints stylistiques pré-existants, hors périmètre).
  Règle-count diff confirme 89→53 = 36 cleared (les compteurs par-règle, pas les
  numéros de ligne qui shiftent).
- `flutter test` full suite : **752/752 verts** (exit 0), incl. les 2 fichiers de test
  modifiés (18 tests).
- Latent bug quota-Pro documenté (TODO `quota-pro` `chat_screen.dart:484` +
  `CLAUDE.md` § Priorité moyenne) — **✅ Corrigé (2026-06-17, orchestration
  multi-agent)** : `message.dart` ajoute `proMaxAttachmentsTotalBytes` 50MB +
  helper `attachmentLimitFor({required bool isPro})` (50MB Pro / 5MB free) ;
  garde agrégée tier-aware en tête `sendMessage` (`chat_notifier.dart`) +
  `_handleImagePick`/`_handleFilePick` (`chat_screen.dart`) câblés au helper ;
  `isPro` lu via `ref.read(isProProvider.future).catchError((_) => false)`
  (JAMAIS `.value`) ; test `attachmentLimitFor is tier-aware` (50MB/5MB).
  **Reste device-only** : smoke-test Xiaomi 12 (état stateful haut-risque) —
  adb ne voit pas le device (USB debugging / autorisation / câble).
- Leçon outillée : **Edit tool > script Python** pour la mutation multi-fichier
  chirurgicale (atomicité, pas de corruption, harness-tracked). Scripts Python
  réservés au read-only/verify ou à la génération de rapports.

**Fichiers** : 21 lib + `main.dart` (imports), `chat_notifier.dart` (thumbnail/safeTitle/
imports), `chat_screen.dart` (imports/isPro→TODO/colorScheme), `worker_chat_client.dart`
(errBody), `file_upload_service.dart` (dead_null), `enhanced_search_service.dart`
(key), `search_intent_extractor.dart` (lower), `file_upload_service_test.dart` (×3),
`search_service_parsing_test.dart` (×3). `CLAUDE.md` + ce fichier (docs).

### Complément — incrément 2 (dead-code analyzer-garanti, 8 warnings supplémentaires)

Après l'incrément 1 (89→53), re-passe sur les buckets restants **analyzer-garantis
dead-code** (comportement préservé par construction) — 8 warnings cleared (53→45) :

- **5 `unused_field`** supprimés (champs privés jamais lus, aucun reflection/sérialisation,
  affectation neutralisée où présente) :
  - `_lightBgColor` (`document_generation_service.dart:203`) — const couleur morte
    (sibling `_primaryColor` utilisé). Delete.
  - `_prefsDatesKey` (`search_cache_service.dart:54`) — const clé SharedPreferences
    planifiée pour persistance des dates TTL, jamais câblée. Delete.
  - `_rate` + `_pitch` (`edge_tts_service_web.dart:11,12`) — champs du stub web écrits
    par `setRate`/`setPitch` mais jamais lus (le stub `synthesize` throw). Setters
    neutralisés en no-op (match le pattern `setEmotion` existant L20) → signatures
    préservées pour la compat d'interface avec `edge_tts_service_io.dart` (conditional
    export). Champs supprimés.
  - `_referralScheme` (`deep_link_service_io.dart:14`) — const scheme `corelia://referral`
    (stale rename AironBot→CorelIA→Corely) jamais référencée en Dart (le manifest Android
    a sa propre string). Delete.
- **1 `unnecessary_null_comparison`** (`location_service_web.dart:14`) —
  `if (geolocation == null) return null;` sur `html.window.navigator.geolocation`
  typé non-nullable (`Geolocation`). La garde est toujours false (dead). Redondant car
  le `catch (_) { return null; }` L32 retourne null si `getCurrentPosition` throw
  (cas runtime geolocation absent). Delete la garde — comportement identique.
- **1 `body_might_complete_normally_catch_error` + 1 `inference_failure_on_untyped_parameter`
  (cascade)** (`main.dart:202-209`) — `sync.mergeWithLocal(remote).catchError((e) {...})`
  dont le handler complete normalement (retourne void où `SyncedPreferences` attendu) +
  param `e` non-typé. Restructuré en listener `async` + `try/catch (e)` — comportement
  identique (merge fire-and-forget, erreurs loggées, résultat déjà discarded), type-correct.
  Les 2 warnings cleared d'un coup (l'inference_failure_on_untyped_parameter était sur
  le callback `(e)` du catchError).

**`_feedback` (chat_notifier.dart:171/182) — DEFERRED** : `late final FeedbackCollector
_feedback` assigné L182 (`FeedbackCollector(_learningRepo)`) mais jamais lu. La
construction peut avoir des side effects, et le champ est dans le god object
chat_notifier (catégorie stateful haut-risque, couverture tests chat faible, deferred
#11). Retirer = retirer aussi l'affectation + potentiellement le constructeur side-effect
→ risque régression. Warning laissé (dead-read = pas d'erreur runtime), documenté ici.

**Conséquences incrément 2** : `flutter analyze` 53→**45 warnings / 0 erreur**.
`flutter test` **752/752 verts** (exit 0). Aucune régression.

### Complément — incrément 3 (callbacks typés, 4 warnings)

Après l'incrément 2 (53→45), typage des callbacks `Function` non-typés (4 warnings cleared,
45→41) :

- **3 `Function`→`void Function(String code)`** (`deep_link_service_io.dart:19,35` +
  `deep_link_service_web.dart:5`) : param `onReferralCode` du callback de deep link.
  `void Function(String)` accepte tout callback (void accepte n'importe quel retour)
  → narrowing sûr pour fire-and-forget. Zéro behavior change.
- **1 `js.allowInterop((event))`→`(dynamic event)`** (`web_speech_bridge_web.dart:127`) :
  le callback JS reçoit un `JsObject` typé dynamiquement côté Dart ; `dynamic` préserve
  le `callback(event as js.JsObject)` suivant.

**⚠️ Incident cascade (leçon outillée)** : dans le même incrément, `Future.delayed<void>(...)`
a causé 4 `wrong_number_of_type_arguments_constructor` **ERROR** (`dio_client_io.dart:102`,
`dio_client_web.dart:80`, `browser_action_test.dart:253,263`). `Future.delayed` **N'est PAS
générique** (contrairement à `Dio.get<T>` / `showDialog<T>`) → les 4 sites revert à
`Future.delayed(...)`. Leçon : **vérifier la genericité d'un constructeur avant d'annoter** —
les buckets type-annotation portent un risque cascade réel ; l'erreur `Future.delayed` est
un faux-positif non-clearable sans bruit `() {}` (4 warnings acceptés, voir incrément 5).

### Complément — incrément 4 (clusters génériques Dio/showDialog, 17 warnings)

17 `inference_failure_on_function_invocation` cleared (41→24). À la différence de
`Future.delayed`, les méthodes Dio `get<T>`/`post<T>`/`fetch<T>` et Flutter `showDialog<T>`
**sont génériques** — le seul risque est de choisir le mauvais `T` par site. Analyse
per-site du handler de `response.data` pour le type correct, zéro behavior change :

- **SerpAPI `get<Map<String, dynamic>>` ×9** (`enhanced_search_service.dart:253,452,627,
  678,736,796,869,873,937`) : précis (réponse JSON = objet), cohérent avec le précédent
  L105 (`get<Map<String, dynamic>>` déjà présent), `_list(dynamic data, String key)` L192
  accepte `Map?` (param `dynamic`), nullable-index nulle part (`resp.data` toujours via
  `_list`). `resp.data` devient `Map<String, dynamic>?` → `_list(resp.data, key)` inchangé.
- **Dio `fetch<dynamic>` ×2** (`dio_client_io.dart:105`, `dio_client_web.dart:83`) :
  retry interceptor, la réponse reshaped est inconnue (retry de la requête originale),
  data non lue (passée à `handler.resolve`) → `<dynamic>` préserve la sémantique.
- **`post<dynamic>`** (`chat_api_service.dart:52`) : `responseType: ResponseType.stream`,
  `response.data.stream as Stream<List<int>>` accès dynamique → `<dynamic>` préserve.
- **weather `get<dynamic>` ×4** (`weather_service.dart:113,131,205,222`) : formes mixtes
  (current=Map, forecast=Map-avec-list, geo-direct=List, geo-zip=Map). Site 131 a un
  **nullable-index direct** `forecastResp.data['list']` L144 → un type précis (`<Map>`)
  serait une **compile error** (index sur `Map?` non-null-checked) → `<dynamic>` obligatoire
  (préserve l'index dynamique). Site 222 : garde `resp.data != null` pourrait promouvoir
  `data` → `as Map<String, dynamic>` deviendrait `unnecessary_cast` (nouveau warning) →
  `<dynamic>` évite. Les 4 weather sites via `<dynamic>` uniformément.
- **`showDialog<void>`** (`settings_screen.dart:867`) : dialog `pop()` sans valeur, résultat
  non capturé → `Future<void?>` awaité. Zéro behavior change.

**Conséquences incrément 4** : `flutter analyze` 41→**24 warnings / 0 erreur**. `flutter
test` **752/752 verts**. Aucune régression, aucun nouveau warning (les `as` casts préservés
restent des real-casts nullable→non-null, pas `unnecessary_cast`).

### Complément — incrément 5 (strict_raw_type sûrs, 7 warnings)

7 `strict_raw_type` cleared (24→17) — les 12 autres sont dans le god-object chat_notifier
(deferred #11) :

- **`StreamSubscription<Uri>?`** (`deep_link_service_io.dart:16`) : prouvé par l'assignment
  `_linkSubscription = _appLinks.uriLinkStream.listen((uri) {...})` (`uriLinkStream` =
  `Stream<Uri>` → `StreamSubscription<Uri>`). Type précis, zero-risk.
- **6 tests** (`browser_action_test.dart`, `message_test.dart`,
  `multi_attachment_integration_test.dart`) : `isA<Map>()`→`isA<Map<dynamic, dynamic>>()`,
  `isA<List>()`→`isA<List<dynamic>>()`, `as List`→`as List<dynamic>`. Le **subtyping
  covariant** de Dart : `Map<String, X> is Map<dynamic, dynamic>` →
  `isA<Map<dynamic, dynamic>>()` matche **any Map** (sémantique « any Map/List » préservée),
  `as List<dynamic>` == `as List`. Zéro behavior change. Note : `as List` (cast position)
  n'est PAS flaggé par ce config de lint (seuls les type-arguments `isA<T>()` et les
  annotations de champ le sont) — d'où l'incohérence apparente message_test:81 `as List`
  non-flaggé vs message_test:80 `isA<List>()` flaggé. (Incident outillage : j'ai d'abord
  édité `as List` L208 au lieu de `isA<List>()` L207 dans `browser_action_test` — corrigé.)

**Conséquences incrément 5** : `flutter analyze` 24→**17 warnings / 0 erreur**. `flutter
test` **752/752 verts**.

### Reste à 17 — DEFERRED (god-object chat_notifier + false-positives)

Les 17 warnings restants sont **tous** soit des false-positives, soit dans le god-object
chat_notifier (cible de décomposition #11, stateful haut-risque, couverture tests chat
faible) :

- **12 `strict_raw_type`** (`chat_notifier.dart` ×12) : raw `Map`/`List` issus de
  `jsonDecode`/API — chaque site nécessite l'analyse du value-type attendu dans un
  god object de 2000+ lignes qu'on cherche à **réduire**, pas micro-annoter. Cascade-risk
  élevé (mauvais value-type = bug latent) → deferred à la décomposition #11.
- **1 `unused_field` `_feedback`** (`chat_notifier.dart`) : construction side-effect
  possible, retrait = retrait de l'assignation + constructeur → risque régression.
  Deferred #11 (déjà documenté incrément 2).
- **4 `inference_failure_on_instance_creation`** (`Future.delayed` ×4 sur
  `dio_client_io.dart:102`, `dio_client_web.dart:80`, `browser_action_test.dart:253,263`)
  : **false-positives** — `Future.delayed` n'est PAS générique, le lint demande un
  type-arg impossible à fournir sans ajouter du bruit `() {}` (qui n'apporte rien).
  Un-clearable.

**Décision (incrément 5)** : arrêter la réduction à la frontière behavior-preserving vérifiée (89→17,
0 erreur, 752/752 verts). Le reste = god-object à décomposer (#11) + false-positives.
Total cleared incrément 1-5 : **72 warnings (89→17, 81%)**.

### Révision — incrément 6 (17→0, session 68d36b15 suite)

La frontière « behavior-preserving vérifiée (89→17) » a été **étendue à 0** cette session —
les 3 catégories laissées à l'incrément 5 se sont avérées toutes clearable sans behavior change :

- **12 `strict_raw_type`** (`chat_notifier.dart`) → `.cast<Map<dynamic, dynamic>>()` /
  `.whereType<Map<dynamic, dynamic>>()` / `.cast<List<dynamic>>()` (×12). Covariant
  subtyping : raw `Map` ≡ `Map<dynamic, dynamic>` (sémantique « any Map/List » identique,
  `as` casts préservés, zéro behavior change). La crainte « cascade-risk / mauvais
  value-type » de l'incrément 5 était infondée pour ces sites : ils ne lisent PAS le
  value-type, ils rejettent juste le raw type → `<dynamic>` est l'annotation correcte.
- **1 `unused_field` `_feedback`** → retrait du **wiring mort** : `late final _learningRepo`/`_feedback`
  + bloc init (`_learningRepo = LearningRepository(...)` / `_feedback = FeedbackCollector(...)`)
  + imports `learning_repository.dart`/`feedback_collector.dart` retirés du god object.
  La « crainte construction side-effect » de l'incrément 5 était fausse : le wiring n'avait
  **aucun consommateur** (zero read de `_feedback`/`_learningRepo` dans le fichier). Services
  LIVE conservés : `_knowledgeBase` (KnowledgeBaseService), `_consentData`, `_insights`
  (AnonymizedInsightService) — utilisés à `chat_notifier` L2597/L3078 + `_insights.recordSessionStart()`.
- **4 `inference_failure_on_instance_creation`** (`Future.delayed`) → supprimés via
  `// ignore: inference_failure_on_instance_creation, Future.delayed n'est pas générique en Dart 3.41 (false-positive)`
  (dio_client_io.dart:102, dio_client_web.dart:80, browser_action_test.dart:253,263).
  Le « un-clearable » de l'incrément 5 était incomplet : on ne peut PAS annoter
  (`Future.delayed<void>` lève `wrong_number_of_type_arguments_constructor` — confirmé
  empiriquement), MAIS on peut supprimer le lint false-positive via `// ignore:` + reason
  (réponse professionnelle à un lint defect — documente permanent le finding).

**État final** : `flutter analyze` **0 erreur / 0 warnings** (4416 `info` lints restants =
préférences de style pré-existantes, hors périmètre). `flutter test` **790/790 verts**
(752 base + 1 quota tier-aware + 37 IATA, EXIT=0) — vérif intégrée finale post-orchestration
multi-agent (3 agents file-disjoints + 1 orchestrateur).

⚠️ **Orphelins supprimés (2026-06-17, suite orchestration)** : `feedback_collector.dart`
(138 lignes) + `learning_repository.dart` (165 lignes) — après retrait du wiring mort, ils
n'avaient plus **aucun** consommateur ni test (scaffolded-but-never-integrated, ajout V10
commit a822434b). **Décision finale** : suppression sur instruction utilisateur explicite
(« supprime les 2 fichiers »). Méthode : Edit tool atomique (après corruption
`chat_screen.dart` à 0 bytes par un script Python antérieur — récupéré via
`git checkout HEAD`).

**Décision finale (incrément 6)** : réduction poussée à **0 warnings** (89→0, 100%).
Total cleared session : **89 warnings**. La frontière behavior-preserving est désormais
**0 warnings** (toutes catégories clearables sans behavior change).

### Révision — session 68d36b15 suite (Bloc 6) — cluster 4 chat_text_helpers + extension Chrome + quota tier-aware + IATA + backend full-async

**Statut** : Accepté · **Date** : 2026-06-17

Le travail d'extraction de `chat_notifier.dart` amorcé dans les ADR-029/030 a continué
en session 68d36b15 (multi-agent, 3 file-disjoints) avec 5 sous-blocs complémentaires
qui bouclent les clusters « texte pur » et « état stateful » :

#### Bloc 6.1 — Extraction `chat_text_helpers` (cluster 4)

7 helpers texte purs extraits de `chat_notifier.dart` (3943→3862, **−81 lignes** ; cumulé
4 clusters = **−408 lignes** sur 4270) vers `lib/features/chat/data/chat_text_helpers.dart` :
`normalizeDocFormat`, `extractDocumentTitle`, `escapeForJson`, `stripActionCommands`,
`parseJsonLoose`, `buildProductSearchQuery`, `formatAiError`. Test miroir
`test/features/chat/data/chat_text_helpers_test.dart` **39/39 vert**. 7 sites d'appel
migrés (via script Python audité `/tmp/refactor_chat_notifier.py` avec asserts
`count==1` et write gated sur verify). Le `formatAiError` est l'extract le plus
remarquable : il centralise le mapping HTTP code → message user-friendly (401 → clé
invalide, 429 → limite, 400 → erreur API, image issues → message clair) qui était
inliné dans `_buildStream`.

#### Bloc 6.2 — Fix bug parsing vols réel (régression reproduite + corrigé)

Régression couverte par `travel_params_parser_test.dart` : `parseFlightParams("trouve
un billet paris-londre direct du 29/05")` retournait `null`. **Cause** : le repli
`_sanitizeFlightQuery`+`_capitalizeWords` produisait `Paris-Londre 29/05` (le
stop-word `du` strippé par les 46 stop-words de l'ADR-029) qu'**aucun pattern A/B/C/D**
ne matchait (pattern B exigeait `du`/`le` après tiret, mais le strip les avait déjà
retirés). **Fix** : pattern B relaxé `(?:d[ue]|le)\s+` → `(?:d[ue]|le)?\s*` — `du`/`le`
rendu **optionnel**, symétrique au pattern D (qui l'était déjà pour le cas espace).
`travel_params_parser.dart:229-240`. Tests : 47/47 + shims 28/28 vert.

⚠️ **Limite connue (round-trip lowercase)** : `paris-londre du 29/05 au 02/06` — `au`/
`retour` aussi strippés par `_sanitizeFlightQuery` (sinon `au`→`Au` est pris pour une
ville) → date de retour perdue sur le chemin sanitize. **Fix propre** = extraire les
dates **avant** sanitization (à faire en session runtime, pas à risque de toucher
l'extraction de villes).

#### Bloc 6.3 — Quota upload tier-aware (latent bug fixé)

Bug latent découvert à l'incrément 1 (TODO `quota-pro` documenté) : la limite d'upload
était **5 MB pour TOUS les tiers** (`maxAttachmentsTotalBytes` fixe `message.dart:9`)
au lieu de « 5 MB gratuit, 50 MB Pro ». La doc disait « 50 MB Pro » mais `isPro` était
lu pour rendre la garde tier-aware et **jamais câblé**. Fix (logique + tests unitaires) :

- `message.dart` : `proMaxAttachmentsTotalBytes = 50*1024*1024` + helper
  `attachmentLimitFor({required bool isPro})` (50MB Pro / 5MB free). `maxAttachmentsTotalBytes`
  (5MB) + `exceedsAttachmentLimit` **conservés** (tests free-tier).
- `chat_notifier.dart` : garde limite agrégée tier-aware en tête de `sendMessage` —
  `isPro = await ref.read(isProProvider.future).catchError((_) => false)` (**JAMAIS
  `.value`** — AsyncValue peut être null mid-transition). L'erreur d'intégration (duplicate
  `isPro` declaration entre la garde et l'ancienne affectation existante) a été détectée
  et corrigée par l'orchestrateur.
- `chat_screen.dart` : `_handleImagePick` + `_handleFilePick` câblés au helper (SnackBar
  dynamique `${limitMB}MB`). TODO retiré.
- `message_test.dart` : 1 test net-new `attachmentLimitFor is tier-aware`.

⚠️ **Reste device-only** : smoke-test Xiaomi 12 (état stateful haut-risque) — adb ne
voit pas le device (USB debugging / autorisation / câble).

#### Bloc 6.4 — Module IATA (ADR-029) — tests + 2 bugs réels

`test/features/chat/data/iata_codes_test.dart` net-new (~37 tests, 9 groupes) :
lookup direct tous continents, casse, accents/disambiguïsation, fuzzy bidirectionnel,
per-word, prefix 5 chars, quirks ordre-map, null/empty, stabilité 20 codes idempotente.
**2 bugs module réels** découverts & fixés :

1. `resolveIataCode('')` retournait `'PAR'` — le fuzzy `contains("")` matche TOUTES
   les villes. Fix : `if (key.isEmpty) return null;` garde en tête (`iata_codes.dart:250`).
2. `resolveIataCode('ab')` retournait `'SAW'` — 'istanbul sabiha' contient 'ab'. Fix :
   fuzzy global gardé par `if (key.length >= 3)` (`iata_codes.dart:273`).

**2 tests corrigés (prédictions sur l'ordre map, pas bugs)** : `San Jose` → SJC
(Californie, clé directe sans accent) pas SJO ; `SIN` → HEL pas SIN ('helsinki'
précède 'singapore' dans la map → artefact d'ordre du fuzzy `contains`, documenté
dans le groupe quirk).

#### Bloc 6.5 — Backend full-async (follow-up ADR-031)

Le stopgap `asyncio.to_thread` du Bloc 5 saturait le pool à 32 downloads concurrents.
Réécriture full-async de `DownloadService` + `CrawlService` :

- `download_service.py` : `extract_media`/`extract_gallery` → `async def`. yt-dlp via
  **helper script** + `asyncio.create_subprocess_exec` + `wait_for(timeout=30)` +
  `proc.kill()`+`await proc.wait()` sur `asyncio.TimeoutError` (reap `ProcessLookupError`,
  zéro zombie). **Critique** : `sys.executable` (pas `"python3"` nu) → hérite le venv
  avec yt_dlp. Page scraper → `httpx.AsyncClient` + `safe_get` (garde SSRF async).
  `MediaFormat` mort retiré.
- `crawl_service.py` : `crawl()` → `async def`, `httpx.AsyncClient` + `safe_get`. BFS
  parallèle via `asyncio.gather` batches `_MAX_CONCURRENT=5`. `_fetch_and_parse` async
  race-free. `deque`→`list`+`pop(0)`. Signatures préservées.
- `main.py` : `/download_media`+`/crawl` → `await service.*` (stopgap `asyncio.to_thread`
  retiré).

**pytest** : `test_async_io.py` 12/12, suite backend **39/39 vert** (zéro nouveau échec).

#### Bloc 6.6 — Extension Chrome (vérif statique + fix réel)

`bash scripts/build_extension.sh` exit 0 → `build/extension/` + `corely-extension.zip`.
7 patches du script tous vérifiés dans les artefacts : `<base href="./">`,
`loadServiceWorker` neutralisé, `useLocalCanvasKit:true` dans buildConfig, CanvasKit
local, manifest MV3 sans `"type":"module"`, CSP `script-src 'self' 'wasm-unsafe-eval'`,
WAR `*.wasm`/`canvaskit/**`. Contrat action Dart↔JS cohérent : 22 `BrowserActionType`
tous routés dans `web/background.js` ; sous-ensemble DOM 13 actions → `web/dom_actions.js`.

**Fix** : `web/manifest.json` déclarait permission `offscreen` + `offscreen.html`/
`offscreen.js` en WAR, MAIS 0 code n'utilise `chrome.offscreen` et les fichiers
n'existent pas (ajout V10 commit a822434b, jamais implémenté). Retiré permission + WAR
refs. Manifeste honnête (CLAUDE.md et autres docs déjà à jour sur ce point — aucun
doc edit requis).

**Runtime = device-only** : chrome-devtools MCP ne peut pas unpacked-load (file picker
+ chrome:// restrictions). À valider device : UI Flutter render popup/sidePanel, slash
DOM exec, speech_bridge STT/TTS.

#### Bilan mission

- **chat_notifier.dart** : 4270 → 3862 lignes (cumul −408 sur 4 clusters extraits,
  ADR-029/030 + Bloc 6.1). Reste god object mais décomposition prouve le pattern.
- **flutter analyze** : 0/0 (89→0, 100% cleared).
- **flutter test** : 790/790 vert (752 base + 1 quota + 37 IATA).
- **backend pytest** : 39/39 vert.

**Reste (device-only, hors autonomie)** :
- Smoke-test Xiaomi 12 : mode vocal V16 (5 tours + barge-in), quota upload 50MB Pro vs
  5MB free UI stateful.
- Extension Chrome unpacked-load + UI Flutter render.
- Parsing vols round-trip lowercase (extraction dates **avant** sanitize).
- Audit Phase 2 : cibles safe restantes = `QuotaService` extraction de la garde
  `sendMessage`, routeurs `searchHotels`/`searchProducts`/`searchWeather` en services
  dédiés, `_buildStream` (~400 L) décomposition. Haut-risque (stateful runtime) → à
  ne pas faire en autonomie sans vérif device.

---

*Dernière mise à jour : 2026-06-17*

---

## ADR-033 : OmniVoice TTS — Backend Python avec fallback multi-moteur (2026-06-27)

**Date** : 2026-06-27
**Statut** : Accepté

### Contexte
Le TTS existant (flutter_tts natif, OpenRouter TTS payant Pro) produit une voix robotique en français.

### Décision
Intégration d'**OmniVoice** (k2-fsa/OmniVoice) comme moteur TTS prioritaire, exécuté côté backend Python.

### Chaîne de fallback
```
OmniVoice (backend, SOTA 646 langues, Auto Voice)
  → OpenRouter TTS (Pro uniquement, payant)
  → flutter_tts (universel, gratuit)
```

### Mode choisi
**Auto Voice** — Voice Design (`instruct`) entraîné sur EN+ZH uniquement, pas fiable pour FR.

### Conséquences
- ✅ Qualité TTS FR state-of-the-art
- ⚠️ CPU VPS = RTF ~1.8x → besoin GPU pour perf optimales
- ⚠️ Dépendance réseau (backend obligatoire pour OmniVoice)

### Prochaine étape
GPU Hetzner (ex: CX22 GPU) pour RTF < 0.1x, ou timeout → fallback flutter_tts.

---

*Dernière mise à jour : 2026-06-27*
