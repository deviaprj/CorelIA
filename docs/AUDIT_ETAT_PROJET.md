# Rapport d'Audit — AironBot V2

**Date** : 2026-05-01
**Branche** : `br-AironBot-V2`
**Auditeur** : Claude Code (Audit automatique)
**Commit HEAD** : `a70e0636`

---

## 1. État Général du Projet

| Domaine | État | % Complet |
|---------|------|-----------|
| Chat IA (streaming, multi-provider) | Fonctionnel | 85% |
| Auth (Firebase, email/Google/Apple) | Fonctionnel | 80% |
| Firestore persistence | Fonctionnel | 90% |
| Extension Chrome (Manifest V3) | Basique | 30% |
| Recherche web | Partiel | 40% |
| TTS (lecture vocale) | Basique | 35% |
| Mode vocal conversation | Partiel / instable | 25% |
| Système Freemium (quota, ads, Pro) | Partiel | 50% |
| Upload images / vision IA | Non implémenté | 0% |
| Upload fichiers (PDF/DOCX/XLSX) | Non implémenté | 0% |
| Parrainage | Partiel | 40% |
| Tests Flutter | Existent, passants | 75% |
| Tests Backend | Existent, partiellement cassés | 50% |
| Lint / Analyse statique | 945 issues | 60% |

**Estimation globale** : ~55% d'avancement vers les objectifs V2 définis dans le cahier des charges.

---

## 2. Fonctionnalités Complètes et Opérationnelles

### 2.1 Chat IA
- **Streaming token-by-token** avec throttle (8 tokens / 150ms) pour réduire les rebuilds UI
- **Multi-provider** avec chaîne de fallback : Ollama local → DeepSeek-V3 → OpenRouter (Mistral)
- **Contexte limité aux 20 derniers messages** (correction du bug `.take()` initial — ADR-009)
- **Persistance Firestore** avec sync temps réel via `StreamProvider`
- **Mode DEMO** (`--dart-define=DEMO_MODE=true`) fonctionnant sans Firebase ni clés API
- **Gestion d'erreurs** : 401, 429, réseau, avec messages utilisateur
- **Recherche web injectable** : toggle dans l'AppBar, indicateur "Recherche en cours..."

### 2.2 Architecture & State Management
- **MVVM + Riverpod** : séparation Model/ViewModel/View respectée
- **Feature-based folder structure** avec `domain/`, `data/`, `presentation/`
- **Platform Service** : détection Android/iOS/Web/Extension fonctionnelle
- **Secure Storage** : `flutter_secure_storage` sur mobile, `shared_preferences` fallback web

### 2.3 Monetization (base)
- **AdMob** : bannière en bas du chat (mobile uniquement), IDs de test en debug
- **RevenueCat** : intégration iOS/Android, entitlements `pro`, offerings `default`
- **Stripe** : constantes configurées, webhook endpoint backend prévu
- **Quota server-side** : Cloud Function `checkQuota` (20 req/jour gratuit)

### 2.4 Extension Chrome
- **Manifest V3** avec side panel, popup, background service worker
- **Context menu** : "Demander à AironBot" sur sélection de texte
- **Content script** : capture sélection texte, envoi au background
- **Build script** (`scripts/build_extension.sh`) : build Flutter Web + packaging ZIP opérationnel
- **Suppression Service Worker Flutter** pour éviter conflits avec background.js

### 2.5 Auth
- **Firebase Auth** : Email, Google Sign-In, Anonymous
- **Mock auth repository** pour mode DEMO sans Firebase
- **Deep links** : `app_links` intégré pour parrainage

---

## 3. Fonctionnalités Partiellement Implémentées

### 3.1 Recherche Web — 40% complet
**Ce qui existe** :
- Recherche directe client-side via DuckDuckGo HTML scraping (`searchDirect`)
- Backend FastAPI avec `duckduckgo-search` lib + SerpAPI fallback
- Injection des résultats dans le contexte système de l'IA
- Indicateur visuel "Recherche web en cours..." dans le chat

