# Rapport d'Audit — AironBot V2

**Date** : 2026-05-01
**Branche** : `br-AironBot-V2`
**Auditeur** : Claude Code (Audit automatique)
**Commit HEAD** : `d9e74e77`
**Fichiers modifiés non commités** : 2 (`ai_client.dart`, `chat_notifier.dart`)

---

## 1. État Général du Projet

| Domaine | État | % Complet |
|---------|------|-----------|
| Chat IA (streaming, multi-provider, retry) | Fonctionnel | 90% |
| Auth (Firebase, email/Google/Apple, mock) | Fonctionnel | 80% |
| Firestore persistence | Fonctionnel | 90% |
| Recherche web (backend + fallback direct) | Fonctionnel | 75% |
| TTS (lecture vocale naturelle) | Fonctionnel | 75% |
| Mode vocal conversation (VAD natif) | Fonctionnel | 70% |
| Upload images (galerie/camera) | Implémenté | 80% |
| Upload fichiers (PDF/DOCX/XLSX) | Implémenté | 70% |
| Extension Chrome (Manifest V3) | Basique | 30% |
| Système Freemium (quota, ads, Pro, credits) | Partiel | 60% |
| Parrainage | Partiel | 40% |
| Tests Flutter | Existent | 75% |
| Tests Backend | Partiellement cassés | 50% |
| Lint / Analyse statique | ~945 issues | 60% |

**Estimation globale** : **~65%** d'avancement vers les objectifs V2.

### Évolution depuis le dernier audit (commit a70e0636 → d9e74e77)

- ✅ **Retry API** : ajout de 2 tentatives avec backoff exponentiel sur erreurs 5xx/429
- ✅ **VAD natif** : `speech_to_text` avec `pauseFor` au lieu du hardcode 5s
- ✅ **TTS naturel** : `TtsNaturalService` avec `cleanMarkdown()`, strip emojis, strip sources
- ✅ **Recherche web** : fallback multi-provider (backend cloud → DuckDuckGo direct)
- ✅ **Upload images** : `ImageUploadService` avec galerie + caméra, compression auto
- ✅ **Upload fichiers** : `FileUploadService` avec extraction PDF/DOCX/XLSX pure Dart
- ✅ **Crédits locaux** : fallback `CreditService` si Cloud Function quota indisponible
- ✅ **File quota** : `FileQuotaService` local (2 fichiers/jour gratuit)
- ✅ **Pagination UI** : `displayCount` + `loadMoreHistory()` dans le ChatState
- ✅ **Sources web structurées** : `searchSources` dans Message, format liste + markdown
- 🔄 **Simplification historique** : suppression du summarize Ollama, `take(20)` direct (en cours, non commité)

---

## 2. Fonctionnalités Complètes et Opérationnelles

### 2.1 Chat IA (90%)
- **Streaming token-by-token** avec throttle (8 tokens / 150ms)
- **Multi-provider** avec chaîne de fallback : Ollama local → DeepSeek-V3 → OpenRouter
- **Retry automatique** : 2 tentatives max sur erreurs 5xx/429 avec délai exponentiel
- **Contexte limité aux 20 derniers messages** (`.reversed.take(20).reversed`)
- **Persistance Firestore** avec sync temps réel via `StreamProvider`
- **Mode DEMO** (`--dart-define=DEMO_MODE=true`) fonctionnel sans Firebase
- **Gestion d'erreurs** : 401, 429, réseau, avec messages utilisateur en français
- **Recherche web injectable** : toggle dans l'AppBar, contexte système formaté

### 2.2 Architecture & State Management (85%)
- **MVVM + Riverpod** : `domain/`, `data/`, `presentation/` respectés
- **Feature-based structure** cohérente sur tous les modules
- **Platform Service** : détection Android/iOS/Web/Extension
- **Secure Storage** : `flutter_secure_storage` + fallback `shared_preferences`
- **Router GoRouter** avec redirection auth/onboarding

### 2.3 Auth (80%)
- **Firebase Auth** : Email, Google Sign-In, Anonymous
- **Mock auth repository** pour mode DEMO (compte test automatique)
- **Deep links** : `app_links` intégré pour parrainage

### 2.4 Recherche Web (75%)
- **Backend cloud** : `/search` endpoint FastAPI avec `duckduckgo-search` lib
- **Fallback client-side** : scraping DuckDuckGo HTML pure Dart (autonome)
- **Timeout 8s** explicite sur toutes les requêtes
- **Contexte limité à ~16000 caractères** (~4000 tokens)
- **Sources affichées** en markdown dans la réponse + liste structurée `searchSources`

