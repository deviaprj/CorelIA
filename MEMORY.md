# AironBot — Mémoire de Projet

Ce fichier contient les connaissances clés et décisions importantes pour le développement continu d'AironBot.

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
- Project ID : `aironbot-1773058753`
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

*Dernière mise à jour : 2026-05-04*
