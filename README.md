# AironBot — AI Chat App + Chrome Extension

> **ChatGPT-like viral, cross-platform Flutter.** Application mobile (Android/iOS) + extension Chrome synchronisées en temps réel via Firebase. Gratuit & freemium, conçu pour 1M+ utilisateurs.

---

## Aperçu

AironBot est une application d'IA conversationnelle grand public s'appuyant sur **DeepSeek-V3** (gratuit, open-source, raisonnement state-of-the-art) pour les utilisateurs gratuits, et des modèles premium (Mistral Large 2, Groq Llama 3.3) pour les abonnés Pro. L'application mobile et l'extension Chrome partagent 95 % du code Flutter et se synchronisent instantanément via Firestore.

---

## Fonctionnalités

### Gratuit (Freemium viral)
| Fonctionnalité | Détail |
|---|---|
| Chat texte | Conversations illimitées, historique 30 jours |
| Chat voix | speech_to_text + flutter_tts (micro → texte → IA → synthèse) |
| Quota IA | 20 requêtes/jour (DeepSeek-V3) |
| Publicités | Bannières bas d'écran + vidéos rewarded (5 requêtes bonus) |
| Résumé / Traduction | Texte collé ou sélectionné |
| Sync app ↔ extension | Historique chats identique sur tous les appareils |
| Auth | Email / Google / Apple (Firebase Auth) |
| Dark / Light mode | Système ou manuel |
| Onboarding 30 s | 3 écrans, pas d'inscription obligatoire |

### Pro (9,99 €/mois — 99 €/an)
| Fonctionnalité | Détail |
|---|---|
| IA illimitée | Requêtes sans quota, contexte 128k tokens |
| Modèles premium | Mistral Large 2 / Groq Llama 3.3 70B |
| Projets & Dossiers | Organiser les chats par projet |
| Upload fichiers | PDF, Word, images (analyse contextuelle) |
| Génération PDF | Export de réponses en PDF ou slides |
| Latence prioritaire | File d'attente Pro < 2 s |
| Pubs optionnelles | Désactivables |
| Support prioritaire | Réponse < 24 h |

---

## Stack Technique

```
Flutter 3.24+  (Dart)
├── Mobile : Android 8+ / iOS 15+
├── Web    : Flutter Web → Chrome Extension (Manifest V3)
│
Firebase
├── Authentication  (email / Google / Apple)
├── Firestore       (users, chats, projets, quotas)
├── Cloud Functions (quotas, queues, webhooks Stripe)
├── FCM             (push notifications sync)
│
IA
├── DeepSeek-V3     (gratuit, API officielle)
├── Mistral Large 2 (pro, via OpenRouter)
├── Groq Llama 3.3  (pro, ultra-rapide)
│
Monétisation
├── RevenueCat      (abonnements iOS / Android / Web)
├── Google AdMob    (bannières, interstitiels, rewarded)
├── Stripe          (paiements web / extension)
│
DevOps
├── GitHub Actions  (CI/CD : test → build → deploy)
├── Fastlane        (Play Store / App Store Connect)
└── Chrome Web Store CLI
```

---

## Architecture Projet

```
airon_bot/
├── lib/
│   ├── main.dart
│   ├── app/
│   │   ├── router.dart          # GoRouter
│   │   └── theme.dart
│   ├── features/
│   │   ├── auth/
│   │   │   ├── data/            # FirebaseAuthRepository
│   │   │   ├── domain/          # User model
│   │   │   └── presentation/    # LoginScreen, OnboardingScreen
│   │   ├── chat/
│   │   │   ├── data/            # AI client (DeepSeek/OpenRouter), FirestoreChatRepo
│   │   │   ├── domain/          # Message, Conversation models
│   │   │   └── presentation/    # ChatScreen, ChatBubble, InputBar, VoiceButton
│   │   ├── projects/
│   │   │   ├── data/
│   │   │   └── presentation/    # ProjectsScreen (Pro)
│   │   ├── settings/
│   │   │   └── presentation/    # SettingsScreen, ApiKeyScreen
│   │   ├── monetization/
│   │   │   ├── ads/             # AdMob banners, rewarded
│   │   │   └── subscription/    # RevenueCat, PaywallScreen
│   │   └── onboarding/
│   ├── core/
│   │   ├── constants.dart
│   │   ├── secure_storage.dart
│   │   ├── firebase_options.dart
│   │   └── providers/           # Global Riverpod providers
│   └── shared/
│       ├── widgets/             # Composants réutilisables
│       └── extensions/
├── web/
│   └── manifest.json            # Chrome Extension Manifest V3
├── android/
├── ios/
├── functions/                   # Firebase Cloud Functions (Node.js)
│   ├── src/
│   │   ├── quotas.ts
│   │   ├── stripe-webhooks.ts
│   │   └── queue.ts
│   └── package.json
├── test/
├── integration_test/
├── .github/
│   ├── workflows/               # CI/CD GitHub Actions
│   └── skills/mobile-ai-chat/   # Skill Copilot
└── fastlane/
```