### 2.5 TTS Naturel (75%)
- **Nettoyage markdown** : `cleanMarkdown()` supprime `**`, `#`, code blocks, liens, images, citations
- **Strip emojis** : détection complète Unicode emoji (18 plages)
- **Strip sources** : suppression section "Sources:" avant lecture
- **Vitesse réglable** : slider 0.5x → 2.0x, pitch réglable
- **Completion handler** : attente réelle de fin de parole avant de rendre la main

### 2.6 Upload Images & Fichiers
- **Images** (80%) : galerie + caméra, compression auto >2MB, max 1920px, base64
- **Fichiers** (70%) : PDF (regex extraction), DOCX (XML parsing), XLSX (excel lib), TXT/CSV/MD
- **Quota fichiers** : 2/jour gratuit, Pro illimité, limite 5MB gratuit / 50MB Pro
- **Injection contexte** : `fileContextMessage` dans le système prompt (limité à 15000 chars)

### 2.7 Monetization
- **Quota server-side** : Cloud Function `checkQuota` (20 req/jour gratuit)
- **Quota fallback local** : `CreditService` + `FileQuotaService` si Cloud Function down
- **AdMob** : bannière (mobile), interstitiel, rewarded (IDs test en debug)
- **RevenueCat** : iOS/Android subscriptions, entitlements `pro`
- **Stripe** : constantes configurées pour web/extension

---

## 3. Fonctionnalités Partiellement Implémentées

### 3.1 Mode Vocal Conversation — 70% complet
**Ce qui existe** :
- Pipeline complet : `listening → thinking → speaking → idle` en boucle
- VAD via `speech_to_text.pauseFor` (silence detection native)
- Transcription temps réel affichée dans l'UI
- Stop/start réactivable (le bouton vocal reste fonctionnel après arrêt)
- Micro coupé avant TTS pour éviter écho/monologue IA
- Fallback `speech_to_text` natif intégré

**Ce qui manque** :
- Pas de mode push-to-talk alternatif
- Pas de retry automatique si STT échoue
- Timeout de 60s pour la réponse IA (300 tentatives × 200ms) — acceptable mais pas configurable

### 3.2 Extension Chrome — 30% complet
**Ce qui existe** :
- Manifest V3 avec side panel, popup, background service worker
- Context menu "Demander à AironBot" sur sélection texte
- Content script capture sélection
- Build script (`scripts/build_extension.sh`) opérationnel

**Ce qui manque** :
- Gestion cookies automatique (bandeau refus)
- Sidebar IA avec contexte page courante
- Résumé de page en 1 clic
- Traduction de sélection
- Téléchargement médias, remplissage formulaires
- Scraping structuré, macros, monitoring prix

### 3.3 Système Freemium — 60% complet
**Ce qui existe** :
- Quota 20 req/jour (Cloud Function + fallback CreditService local)
- Quota fichiers 2/jour (FileQuotaService local)
- Snackbar "Quota journalier atteint" avec CTA paywall
- Écran paywall basique

**Ce qui manque** :
- Compteurs détaillés par type (messages vs vocal vs recherche vs fichiers)
- Écran rewarded ads fonctionnel (endpoint existant mais UI non intégrée)
- Streak quotidien / gamification
- Notifications push de rappel quota
- Essai Premium 7 jours sans CB
- Achats in-app ponctuels (pack messages, débloquer vocal)
- Partage social viral

### 3.4 Extraction Fichiers — 70% complet
**Ce qui existe** :
- PDF : extraction regex des opérateurs `Tj`/`T'` + hex strings
- DOCX : parsing XML `word/document.xml`
- XLSX : lib `excel` avec parcours feuilles/rows/cells
- TXT/CSV/MD : lecture directe UTF-8

**Ce qui manque** :
- PDF complexes (scannés, encodages exotiques) → fallback texte partiel
- Pas de preview UI avant envoi
- Pas d'indicateur de progression pendant l'extraction
- Pas de cache des extractions pour réutilisation

### 3.5 Parrainage — 40% complet
- `ReferralService` et `DeepLinkService` existent
- Pas d'UI de parrainage intégrée dans les paramètres
- Pas de tracking des conversions

---

## 4. Bugs Identifiés

### 4.1 Critiques

