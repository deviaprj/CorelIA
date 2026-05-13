# AUDIT TECHNIQUE — AironBot Transformation

> Date : 2026-04-24
> Branche : `br-openclaw`
> Auditeur : Agent Autonome Principal

---

## 1. STACK TECHNIQUE ACTUELLE

### 1.1 Frontend Mobile / Extension
| Composant | Version / Choix | État |
|---|---|---|
| Framework | Flutter 3.24+ (SDK >=3.0.0) | ✅ Stable |
| State Management | `flutter_riverpod` ^2.4.9 | ✅ MVVM bien appliqué |
| Navigation | `go_router` ^13.0.0 | ✅ Clean |
| UI | Material 3 + `flutter_markdown` | ✅ Responsive |
| Langue cible | Dart | ✅ |

### 1.2 Backend & Infrastructure
| Composant | Version / Choix | État |
|---|---|---|
| BaaS | Firebase (Core, Auth, Firestore, Functions, FCM) | ✅ Déployé |
| Auth | Firebase Auth (Email, Google, Apple, Anonymous) | ✅ Fonctionnel |
| DB | Cloud Firestore | ✅ Sync temps réel |
| Serverless | Firebase Functions (Node 20, TS) | ⚠️ Minimale (142 lignes) |
| Storage local | `flutter_secure_storage` + `shared_preferences` | ✅ Correct |

### 1.3 IA & LLM
| Client | Modèle cible | Implémentation | Streaming | État |
|---|---|---|---|---|
| `DeepSeekClient` | `deepseek-chat` (V3) | SSE direct | ✅ | ✅ |
| `OpenRouterClient` | Mistral Large, Llama 3.3 70B | SSE direct | ✅ | ✅ |
| `OllamaClient` | `kimi-k2.5:cloud` | SSE `application/x-ndjson` | ✅ | ⚠️ Cloud only, pas local |

**Problèmes critiques IA :**
- Pas de **chaînage de fallback** (si DeepSeek tombe, pas de bascule automatique).
- Pas de **tool use / function calling**.
- Pas de **recherche web** intégrée.
- Pas de **mémoire conversationnelle long terme** (hors les 20 derniers messages).
- `OllamaClient` pointe vers `https://ollama.com` (endpoint cloud erroné ; Ollama local = `http://localhost:11434`).

### 1.4 Voix
| Module | Package | État |
|---|---|---|
| STT (entrée) | `speech_to_text` ^7.1.0 | ✅ Basique (30s max, fr-FR) |
| TTS (sortie) | `flutter_tts` ^4.2.0 | ✅ Basique (parle bloc entier) |

**Lacunes voix :**
- Pas de **streaming vocal** (interruption, word-by-word TTS).
- Pas de **mode conversation mains-libres** (détection de wake-word, boucle écoute→réponse).
- Pas de **gestion des langues dynamiques**.

### 1.5 Monétisation
| Tier | Canal | Implémentation | État |
|---|---|---|---|
| Gratuit | Mobile | AdMob (bannière, interstitiel, récompensé) | ✅ |
| Gratuit | Web/Ext | Aucune pub (pas de SDK web AdMob) | ⚠️ Non monétisé |
| Pro | Mobile | RevenueCat (StoreKit + Play Billing) | ✅ |
| Pro | Web/Ext | Stripe Checkout + Webhooks (CF) | ✅ Partiel |
| Parrainage | Firestore | `referral_service.dart` | ✅ Code saisie manuelle |

**Lacunes monétisation :**
- Pas de **lien de parrainage traçable** (deep link + génération automatique).
- Pas de **système de crédits** (achat unitaire hors abonnement).
- Pas de **bandeau pub non-intrusif** avec consentement GDPR.

---

## 2. ARCHITECTURE EXISTANTE

