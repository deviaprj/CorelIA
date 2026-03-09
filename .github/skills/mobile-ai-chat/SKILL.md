# Mobile AI Chat App + Chrome Extension (Flutter Cross-Platform)

## Objectif
Développe mode autonome : app Android/iOS + extension Chrome identique (UI/foncs sync via Firebase). Évolutions/corrections pushées = sync instantané. UX ChatGPT-like viral : texte/voix, gratuit (DeepSeek-V3 API gratuite), freemium (abos via Stripe, pubs AdMob/Google Ads).

## Stack Obligatoire (Performant/Rapide 2026)
- **Frontend** : Flutter 3.24+ (Dart) – 95% code partagé mobile/web. Extension Chrome : `flutter build web` → manifest V3.
- **Backend** : Firebase (Auth: email/Google/Apple; Firestore: users/chats/projets; Functions: quotas/queues; FCM push sync).
- **IA Gratuit** : DeepSeek-V3 API (open-source, top perf raisonnement). Payant : Mistral Large 2 / Groq Llama3 via OpenRouter.
- **Autres** : speech_to_text (voix), file_picker (fichiers), pdf lib (génération pro), revenuecat (abos cross-platform).

## Règles Développement Autonome
1. **Sync Auto** : Tout code UI/logique partagé. Firebase listeners pour chats/projets sync realtime (app ↔ extension).
2. **Quotas** : Gratuit : 20 req/jour (équilibre viral/retention). Pro : illimité + contexte 128k. File d'attente Cloud Functions si surcharge.
3. **Monétisation** :
   - Pubs : google_mobile_ads (bannières/interstitiels), rewarded_video (bonus req).
   - Freemium : RevenueCat pour abos mensuel (9.99€) / annuel (99€), packs crédits.
4. **Fonctionnalités Clés** :
   | Gratuit | Pro |
   |---------|-----|
   | Texte/voix basique, résumé/traduction, 20 req/j | Contextes longs, projets/dossiers, PDF/slides, priorité |
   | Pubs obligatoires | Pubs optionnelles |
5. **Émulateur Optimisé** : Toujours tester Android/iOS émulateurs + Chrome (flutter run -d chrome). Auto-génère APK/IPA/ZIP extension.
6. **Qualité** : Clean code MVVM (Riverpod), tests unitaires/integration 80% coverage. Publier Play Store/App Store/Chrome Web Store auto via Fastlane/CI GitHub Actions.
7. **Viral** : Partage social (screenshots réponses), onboarding 30s, dark/light mode.

## Workflow Autonome
- `@copilot: Génère app complète : structure Flutter, Firebase setup, IA integration, sync logic.`
- Implémente feature-by-feature : auth → chat → voix → pubs → pro → tests.
- Optimise perf : lazy loading, caching réponses IA.
- Génère manifest.json pour extension, adapte web build.

**Prompt Utilisation** : "Crée [feature] pour l'app AI Chat Flutter, sync app/extension via Firebase."