| ID | Bug | Fichier | Impact |
|----|-----|---------|--------|
| C1 | **DeepSeek model obsolète** — `deepseek-chat` sera décommissionné en juillet 2026. Doit migrer vers `deepseek-v4-flash` | `constants.dart:17`, `chat_router.py:59` | Rupture de service imminente |
| C2 | **Backend STT fondamentalement cassé** — Envoie l'audio en base64 dans un prompt textuel à `/api/generate`. Aucun modèle Ollama ne peut traiter ça. | `backend/agents/voice.py:49-51` | Pipeline vocal backend inopérant |
| C3 | **Recherche web par regex HTML fragile** — Parsing DuckDuckGo HTML cassera si le site change son markup | `search_service.dart:122-141` | Feature principale — fallback existe |

### 4.2 Majeurs

| ID | Bug | Fichier | Impact |
|----|-----|---------|--------|
| M1 | **Backend tests cassés** — 2/4 tests échouent (mock `firebase_auth` incorrect) | `backend/tests/test_chat.py` | Régression backend |
| M2 | **OllamaClient pointe vers ollama.com** — L'URL `https://ollama.com/api/chat` n'est pas une API utilisable. Ollama Cloud nécessite une URL spécifique par utilisateur. | `ai_client.dart:178` | Client Ollama cloud non fonctionnel |
| M3 | **Quota fallback local pas thread-safe** — `CreditService` utilise `shared_preferences` sans lock | `credit_service.dart` | Conditions de concurrence |
| M4 | **Pas de retry dans le mode vocal** — Si STT natif échoue, pas de nouvelle tentative automatique | `voice_conversation_service.dart` | UX vocale |

### 4.3 Mineurs

| ID | Bug | Fichier |
|----|-----|---------|
| m1 | `flutter_markdown` discontinué (remplacer par `flutter_markdown_plus`) | `pubspec.yaml:65` |
| m2 | 117 packages ont des versions plus récentes disponibles | `pubspec.yaml` |
| m3 | `image_upload_service.dart` : `width`/`height` toujours à 0 (non extraits) | `image_upload_service.dart:96-97` |
| m4 | `TtsNaturalService` : `_tts` est un `FlutterTts` non disposé proprement | `tts_natural_service.dart` |
| m5 | 1 TODO restant : activer le certificate pinning dans `dio_client.dart:56` | `dio_client.dart` |
| m6 | `file_upload_service.dart` : regex PDF fragile pour PDF complexes/scannés | `file_upload_service.dart:110-144` |

---

## 5. Dette Technique Observable

### 5.1 Architecture
- **Divergence cahier des charges** : Flutter au lieu de React Native, Python/FastAPI au lieu de Node.js/TypeScript — documenté et assumé (ADR-001)
- **Double implémentation** : recherche web existe côté client (DuckDuckGo scraping) ET côté backend (FastAPI) — redondant mais justifié par l'exigence d'autonomie
- **Modèles IA** : DeepSeek (gratuit), OpenRouter (Pro) — pas de Claude/Anthropic comme dans le cahier Phase 6

### 5.2 Code Quality
- **~945 issues `flutter analyze`** : 1 erreur, ~80 warnings, ~864 hints
- **Types faibles** : nombreux `inference_failure_on_function_invocation`
- **Imports non utilisés** : nettoyage nécessaire dans plusieurs fichiers
- **`Future.delayed` sans type argument** : `dio_client.dart`, `voice_conversation_service.dart`

### 5.3 Dépendances à Surveiller
- `flutter_markdown: ^0.7.0` → discontinué, migrer vers `flutter_markdown_plus`
- `flutter_tts: ^4.2.0` — version stable mais limitation TTS natif Android/iOS
- `record: ^6.0.0` — stable, utilisé pour capture avancée (non critique)

### 5.4 Backend
- **STT via base64 dans `/api/generate`** = anti-pattern. Devrait utiliser une vraie API Whisper (OpenAI, Groq, ou Whisper local via HTTP)
- **Pas de rate limiting par utilisateur** (seulement par IP via slowapi)
- **Redis requis** pour rate limiting — fallback mémoire existe mais non testé
- **Ollama cloud URL** : `ollama.com` n'expose pas d'API utilisable publiquement

### 5.5 Tests
- Tests Flutter passent (couverture core + chat + auth + monetization)
- Tests backend partiellement cassés (mocks Firebase incorrects)
- Pas de tests pour `VoiceConversationNotifier`, `TtsNaturalService`, `FileUploadService`
- Pas de tests d'intégration vocale

---

## 6. Plan d'Action Recommandé par Priorité

### Priorité 1 — Critique (bugs bloquants)