```
lib/
├── main.dart                    # Entry point, init conditionnelle Firebase/AdMob/RevenueCat
├── app/
│   ├── theme.dart               # Thème clair/sombre
│   └── router.dart              # go_router avec guards (onboarding → auth → chats)
├── core/
│   ├── constants.dart           # Clés API compilées (dart-define), config globale
│   ├── secure_storage.dart      # Wrapper flutter_secure_storage
│   ├── platform_service.dart    # Détection plateforme (mobile/web/extension)
│   └── providers/               # Riverpod providers globaux
├── features/
│   ├── auth/                    # Firebase Auth + Mock (DEMO)
│   ├── chat/                    # IA clients, Firestore repo, quota, voice
│   ├── projects/                # Pro feature (écrans basiques)
│   ├── monetization/            # AdService, SubscriptionService, Paywall
│   ├── onboarding/              # 3 pages statiques
│   ├── settings/                # Thème, clé API perso, parrainage, logout
│   └── referral/                # Service Firestore de parrainage
└── shared/                      # Widgets communs, extensions
```

**Patterns identifiés :**
- ✅ MVVM respecté (`domain/` + `presentation/notifier` + `presentation/screens`).
- ✅ Repository pattern avec mock fallback (`isDemoMode`).
- ✅ Séparation UI / logique via Riverpod.
- ⚠️ Pas de **couche d'orchestration IA** (tout est dans `chat_notifier.dart` → God-object).
- ⚠️ Pas de **couche réseau abstraite** (`http.Client` direct dans chaque client IA).
- ⚠️ Pas de **cache local structuré** (hors Firestore offline implicit).

---

## 3. QUALITÉ DU CODE

### 3.1 Points forts
- Typage strict avec `very_good_analysis` ^6.0.0.
- Gestion des erreurs par exceptions spécialisées (`AiException`, `QuotaExceededException`).
- Mode DEMO élégant (`isDemoMode` global) pour tests sans Firebase.
- Streaming SSE optimisé avec `List.unmodifiable` pour éviter O(n²).
- Auto-scroll sur le chat avec `PostFrameCallback`.

### 3.2 Failles & dettes techniques

#### Sécurité
| Risque | Fichier | Gravité |
|---|---|---|
| Clés API compilées en dur dans l'APK/IPA via `--dart-define` | `core/constants.dart` | 🔴 **Élevée** |
| `isProProvider` retourne `true` en debug (`!kReleaseMode`) | `subscription_service.dart:56` | 🔴 **Critique** — permet de bypasser le paywall en debug build |
| Pas de proxy backend pour les appels IA | `ai_client.dart` | 🟡 Moyenne — clés exposées si reverse engineering |
| Pas de rate-limiting client-side | `chat_notifier.dart` | 🟡 Moyenne |
| `OPENROUTER_API_KEY` manquant du `.env` | `.env` | 🟡 Faible — fallback sur DeepSeek |
| Pas de certificate pinning | `http.Client` | 🟡 Faible — MITM possible sur réseaux non fiables |

#### Performance
- `chat_notifier.dart` fait `List.unmodifiable(updatedMessages)` à **chaque token SSE** → toujours une allocation O(n) par token, mais acceptable pour < 1000 tokens.
- Pas de **debounce** sur la saisie utilisateur.
- Pas de **pagination** sur l'historique des conversations (limite 50 côté Firestore mais pas de lazy load côté UI).

#### Tests
- ✅ Bonne couverture : unit (`test/core/`, `test/features/*`), widget (`test/widget_test.dart`), integration (`integration_test/*`), load (`test/load/`).
- ⚠️ Les tests de `ai_client.dart` sont probablement des mocks statiques (à vérifier).
- ⚠️ Pas de tests E2E pour le flux vocal.

---

## 4. FONCTIONNALITÉS IMPLÉMENTÉES

