# AironBot — Décisions Architecturales (ADR)

Ce fichier documente les décisions architecturales importantes prises durant le développement d'AironBot.

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

*Dernière mise à jour : 2026-05-21*