1. **[C1] Migrer le modèle DeepSeek** :
   - Remplacer `deepseek-chat` → `deepseek-v4-flash` dans `constants.dart` et `chat_router.py`
   - Vérifier que l'API key fonctionne avec le nouveau modèle
   - Échéance : **avant juillet 2026**

2. **[C2] Corriger le backend STT** :
   - Remplacer le endpoint `/voice/stt` par une vraie intégration Whisper API (Groq Whisper ou OpenAI Whisper)
   - OU supprimer complètement le endpoint STT backend et ne garder que le STT natif
   - Actuellement le backend STT est inutilisable — le client utilise déjà `speech_to_text` natif

3. **[M2] Corriger OllamaClient** :
   - `https://ollama.com/api/chat` n'est pas un endpoint API valide
   - Soit documenter l'URL Ollama cloud réelle, soit supprimer ce client
   - Le client utilise déjà le fallback DeepSeek/OpenRouter correctement

### Priorité 2 — Extension Chrome

4. **Gestion cookies automatique** — priorité pour fonctionnement seamless
5. **Sidebar IA avec contexte page courante** — killer feature extension
6. **Résumé de page en 1 clic** — différenciateur

### Priorité 3 — Système Freemium

7. **Compteurs détaillés par type de requête** (messages, vocal, fichiers)
8. **Intégration rewarded ads** pour +5 requêtes
9. **Essai Premium 7 jours sans CB**
10. **UI parrainage** dans les paramètres

### Priorité 4 — Qualité

11. **Réduire les issues lint** : cibler les warnings d'abord (~80)
12. **Réparer les tests backend** (mocks Firebase)
13. **Ajouter tests pour les services vocaux et upload**

---

## 7. Outils et Environnement

| Outil | Version | Statut |
|-------|---------|--------|
| Flutter SDK | 3.24.0 | Installé (`$HOME/flutter`) |
| Dart | 3.5.0 | Inclus |
| Android SDK | 36.0.0 | Licences acceptées |
| Java | OpenJDK | Présent |
| Python | 3.12.3 | Système |
| Backend venv | Python 3.12 | Présent (`backend/venv/`) |
| Chrome | — | Tests web/extension |
| Redis | — | Non vérifié (optionnel) |

### Packages Dart clés (pubspec.yaml)
- **State** : `flutter_riverpod: ^2.4.9`
- **Navigation** : `go_router: ^13.0.0`
- **Firebase** : `firebase_core`, `firebase_auth`, `cloud_firestore`, `cloud_functions`, `firebase_messaging`
- **AI/HTTP** : `http`, `dio`, `connectivity_plus`
- **Voice** : `speech_to_text`, `flutter_tts`, `record`, `just_audio`, `permission_handler`
- **Monetization** : `google_mobile_ads`, `purchases_flutter`
- **Files** : `image_picker`, `file_picker`, `archive`, `excel`, `xml`, `flutter_image_compress`

### Packages Python backend (requirements.txt)
- `fastapi`, `uvicorn`, `httpx`, `pydantic`, `pydantic-settings`
- `slowapi`, `redis`, `duckduckgo-search`
- `firebase-admin`, `pytest`, `pytest-asyncio`

---

## 8. Résumé Exécutif

AironBot V2 est une application Flutter cross-platform (mobile + extension Chrome) avec une architecture solide (MVVM + Riverpod). **Le chat IA avec streaming, retry, et multi-provider est mature (90%).** L'authentification, la persistance Firestore, et la monetization de base fonctionnent.

**Progrès significatifs depuis le dernier audit** :
- Le TTS est passé de "basique et robotique" à "naturel" avec `cleanMarkdown()` complet
- Le mode vocal utilise maintenant VAD natif au lieu d'un hardcoded 5s
- La recherche web a un fallback multi-provider (backend cloud + DuckDuckGo direct)
- L'upload images et fichiers est implémenté (extraction PDF/DOCX/XLSX pure Dart)
- Le retry API et le fallback quota local (crédits) ont été ajoutés

**Risques majeurs restants** :
1. **DeepSeek model obsolète** (`deepseek-chat` décommissionné juillet 2026) — migration nécessaire
2. **Backend STT inopérant** — le client utilise déjà le STT natif, le backend vocal est du code mort
3. **OllamaClient URL invalide** — `ollama.com/api/chat` n'existe pas
4. **Extension Chrome** à seulement 30% — fonctionnalités killer manquantes

**Recommandation** : Migrer le modèle DeepSeek en priorité (échéance juillet 2026), nettoyer le backend vocal (code mort), puis concentrer les efforts sur l'extension Chrome et le système freemium.

---

*Fin du rapport d'audit — 2026-05-01*