**Ce qui manque** :
- Pas de fallback multi-provider côté client (Brave Search, DuckDuckGo API)
- Parsing HTML par regex — très fragile, cassera si DuckDuckGo change son HTML
- Pas de timeout explicite de 8s avec gestion d'erreur claire
- Pas de nettoyage HTML des pages récupérées (scripts, ads, nav)
- Pas de limite à 4000 tokens sur le contexte injecté
- URLs sources affichées dans le contexte IA mais pas explicitement dans la bulle de réponse
- Pas de logging structuré des échecs (URL, code, provider)

### 3.2 TTS (Text-to-Speech) — 35% complet
**Ce qui existe** :
- `flutter_tts` intégré avec `rate: 0.9`, `language: 'fr-FR'`
- Bouton lecture/arrêt dans la bulle de message

**Ce qui manque** :
- Aucun découpage intelligent par phrases/segments
- Aucune pause entre phrases (100–200ms) ou paragraphes (400ms)
- Pas de filtrage markdown (`**`, `#`, `` ` ``, `---`) avant TTS
- Pas de contrôle vitesse utilisateur (slider 0.5x → 2x)
- Backend TTS Ollama (`piper`) non fonctionnel en pratique — retourne du texte/SSML, pas d'audio

### 3.3 Mode Vocal Conversation — 25% complet
**Ce qui existe** :
- Architecture en états : `idle`, `listening`, `processingStt`, `thinking`, `speaking`, `error`
- Enregistrement audio WAV 16kHz via `record` + `just_audio`
- Service `VoiceConversationNotifier` avec pipeline conceptuel

**Ce qui manque** :
- Durée d'enregistrement **hardcodée à 5 secondes** (`await Future.delayed(const Duration(seconds: 5))`) — pas de VAD
- Pas de Voice Activity Detection (silence 1.5s = arrêt auto)
- Pas de mode push-to-talk
- STT backend Ollama (`/voice/stt`) encode l'audio en base64 et l'envoie à `/api/generate` — approche fondamentalement inefficace et non fonctionnelle
- Pas de retry automatique (3 tentatives) sur erreur réseau
- Pas de transcription temps réel affichée pendant l'écoute
- Le fallback vers `speech_to_text` natif n'est pas correctement branché dans le pipeline conversation

### 3.4 Système Freemium — 50% complet
**Ce qui existe** :
- Quota 20 requêtes/jour via Cloud Function `checkQuota`
- Snackbar "Quota journalier atteint. Passez en Pro !" avec CTA vers `/paywall`
- AdMob bannière (mobile)
- RevenueCat pour abonnements Pro (mobile)
- Écran paywall basique (`paywall_screen.dart`)

**Ce qui manque** :
- Pas de compteurs détaillés : vocal, recherche, images, fichiers
- Pas de limites par type de feature (tout passe par le compteur global 20 req/jour)
- Pas d'écran de récompense publicitaire (rewarded ads)
- Pas de streak quotidien / gamification
- Pas de notifications push de rappel
- Pas de partage social viral
- Pas d'essai Premium 7 jours sans CB
- Pas d'achats in-app ponctuels (pack messages, débloquer vocal)

### 3.5 Extension Chrome — 30% complet
**Ce qui existe** :
- Wrapper Flutter Web + Manifest V3
- Side panel + popup
- Context menu sélection texte

**Ce qui manque** :
- Gestion cookies automatique (bandeau refus)
- Sidebar IA avec contexte page courante
- Résumé de page en 1 clic
- Traduction de sélection
- Téléchargement médias (vidéos, images)
- Remplissage formulaires
- Scraping structuré
- Macros et automatisation
- Monitoring prix

---

## 4. Bugs Identifiés

### 4.1 Critiques

| ID | Bug | Fichier | Impact |
|----|-----|---------|--------|
| C1 | **Recherche web par regex HTML** — Parsing DuckDuckGo via regex fragile, cassera à la moindre évolution du site | `search_service.dart:91` | Fort — feature principale |
| C2 | **Mode vocal hardcodé à 5s** — Pas de VAD, l'enregistrement s'arrête après 5s fixe | `voice_conversation_service.dart:82` | Fort — UX vocale inutilisable |
| C3 | **Backend STT base64 inefficace** — Ollama `/api/generate` avec audio base64 = approche non fonctionnelle | `backend/agents/voice.py:45` | Fort — pipeline vocal backend inopérant |
| C4 | **Argument type error** — `dynamic` assigné à `String` dans `chat_request.dart` | `chat_request.dart:54` | Moyen — compilation/lint |
| C5 | **DeepSeek model obsolète** — `deepseek-chat` utilisé, doit migrer vers `deepseek-v4-flash` avant juillet 2026 | `constants.dart:15` | Moyen — rupture de service future |

### 4.2 Majeurs

| ID | Bug | Fichier | Impact |
|----|-----|---------|--------|
| M1 | **Backend tests cassés** — 2/4 tests échouent (`firebase_auth` mock incorrect) | `backend/tests/test_chat.py` | Moyen — régression backend |
| M2 | **Pas de retry API** — Aucune retry sur échec réseau DeepSeek/OpenRouter | `ai_client.dart` | Moyen — instabilité réseau |
| M3 | **Quota pas de fallback local** — Si Cloud Function indisponible, l'erreur remonte brute | `quota_service.dart` | Moyen — UX gratuits cassée |
| M4 | **TTS natif basique** — Lecture robotique sans pauses ni filtrage markdown | `voice_service.dart` | Moyen — qualité vocale |
| M5 | **Voice conversation pas de fallback STT natif** — Si backend Ollama down, pas de basculement vers `speech_to_text` | `voice_conversation_service.dart` | Moyen — pipeline vocal |

### 4.3 Mineurs

| ID | Bug | Fichier |
|----|-----|---------|
| m1 | 945 issues lint (unused imports, inference failures) | Multiples |
| m2 | `flutter_markdown` discontinué (remplacer par `flutter_markdown_plus`) | `pubspec.yaml` |
| m3 | Dépendances obsolètes : 117 packages ont des versions plus récentes | `pubspec.yaml` |
| m4 | `dio_client.dart` : `Future.delayed` sans type argument | `dio_client.dart:102` |
| m5 | `voice_conversation_service.dart` : `Future.delayed` sans type argument (×3) | `voice_conversation_service.dart` |
| m6 | `deep_link_service.dart` : unused import `referral_service.dart` | `deep_link_service.dart:7` |

---

## 5. Dette Technique Observable

### 5.1 Architecture
- **Flutter** (pas React Native/Expo comme indiqué dans le cahier des charges Phase 2) — cohérent avec ADR-001 mais divergent du cahier utilisateur
- **Backend FastAPI/Python** (pas Node.js/TypeScript) — cohérent avec l'implémentation actuelle
- **AI DeepSeek/OpenRouter** (pas Anthropic/Claude comme spécifié dans Phase 6) — divergence majeure du cahier

### 5.2 Code Quality
- 945 issues `flutter analyze` (1 erreur, ~80 warnings, ~864 hints)
- Nombreux `inference_failure_on_function_invocation` — manque de types génériques explicites
- Nombreux `unused_import` — nettoyage nécessaire

### 5.3 Dépendances Critiques Manquantes
Pour implémenter les features demandées, il manque dans `pubspec.yaml` :
- `image_picker` — upload images / caméra
- `file_picker` — upload fichiers
- `firebase_storage` — stockage fichiers/images
- `cached_network_image` — preview images
- `path_provider` — accès répertoires locaux (souvent transitif mais pas garanti)

### 5.4 Backend
- STT via base64 vers Ollama generate = anti-pattern technique (audio devrait aller vers un vrai endpoint STT comme Whisper API ou Ollama multimodal natif)
- Pas de rate limiting par utilisateur authentifié côté backend (seulement par IP via slowapi)

---

## 6. Plan d'Action Recommandé par Priorité

### Priorité 1 — Bugs Bloquants (expérience cassée)
1. **[C1] Fiabiliser la recherche web** :
   - Remplacer le scraping regex par l'API backend `duckduckgo-search` en priorité
   - Ajouter fallback client-side Brave Search API
   - Ajouter timeout 8s et gestion d'erreur utilisateur claire
   - Limiter contexte injecté à 4000 tokens
   - Afficher sources avec URLs dans la réponse

2. **[C2+C3+M5] Corriger le mode vocal** :
   - Implémenter VAD (silence 1.5s) ou mode push-to-talk
   - Corriger le backend STT : utiliser une vraie API Whisper (OpenAI/Whisper API) ou Ollama multimodal natif
   - Brancher fallback `speech_to_text` natif dans `VoiceConversationNotifier`
   - Ajouter retry 3 tentatives

3. **[C4] Corriger l'erreur de compilation** dans `chat_request.dart`

### Priorité 2 — Fonctionnalités Manquantes Critiques
4. **[0%] Implémenter upload et analyse d'images** :
   - Ajouter `image_picker`, `firebase_storage`
   - Compression 1920px/85%/JPEG
   - Conversion base64 pour API (DeepSeek n'a pas de vision ; nécessite migration vers OpenRouter avec modèle vision ou Anthropic)
   - Preview miniature dans bulle de message

5. **[0%] Implémenter upload et analyse de fichiers** :
   - Ajouter `file_picker`
   - Extraction PDF → `pdf-parse` backend ou lib Dart
   - Extraction DOCX → `mammoth` backend
   - Extraction XLSX → `xlsx` backend
   - Limite gratuite 2/jour 5MB, Pro illimité 50MB

### Priorité 3 — TTS et UX
6. **[C4] Corriger le TTS** :
   - Fonction `splitForTTS` : découpage par phrases avec filtrage markdown
   - Pauses inter-phrases 150ms, inter-paragraphes 400ms
   - Slider vitesse utilisateur
   - Nettoyage markdown avant lecture

### Priorité 4 — Système Freemium
7. **Implémenter compteurs détaillés** :
   - Messages, vocal, recherche, images, fichiers avec leurs propres limites
   - Paywalls non-intrusifs avec CTA premium
   - Écran essai Premium 7 jours

### Priorité 5 — Extension Chrome
8. **Gestion cookies automatique**
9. **Sidebar IA avec contexte page**
10. **Téléchargement médias basique**

---

## 7. Outils Installés / Disponibles

| Outil | Version | Statut |
|-------|---------|--------|
| Flutter SDK | 3.24.0 | Installé dans `$HOME/flutter` |
| Dart | 3.5.0 | Inclus dans Flutter |
| Android SDK | 36.0.0 | Présent (licences acceptées) |
| Java | OpenJDK | Présent |
| Python | 3.12.3 | Système |
| Backend venv | Python 3.12 | Présent (`backend/venv/`) |
| Chrome | — | Disponible pour tests web/extension |

---

## 8. Résumé Exécutif

AironBot V2 est une application Flutter cross-platform (mobile + extension Chrome) avec une architecture solide (MVVM + Riverpod, Firebase, multi-provider IA). Le chat streaming, l'authentification, la persistance Firestore et la monetization de base fonctionnent.

**Cependant**, les 4 bugs critiques identifiés dans le cahier des charges sont confirmés :
1. **TTS** est basique et robotique (pas de découpage, pas de pauses)
2. **Mode vocal** est quasi-inutilisable (5s fixe, pas de VAD, backend STT non fonctionnel)
3. **Recherche web** repose sur du scraping regex fragile
4. **Upload images/fichiers** est totalement absent (0%)

Le backend FastAPI est fonctionnel pour le chat streaming et la recherche DuckDuckGo, mais le endpoint vocal Ollama est fondamentalement mal conçu. Les tests Flutter passent mais les tests backend ont des mocks cassés.

**Recommandation** : Commencer par Priorité 1 (bugs bloquants) avant d'ajouter des features. La migration du modèle DeepSeek (`deepseek-chat` → `deepseek-v4-flash`) doit être traitée en parallèle.

---

*Fin du rapport d'audit — Phase 1 terminée.*