| Fonctionnalité | État | Notes |
|---|---|---|
| Chat texte avec streaming | ✅ 100% | DeepSeek + OpenRouter + Ollama |
| Historique conversations Firestore | ✅ 100% | Sync temps réel |
| Authentification (Email, Google, Apple) | ✅ 100% | |
| Onboarding 3 étapes | ✅ 100% | |
| Quotas gratuits (20/jour) | ✅ 100% | Cloud Function `checkQuota` |
| Reconnaissance vocale (STT) | ✅ 70% | 30s max, fr-FR fixe |
| Synthèse vocale (TTS) | ✅ 60% | Parle bloc entier, pas d'interruption fluide |
| Publicités AdMob | ✅ 80% | Mobile uniquement |
| Abonnements Pro (RevenueCat) | ✅ 80% | Mobile uniquement |
| Parrainage (code manuel) | ✅ 70% | Pas de deep links |
| Mode DEMO sans Firebase | ✅ 100% | Mock complet |
| Extension Chrome (Manifest V3) | ✅ 80% | Build script fonctionnel |

---

## 5. LACUNES vs OBJECTIFS AIRONBOT

| Objectif AironBot | Lacune actuelle | Impact |
|---|---|---|
| **Conversations naturelles** | Contexte limité 20 messages, pas de mémoire long terme | 🔴 Élevé |
| **Recherche web temps réel** | Aucun moteur de recherche intégré | 🔴 Élevé |
| **Voix mains-libres** | STT/TTS basiques sans boucle conversation | 🔴 Élevé |
| **Ollama local** | Client pointe vers cloud erroné, pas de détection local | 🔴 Élevé |
| **DeepSeek fallback** | Pas de chaînage Ollama → DeepSeek → OpenRouter | 🟡 Moyen |
| **Monétisation avancée** | Pas de crédits à l'unité, pas de liens traçables | 🟡 Moyen |
| **Tool use** | Pas de function calling | 🟡 Moyen |
| **Sécurité API keys** | Clés compilées dans le binaire | 🔴 Élevé |
| **Multi-agent backend** | Aucun orchestrateur côté serveur | 🟡 Moyen |
| **RAG / projects** | Projects existent mais sans indexation sémantique | 🟡 Moyen |

---

## 6. VÉRIFICATION DES VARIABLES D'ENVIRONNEMENT

### Fichier `.env` (courant)
```
OLLAMA_API_KEY=76c17430dbe942b284927d3fe8ba8a7c.rf87F0DSwUTPYm4Y8iqKBZ2r
DEEPSEEK_API_KEY=sk-f1a280f8a59443b8943099c40b2b263a
```

### Fichier `.env.example`
- ❌ `OLLAMA_API_KEY` **manquant**.
- ✅ `DEEPSEEK_API_KEY` présent.
- ✅ `OPENROUTER_API_KEY` présent (mais **non renseigné** dans `.env`).
- ✅ Toutes les variables AdMob, RevenueCat, Stripe, APP_ENV présentes.

### Actions requises
1. Ajouter `OLLAMA_API_KEY=` dans `.env.example`.
2. Vérifier si `OPENROUTER_API_KEY` doit être ajouté au `.env` réel.
3. **Sécurité** : les clés ci-dessus ne doivent **JAMAIS** être commitées en clair (gitignore OK).

---

## 7. SYNTHÈSE DU RAPPORT D'AVIATION

| Domaine | Score | Commentaire |
|---|---|---|
| Architecture | 7/10 | MVVM solide, mais couche IA à refactorer |
| Code Quality | 7/10 | Typage strict, mais god-objects et fuites sécu |
| Sécurité | 4/10 | Clés en dur, bypass paywall debug, pas de proxy IA |
| Performance | 6/10 | Streaming OK, mais pas de pagination ni cache avancé |
| Tests | 7/10 | Bonne couverture, manque E2E voix |
| Fonctionnalités | 5/10 | Chat OK, mais pas de recherche web, voix limitée, Ollama cassé |
| Monétisation | 6/10 | Ads + Subs OK, manque crédits et liens traçables |
| Documentation | 8/10 | ADR complets, CLAUDE.md précis |

---

*Fin de l'audit — Passage à la Phase 2 : Plan d'action.*