---

## Monétisation

### Modèle de revenus
```
Gratuit (acquisition virale)
  → 20 req/jour → mur de quota → upsell Pro
  → Pubs rewarded → incentive naturel

Pro (8–12 % conversion cible)
  → 9,99 €/mois × 10 000 users = ~100 k€/mois ARR
  → 99 €/an   × 10 000 users = ~1 M€/an ARR

Pubs (long tail)
  → 100k MAU × 0.05 €/user/jour = 5 000 €/jour passif
```

### RevenueCat — Plans
| Plan | Prix | Période |
|---|---|---|
| Pro Monthly | 9,99 € | Mensuel |
| Pro Yearly | 99 € | Annuel (économie 17 %) |
| Credits 50 | 2,99 € | One-time (50 requêtes) |
| Credits 200 | 9,99 € | One-time (200 requêtes) |

---

## Roadmap — 1 Million d'Utilisateurs

### Phase 1 — MVP (Semaines 1–4)
- [x] Scaffold Flutter + Firebase setup
- [ ] Auth (email + Google)
- [ ] Chat texte DeepSeek-V3 avec streaming
- [ ] Quotas Firestore (20 req/jour)
- [ ] Extension Chrome basique (même UI)
- [ ] Sync realtime Firestore

### Phase 2 — Monétisation (Semaines 5–8)
- [ ] RevenueCat abonnements Pro
- [ ] AdMob bannières + rewarded
- [ ] Paywall UI/UX premium
- [ ] Stripe webhooks (web)

### Phase 3 — Viral Features (Semaines 9–12)
- [ ] Chat voix (speech_to_text + TTS)
- [ ] Upload fichiers / PDF
- [ ] Partage social (screenshot réponse)
- [ ] Onboarding 30 s optimisé
- [ ] Referral program (+5 req/referral)

### Phase 4 — Scale (Semaines 13–20)
- [ ] Cloud Functions queue (haute charge)
- [ ] Modèles Pro (Mistral / Groq)
- [ ] Projets & dossiers Pro
- [ ] CI/CD Fastlane automatisé
- [ ] Play Store + App Store + Chrome Web Store

### Phase 5 — 1M Users (Mois 6+)
- [ ] PWA offline cache
- [ ] Multi-langue (i18n)
- [ ] Analytics avancés + A/B tests
- [ ] API publique (développeurs)
- [ ] Widget iOS / Android

---

## Démarrage Rapide

```bash
# Prérequis : Flutter 3.24+, Dart 3.5+, Firebase CLI, Node.js 20+

git clone https://github.com/votre-org/airon-bot.git
cd airon_bot

# Installation
flutter pub get

# Configuration (voir INSTALL-MOBILE.md)
cp .env.example .env
# → Renseigner DEEPSEEK_API_KEY, FIREBASE_PROJECT_ID, etc.

# Lancer en développement
flutter run -d android   # ou ios, chrome, emulator
```

Voir [INSTALL-MOBILE.md](./INSTALL-MOBILE.md) et [INSTALL-EXTENSION.md](./INSTALL-EXTENSION.md) pour les guides complets.

---

## Contribution

Pull requests bienvenues. Voir `.github/CONTRIBUTING.md`.  
Standards : MVVM + Riverpod, `very_good_analysis`, coverage ≥ 80 %.

---

## Licence

MIT — voir `LICENSE`.
